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
    case stalled = 2     // says "working" but transcript went quiet — check it
    case working = 3     // actively streaming / running tools
    case done = 4        // turn finished cleanly, nothing asked
    case idle = 5        // no activity for a while

    var label: String {
        switch self {
        case .needsInput: return "needs input"
        case .error: return "error"
        case .stalled: return "stalled?"
        case .working: return "running"
        case .done: return "done"
        case .idle: return "idle"
        }
    }

    /// Blocked on the user in some way — drives the badge, sort, and pings.
    var actionable: Bool { rawValue <= ThreadStatus.stalled.rawValue }
}

struct AgentThread: Identifiable, Equatable {
    let id: String          // session / thread UUID
    let source: AgentSource
    let title: String
    let summary: String     // latest assistant message snippet, shown on hover
    let cwd: String
    let filePath: String
    let lastActivity: Date
    var status: ThreadStatus // scanners store the content-derived status; Store overlays time rules
    var spawned = false      // tool-spawned worker (e.g. codex exec reviewer), not a human session
    var prURL: String?       // newest pr-link record in the transcript, if any

    var projectName: String { (cwd as NSString).lastPathComponent }
}

/// Tunables. The user-facing ones are UserDefaults-backed (editable in Settings).
enum Config {
    /// Hard ceiling: sessions older than this are never shown (starred included).
    static var showWindow: TimeInterval { hours("windowHours", 36) }
    /// Done/idle rows auto-expire after this (starred rows are exempt).
    static var doneRetention: TimeInterval { hours("doneRetentionHours", 3) }
    /// Needs-input / error rows auto-expire after this (starred exempt).
    static var needsRetention: TimeInterval { hours("needsRetentionHours", 12) }
    /// Rows untouched for this long render heavily dimmed.
    static var dimAfter: TimeInterval { hours("dimAfterHours", 24) }
    /// A needs-input row waiting longer than this shows a red timer.
    static var overdueAfter: TimeInterval { 60 * (minutes("overdueMinutes", 10)) }
    /// DND: mute completion sounds (banners still show).
    static var muted: Bool { UserDefaults.standard.bool(forKey: "muted") }
    /// Hide tool-spawned Codex agents (adversarial reviewers etc.). Default on.
    static var hideSpawned: Bool {
        UserDefaults.standard.object(forKey: "hideSpawned") as? Bool ?? true
    }
    /// Kill switch for OpenRouter titles/summaries (default: on when a key exists).
    static var aiTitlesOff: Bool { UserDefaults.standard.bool(forKey: "aiTitlesOff") }
    /// Kill switch for music ducking while the mic is in use.
    static var duckOff: Bool { UserDefaults.standard.bool(forKey: "duckOff") }

    /// File written within this many seconds => working.
    static let workingWindow: TimeInterval = 25
    /// No activity for this long => idle.
    static let idleAfter: TimeInterval = 30 * 60
    static let pollInterval: TimeInterval = 2.0
    /// One clock for every animation (SwiftUI + window resize) so nothing fights.
    static let animDuration: TimeInterval = 0.22
    static let tailBytes = 64 * 1024
    static let headBytes = 256 * 1024

    private static func hours(_ key: String, _ def: Double) -> TimeInterval {
        let v = UserDefaults.standard.double(forKey: key)
        return (v > 0 ? v : def) * 3600
    }
    private static func minutes(_ key: String, _ def: Double) -> Double {
        let v = UserDefaults.standard.double(forKey: key)
        return v > 0 ? v : def
    }
}
