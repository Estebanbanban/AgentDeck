import AppKit
import SwiftUI
import UserNotifications

import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = Store()
    var panel: NSPanel!
    var hosting: NSHostingView<DeckView>!
    var sub: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.log("launched")
        store.start()
        if Bundle.main.bundleIdentifier != nil {
            store.notifier.requestAuth()
            UNUserNotificationCenter.current().delegate = self
        }
        if ProcessInfo.processInfo.environment["AGENTDECK_HEADLESS"] == nil {
            panel = makePanel()
            panel.orderFrontRegardless()
            sub = store.$threads.receive(on: DispatchQueue.main).sink { [weak self] _ in
                DispatchQueue.main.async { self?.resizeToFit() }
            }
            NotificationCenter.default.addObserver(forName: .agentDeckResize, object: nil,
                                                   queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.resizeToFit() }
            }
        }
    }

    /// Resize the panel to the SwiftUI content's ideal size, keeping its top-left corner fixed.
    private func resizeToFit() {
        guard let panel, let hosting else { return }
        let size = hosting.fittingSize
        guard size.height > 10, abs(panel.frame.height - size.height) > 1 else { return }
        var f = panel.frame
        f.origin.y += f.size.height - size.height
        f.size = size
        panel.setFrame(f, display: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        Notifier.log("terminating (user quit)")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 330, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hosting = NSHostingView(rootView: DeckView(store: store))
        p.contentView = hosting
        // Only the top-left POSITION is remembered; height always comes from content.
        if !p.setFrameUsingName("AgentDeck"), let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameTopLeftPoint(NSPoint(x: f.maxX - 350, y: f.maxY - 12))
        }
        p.setFrameAutosaveName("AgentDeck")
        let topLeft = NSPoint(x: p.frame.minX, y: p.frame.maxY)
        p.setContentSize(hosting.fittingSize)
        p.setFrameTopLeftPoint(topLeft)
        return p
    }

    // Clicking a notification jumps to the thread.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let id = response.notification.request.content.userInfo["threadId"] as? String,
           let t = store.thread(id: id) {
            Actions.open(t)
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}

// Debug: `AgentDeck --dump` prints one scan and exits (QA harness, no UI).
if CommandLine.arguments.contains("--dump") {
    let cutoff = Date().addingTimeInterval(-Config.showWindow)
    let all = (ClaudeScanner.scan(cutoff: cutoff) + CodexScanner.scan(cutoff: cutoff))
        .sorted { $0.lastActivity > $1.lastActivity }
    for t in all {
        let st = ["working", "ready", "idle"][t.status.rawValue]
        print("[\(st)] \(t.source.rawValue) | \(t.projectName) | \(t.title) | \(t.id.prefix(8)) | \(Int(-t.lastActivity.timeIntervalSinceNow))s ago")
        if !t.summary.isEmpty { print("        ↳ \(t.summary.prefix(100))") }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
