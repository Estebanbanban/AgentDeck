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
    case working = 0   // actively streaming / running tools
    case ready = 1     // turn finished, waiting on the user
    case idle = 2      // no activity for a while
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
    static let tailBytes = 64 * 1024
    static let headBytes = 256 * 1024
}
