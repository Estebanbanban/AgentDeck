import Foundation

/// Reads Claude Code sessions (CLI + Claude desktop app) from ~/.claude/projects/*/*.jsonl
enum ClaudeScanner {
    // Parse cache keyed by path; only re-parse files whose mtime changed.
    private static var cache: [String: (mtime: Date, thread: AgentThread?)] = [:]

    static func scan(cutoff: Date) -> [AgentThread] {
        let root = ScanCore.home + "/.claude/projects"
        let files = ScanCore.recentFiles(root: root, suffix: ".jsonl", cutoff: cutoff)
        let out = files.compactMap { (path, mtime) -> AgentThread? in
            if let c = cache[path], c.mtime == mtime { return c.thread }
            let t = parse(path: path, mtime: mtime)
            cache[path] = (mtime, t)
            return t
        }
        if cache.count > 3000 { // prune entries that scrolled out of the window
            let seen = Set(files.map(\.path))
            cache = cache.filter { seen.contains($0.key) }
        }
        return out
    }

    private static func parse(path: String, mtime: Date) -> AgentThread? {
        let tail = ScanCore.tailLines(path, bytes: Config.tailBytes).compactMap(ScanCore.json)
        guard !tail.isEmpty else { return nil }

        var sessionId: String?
        var cwd: String?
        var entrypoint: String?
        var prURL: String?
        var summaryParts: [String] = []
        var content: ThreadStatus?

        for rec in tail.reversed() {
            if sessionId == nil { sessionId = rec["sessionId"] as? String }
            if cwd == nil { cwd = rec["cwd"] as? String }
            if entrypoint == nil { entrypoint = rec["entrypoint"] as? String }
            if prURL == nil, rec["type"] as? String == "pr-link" { prURL = rec["prUrl"] as? String }
            // Latest assistant text; if it's a stub ("Done."), pull in the one before it too.
            if summaryParts.count < 2, summaryParts.joined().count < 80,
               rec["type"] as? String == "assistant", let s = assistantText(rec) {
                summaryParts.append(s)
            }
            guard content == nil, let type = rec["type"] as? String else { continue }
            if rec["isSidechain"] as? Bool == true { return nil } // subagent transcript
            switch type {
            case "progress":
                content = .working
            case "user":
                // Raw content (userText() strips harness noise, incl. the interrupt marker).
                let msg = rec["message"] as? [String: Any]
                let raw = (msg?["content"] as? String)
                    ?? ((msg?["content"] as? [[String: Any]])?
                        .compactMap { $0["text"] as? String }.joined(separator: " ")) ?? ""
                content = raw.hasPrefix("[Request interrupted") ? .needsInput : .working
            case "assistant":
                content = assistantStatus(rec)
            default:
                continue // summary, file-history-snapshot, last-prompt, pr-link...
            }
        }
        guard let id = sessionId, let contentStatus = content else { return nil }

        let head = ScanCore.headLines(path, bytes: Config.headBytes).compactMap(ScanCore.json)
        let summary = ScanCore.clean(summaryParts.reversed().joined(separator: " — "), max: 300)
        let title = bestTitle(head: head, tail: tail)
            ?? (summary.isEmpty ? "Claude session" : TitleMaker.make(summary))
        let source: AgentSource = (entrypoint?.hasPrefix("claude-desktop") == true) ? .claudeApp : .claudeCLI
        return AgentThread(id: id, source: source, title: title, summary: summary,
                           cwd: cwd ?? ScanCore.home, filePath: path,
                           lastActivity: mtime, status: contentStatus, prURL: prURL)
    }

    /// Status implied by the latest assistant record.
    private static func assistantStatus(_ rec: [String: Any]) -> ThreadStatus {
        if rec["isApiErrorMessage"] as? Bool == true { return .error }
        guard let msg = rec["message"] as? [String: Any],
              let content = msg["content"] as? [[String: Any]] else { return .done }
        for block in content where block["type"] as? String == "tool_use" {
            // AskUserQuestion / plan approval = blocked on the user, not running.
            let name = block["name"] as? String ?? ""
            return ["AskUserQuestion", "ExitPlanMode"].contains(name) ? .needsInput : .working
        }
        let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: " ")
        if text.hasPrefix("API Error") { return .error }
        return ScanCore.endsAsQuestion(text) ? .needsInput : .done
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
            if let t = userText(rec) { return TitleMaker.make(t) }
        }
        for rec in tail where rec["type"] as? String == "user" {
            if let t = userText(rec) { return TitleMaker.make(t) }
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
