import Foundation

/// Reads Codex sessions (CLI + Codex Desktop) from ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
enum CodexScanner {
    static func scan(cutoff: Date) -> [AgentThread] {
        let root = ScanCore.home + "/.codex/sessions"
        return ScanCore.recentFiles(root: root, suffix: ".jsonl", cutoff: cutoff)
            .compactMap { parse(path: $0.path, mtime: $0.mtime) }
    }

    private static func parse(path: String, mtime: Date) -> AgentThread? {
        let head = ScanCore.headLines(path, bytes: Config.headBytes).compactMap(ScanCore.json)
        guard let meta = head.first(where: { $0["type"] as? String == "session_meta" }),
              let payload = meta["payload"] as? [String: Any],
              let id = payload["id"] as? String else { return nil }

        if payload["thread_source"] as? String == "subagent" { return nil }
        if (payload["source"] as? [String: Any])?["subagent"] != nil { return nil }

        let cwd = payload["cwd"] as? String ?? ScanCore.home
        let originator = payload["originator"] as? String ?? ""
        let source: AgentSource = originator.lowercased().contains("desktop") ? .codexApp : .codexCLI

        let tail = ScanCore.tailLines(path, bytes: Config.tailBytes).compactMap(ScanCore.json)
        var content: ThreadStatus?
        var summaryParts: [String] = []
        for rec in tail.reversed() {
            guard let payload = rec["payload"] as? [String: Any],
                  let ptype = payload["type"] as? String else { continue }
            if summaryParts.count < 2, summaryParts.joined().count < 80,
               let s = assistantText(payload, ptype: ptype) {
                summaryParts.append(s)
            }
            if content == nil {
                switch ptype {
                case "error":
                    content = .error
                case "turn_aborted":
                    content = .needsInput // user interrupted; it's waiting on them
                case "task_complete":
                    content = .done
                case "task_started", "user_message", "function_call", "custom_tool_call",
                     "local_shell_call", "reasoning", "web_search_call":
                    content = .working
                case "message":
                    content = (payload["role"] as? String == "user") ? .working : .done
                case "agent_message":
                    let m = payload["message"] as? String ?? ""
                    content = ScanCore.endsAsQuestion(m) ? .needsInput : .done
                default:
                    break // token_count, turn_context, world_state...
                }
            }
            if content != nil, summaryParts.count >= 2 { break }
        }

        let summary = ScanCore.clean(summaryParts.reversed().joined(separator: " — "), max: 300)
        let title = bestTitle(head: head, tail: tail)
            ?? (summary.isEmpty ? "Codex session" : TitleMaker.make(summary))
        return AgentThread(id: id, source: source, title: title, summary: summary,
                           cwd: cwd, filePath: path, lastActivity: mtime,
                           status: ScanCore.finalStatus(content: content ?? .done, mtime: mtime))
    }

    private static func assistantText(_ payload: [String: Any], ptype: String) -> String? {
        if ptype == "agent_message", let m = payload["message"] as? String, !m.isEmpty { return m }
        if ptype == "message", payload["role"] as? String == "assistant",
           let content = payload["content"] as? [[String: Any]] {
            let text = content.compactMap { $0["type"] as? String == "output_text" ? $0["text"] as? String : nil }
                .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func bestTitle(head: [[String: Any]], tail: [[String: Any]]) -> String? {
        for rec in head { if let t = userText(rec) { return TitleMaker.make(t) } }
        for rec in tail.reversed() { if let t = userText(rec) { return TitleMaker.make(t) } }
        return nil
    }

    private static func userText(_ rec: [String: Any]) -> String? {
        guard let payload = rec["payload"] as? [String: Any],
              let ptype = payload["type"] as? String else { return nil }
        var text: String?
        if ptype == "user_message" { text = payload["message"] as? String }
        if ptype == "message", payload["role"] as? String == "user",
           let content = payload["content"] as? [[String: Any]] {
            text = content.first { $0["type"] as? String == "input_text" }?["text"] as? String
        }
        guard var t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        if t.hasPrefix("<") || t.hasPrefix("# AGENTS.md") { return nil } // env/instruction noise
        if let r = t.range(of: "<environment_context") { t = String(t[..<r.lowerBound]) }
        t = t.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) // markdown header prompts
        return t.isEmpty ? nil : t
    }
}
