import AppKit

/// Click routing: jump to the exact app thread or Ghostty tab.
enum Actions {
    static func open(_ t: AgentThread) {
        switch t.source {
        case .codexApp:
            openURL("codex://threads/\(t.id)")
        case .claudeApp:
            openURL("claude://resume?session=\(t.id)")
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

    private static func isAlive(_ t: AgentThread) -> Bool {
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
