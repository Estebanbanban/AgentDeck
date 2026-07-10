import AppKit
import SwiftUI

/// Fresh-boot ritual: open the agent apps and brief what was in flight.
/// Auto-fires once per launch IF the Claude app wasn't already running when
/// AgentDeck started (i.e. a real login/boot, not a dev rebuild). The ✳ header
/// button re-runs it on demand.
final class BootBriefing: ObservableObject {
    static let shared = BootBriefing()
    @Published var text: String?
    private let freshBoot = NSRunningApplication
        .runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop").isEmpty
    private var ran = false

    /// Called on every store publish; fires once when the first scan lands.
    func autoRun(_ threads: [AgentThread]) {
        guard freshBoot, !ran, !threads.isEmpty else { return }
        run(threads)
    }

    func run(_ threads: [AgentThread]) {
        ran = true
        openAgentApps()
        guard OpenRouter.apiKey != nil, Budget.allow() else { return }
        show("Briefing…")
        let lines = threads.prefix(30).map { t in
            "\(t.status.label) | \(t.source.short) | \(t.projectName) | \(t.title)"
                + (t.summary.isEmpty ? "" : " — \(t.summary.prefix(140))")
        }.joined(separator: "\n")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let sys = """
            You brief a developer on his AI coding agents at the start of the day. \
            Given the thread list, write a tight plain-text briefing, max 5 short lines: \
            first what NEEDS HIM (questions, stalls, errors), then what finished, then what's still running. \
            Name projects and tasks concretely. No preamble, no markdown, no headers.
            """
            let out = OpenRouter.chat(system: sys, user: lines, maxTokens: 700)
            DispatchQueue.main.async { self?.show(out ?? "Briefing failed (OpenRouter).") }
        }
    }

    func dismiss() { show(nil) }

    private func show(_ t: String?) {
        text = t
        NotificationCenter.default.post(name: .agentDeckResize, object: nil)
    }

    /// Resolve whichever apps own the claude:// and codex:// schemes and launch them.
    private func openAgentApps() {
        for scheme in ["claude", "codex"] {
            guard let target = URL(string: "\(scheme)://"),
                  let app = NSWorkspace.shared.urlForApplication(toOpen: target) else { continue }
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
