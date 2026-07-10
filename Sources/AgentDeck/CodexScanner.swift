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
        var working = false
        var decided = false
        var summary: String?
        for rec in tail.reversed() {
            guard let payload = rec["payload"] as? [String: Any],
                  let ptype = payload["type"] as? String else { continue }
            if summary == nil, let s = assistantText(payload, ptype: ptype) {
                summary = ScanCore.clean(s, max: 280)
            }
            if decided { continue } // keep walking only to find a summary
            switch ptype {
            case "task_complete", "turn_aborted", "error":
                working = false; decided = true
            case "task_started", "user_message", "function_call", "custom_tool_call",
                 "local_shell_call", "reasoning", "web_search_call":
                working = true; decided = true
            case "message":
                let role = payload["role"] as? String
                working = (role == "user"); decided = true
            case "agent_message":
                working = false; decided = true
            default:
                continue // token_count, turn_context, world_state...
            }
            if decided, summary != nil { break }
        }

        let title = bestTitle(head: head, tail: tail) ?? "Codex session"
        return AgentThread(id: id, source: source, title: title, summary: summary ?? "",
                           cwd: cwd, filePath: path, lastActivity: mtime,
                           status: ScanCore.finalStatus(contentSaysWorking: working, mtime: mtime))
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
        for rec in head { if let t = userText(rec) { return ScanCore.clean(t) } }
        for rec in tail.reversed() { if let t = userText(rec) { return ScanCore.clean(t) } }
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
