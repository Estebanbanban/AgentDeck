import AppKit

/// Click routing: jump to the exact app thread or Ghostty tab.
enum Actions {
    static func open(_ t: AgentThread) {
        switch t.source {
        case .codexApp:
            openURL("codex://threads/\(t.id)")
        case .claudeApp:
            // claude://resume IMPORTS the transcript — on an already-open session it
            // spawns a duplicate "general coding session" tab. If a live process is
            // running this session, reopen/activate the app instead. (Reopen, not
            // activate: with its window closed, activate shows nothing. The app has
            // no focus-session deep link — resume/import is the only session route.)
            if isLiveClaudeSession(t.id) {
                reopen("com.anthropic.claudefordesktop")
                ClaudeAppNav.focus(sessionId: t.id) // sidebar-click the exact session
            } else {
                openURL("claude://resume?session=\(t.id)")
            }
        case .claudeCLI, .codexCLI:
            jumpToCLI(t)
        }
    }

    private static func openURL(_ s: String) {
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }

    private static func jumpToCLI(_ t: AgentThread) {
        if isAlive(t) {
            focusGhostty(matching: hints(for: t))
        } else {
            resumeInNewGhostty(t)
        }
    }

    // MARK: liveness

    /// Claude keeps a registry at ~/.claude/sessions/<pid>.json with the sessionId;
    /// entry + live pid == the session is open somewhere right now.
    private static func isLiveClaudeSession(_ id: String) -> Bool {
        let dir = NSHomeDirectory() + "/.claude/sessions"
        for f in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] {
            guard f.hasSuffix(".json"),
                  let data = FileManager.default.contents(atPath: "\(dir)/\(f)"),
                  let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  j["sessionId"] as? String == id,
                  let pid = j["pid"] as? Int else { continue }
            if kill(pid_t(pid), 0) == 0 { return true }
        }
        return false
    }

    private static func isAlive(_ t: AgentThread) -> Bool {
        if t.source.isClaude, isLiveClaudeSession(t.id) { return true }
        let ps = shell("/bin/ps", ["axo", "command="])
        if ps.contains(t.id) { return true }
        let bin = t.source.isClaude ? "claude" : "codex"
        let cwds = shell("/usr/sbin/lsof", ["-a", "-c", bin, "-d", "cwd", "-Fn"])
        return cwds.components(separatedBy: "\n").contains("n" + t.cwd)
    }

    // MARK: focus existing Ghostty tab

    private static func hints(for t: AgentThread) -> [String] {
        var h = [t.projectName]
        let words = t.title.split(separator: " ").map(String.init).filter { $0.count > 4 }
        h.append(contentsOf: words.prefix(3))
        return h
    }

    /// Raise the Ghostty window/tab whose title matches a hint; else just activate Ghostty.
    /// ponytail: title matching — macOS exposes no tty->AX-window mapping; tabs are
    /// NSWindows so AXRaise on a match selects the exact tab.
    private static func focusGhostty(matching hints: [String]) {
        let conditions = hints.map { "name of w contains \"\(escape($0))\"" }
            .joined(separator: " or ")
        let script = """
        tell application "System Events"
            tell process "Ghostty"
                repeat with w in windows
                    if \(conditions) then
                        perform action "AXRaise" of w
                        return "ok"
                    end if
                end repeat
            end tell
        end tell
        """
        _ = NSAppleScript(source: script)?.executeAndReturnError(nil)
        activate("com.mitchellh.ghostty")
    }

    // MARK: resume dead session in a fresh Ghostty window

    private static func resumeInNewGhostty(_ t: AgentThread) {
        let cmd = t.source.isClaude ? "claude --resume \(t.id)" : "codex resume \(t.id)"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-na", "Ghostty", "--args",
                       "--working-directory=\(t.cwd)",
                       "-e", "/bin/zsh", "-ilc", cmd]
        try? p.run()
    }

    // MARK: helpers

    private static func activate(_ bundleId: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .first?.activate(options: [.activateAllWindows])
    }

    /// Launch-or-reopen: fires the app's reopen event so a closed window comes back.
    private static func reopen(_ bundleId: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func shell(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
