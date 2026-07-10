import Foundation

/// Reads Claude Code sessions (CLI + Claude desktop app) from ~/.claude/projects/*/*.jsonl
enum ClaudeScanner {
    static func scan(cutoff: Date) -> [AgentThread] {
        let root = ScanCore.home + "/.claude/projects"
        return ScanCore.recentFiles(root: root, suffix: ".jsonl", cutoff: cutoff)
            .compactMap { parse(path: $0.path, mtime: $0.mtime) }
    }

    private static func parse(path: String, mtime: Date) -> AgentThread? {
        let tail = ScanCore.tailLines(path, bytes: Config.tailBytes).compactMap(ScanCore.json)
        guard !tail.isEmpty else { return nil }

        var sessionId: String?
        var cwd: String?
        var entrypoint: String?
        var summary: String?
        var working = false
        var foundMessage = false

        for rec in tail.reversed() {
            if sessionId == nil { sessionId = rec["sessionId"] as? String }
            if cwd == nil { cwd = rec["cwd"] as? String }
            if entrypoint == nil { entrypoint = rec["entrypoint"] as? String }
            if summary == nil, rec["type"] as? String == "assistant", let s = assistantText(rec) {
                summary = ScanCore.clean(s, max: 280)
            }
            guard !foundMessage, let type = rec["type"] as? String else { continue }
            if rec["isSidechain"] as? Bool == true { return nil } // subagent transcript
            switch type {
            case "progress":
                working = true; foundMessage = true
            case "user":
                working = true; foundMessage = true // tool result or fresh prompt: model's turn
            case "assistant":
                working = hasToolUse(rec); foundMessage = true
            default:
                continue // summary, file-history-snapshot, last-prompt, pr-link...
            }
        }
        guard let id = sessionId, foundMessage else { return nil }

        let head = ScanCore.headLines(path, bytes: Config.headBytes).compactMap(ScanCore.json)
        let title = bestTitle(head: head, tail: tail) ?? "Claude session"
        let source: AgentSource = (entrypoint?.hasPrefix("claude-desktop") == true) ? .claudeApp : .claudeCLI
        return AgentThread(id: id, source: source, title: title, summary: summary ?? "",
                           cwd: cwd ?? ScanCore.home, filePath: path,
                           lastActivity: mtime,
                           status: ScanCore.finalStatus(contentSaysWorking: working, mtime: mtime))
    }

    private static func hasToolUse(_ rec: [String: Any]) -> Bool {
        guard let msg = rec["message"] as? [String: Any],
              let content = msg["content"] as? [[String: Any]] else { return false }
        return content.contains { $0["type"] as? String == "tool_use" }
    }

    private static func assistantText(_ rec: [String: Any]) -> String? {
        guard rec["isSidechain"] as? Bool != true,
              let msg = rec["message"] as? [String: Any],
              let blocks = msg["content"] as? [[String: Any]] else { return nil }
        let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Prefer a compaction summary, else the first real user message.
    private static func bestTitle(head: [[String: Any]], tail: [[String: Any]]) -> String? {
        for rec in tail.reversed() where rec["type"] as? String == "summary" {
            if let s = rec["summary"] as? String { return ScanCore.clean(s) }
        }
        for rec in head where rec["type"] as? String == "summary" {
            if let s = rec["summary"] as? String { return ScanCore.clean(s) }
        }
        for rec in head where rec["type"] as? String == "user" {
            if let t = userText(rec) { return ScanCore.clean(t) }
        }
        for rec in tail where rec["type"] as? String == "user" {
            if let t = userText(rec) { return ScanCore.clean(t) }
        }
        return nil
    }

    private static func userText(_ rec: [String: Any]) -> String? {
        guard rec["isSidechain"] as? Bool != true,
              let msg = rec["message"] as? [String: Any] else { return nil }
        var text: String?
        if let s = msg["content"] as? String { text = s }
        if let blocks = msg["content"] as? [[String: Any]] {
            text = blocks.first { $0["type"] as? String == "text" }?["text"] as? String
        }
        guard var t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        if t.hasPrefix("<") || t.hasPrefix("[") || t.hasPrefix("Caveat:") { return nil } // harness noise
        if let r = t.range(of: "<system-reminder") { t = String(t[..<r.lowerBound]) }
        return t.isEmpty ? nil : t
    }
}
