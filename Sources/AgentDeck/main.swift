import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = Store()
    var panel: NSPanel!

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
        }
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
        p.contentView = NSHostingView(rootView: DeckView(store: store))
        if !p.setFrameUsingName("AgentDeck") {
            if let screen = NSScreen.main {
                let f = screen.visibleFrame
                p.setFrameTopLeftPoint(NSPoint(x: f.maxX - 350, y: f.maxY - 12))
            }
        }
        p.setFrameAutosaveName("AgentDeck")
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
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
