import Foundation

enum AgentSource: String {
    case claudeApp = "Claude app"
    case claudeCLI = "Claude CLI"
    case codexApp = "Codex app"
    case codexCLI = "Codex CLI"

    var isClaude: Bool { self == .claudeApp || self == .claudeCLI }
    var short: String {
        switch self {
        case .claudeApp: return "Claude"
        case .claudeCLI: return "Claude CLI"
        case .codexApp: return "Codex"
        case .codexCLI: return "Codex CLI"
        }
    }
}

enum ThreadStatus: Int {
    case needsInput = 0  // asked a question / permission prompt / interrupted
    case error = 1       // API or task error
    case working = 2     // actively streaming / running tools
    case done = 3        // turn finished cleanly, nothing asked
    case idle = 4        // no activity for a while

    var label: String {
        switch self {
        case .needsInput: return "needs input"
        case .error: return "error"
        case .working: return "running"
        case .done: return "done"
        case .idle: return "idle"
        }
    }
}

struct AgentThread: Identifiable, Equatable {
    let id: String          // session / thread UUID
    let source: AgentSource
    let title: String
    let summary: String     // latest assistant message snippet, shown on hover
    let cwd: String
    let filePath: String
    let lastActivity: Date
    let status: ThreadStatus

    var projectName: String { (cwd as NSString).lastPathComponent }
}

enum Config {
    /// Sessions older than this are not shown at all.
    static let showWindow: TimeInterval = 8 * 3600
    /// File written within this many seconds => working.
    static let workingWindow: TimeInterval = 25
    /// No activity for this long => idle.
    static let idleAfter: TimeInterval = 30 * 60
    static let pollInterval: TimeInterval = 2.0
    /// One clock for every animation (SwiftUI + window resize) so nothing fights.
    static let animDuration: TimeInterval = 0.22
    static let tailBytes = 64 * 1024
    static let headBytes = 256 * 1024
}
