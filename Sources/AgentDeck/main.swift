import AppKit
import SwiftUI
import UserNotifications

import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = Store()
    var panel: NSPanel!
    var hosting: NSHostingView<DeckView>!
    var sub: AnyCancellable?
    var statusItem: NSStatusItem?

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
            sub = store.$threads.receive(on: DispatchQueue.main).sink { [weak self] threads in
                DispatchQueue.main.async {
                    self?.resizeToFit()
                    self?.updateStatusItem()
                    BootBriefing.shared.autoRun(threads)
                }
            }
            installStatusItem()
            MusicDucker.shared.start()
            MicPin.shared.start()
            NotificationCenter.default.addObserver(forName: .agentDeckResize, object: nil,
                                                   queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.resizeToFit() }
            }
            // Self-heal: if any resize signal was missed, converge within a second.
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.resizeToFit()
            }
            installHotkey()
        }
    }

    /// £ anywhere toggles the deck. Global monitor needs Accessibility permission;
    /// without it only in-app £ works (the local monitor).
    private func installHotkey() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.characters == "£" { self?.toggleDeck() }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.characters == "£" { self?.toggleDeck(); return nil }
            return e
        }
    }

    /// Menu-bar badge: how many agents are blocked on you, visible with the deck hidden.
    /// macOS 26.4 (verified by bisection): setting target/action — or any title — on the
    /// button prevents the item from EVER materializing in the bar. Image-only is the one
    /// config that renders, so clicks are caught by mouse monitors over the item's frame.
    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItem()
        let click: (NSEvent) -> Void = { [weak self] _ in
            guard let self, let w = self.statusItem?.button?.window,
                  w.frame.contains(NSEvent.mouseLocation) else { return }
            self.toggleDeck()
        }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: click)
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { e in click(e); return e }
    }

    private var lastBadgeCount = -1

    private func updateStatusItem() {
        guard let btn = statusItem?.button else { return }
        let needs = store.threads.filter { $0.status.actionable }.count
        guard needs != lastBadgeCount else { return } // redrawing every tick is wasteful
        lastBadgeCount = needs
        btn.image = StatusBadge.image(count: needs) // no toolTip: see StatusBadge doc
    }

    private func toggleDeck() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
            resizeToFit()
        }
    }

    /// Fit the (invisible) window to the card WITHOUT animating it — the card is
    /// SwiftUI-animated and the window animating too is what caused the twitching.
    /// Grow instantly (extra window area is transparent, card is top-pinned);
    /// shrink only after the content animation has settled.
    private var shrinkTask: DispatchWorkItem?

    private func resizeToFit() {
        guard let panel, let hosting else { return }
        let size = hosting.fittingSize
        guard size.height > 10 else { return }
        shrinkTask?.cancel()
        if size.height > panel.frame.height + 1 {
            apply(size)
        } else if size.height < panel.frame.height - 1 {
            let task = DispatchWorkItem { [weak self] in
                guard let self, let hosting = self.hosting else { return }
                let s = hosting.fittingSize
                if s.height > 10 { self.apply(s) }
            }
            shrinkTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + Config.animDuration + 0.08, execute: task)
        }
    }

    private func apply(_ size: NSSize) {
        guard let panel else { return }
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
    let all = Titler.shared.enhance((ClaudeScanner.scan(cutoff: cutoff) + CodexScanner.scan(cutoff: cutoff))
        .map { t -> AgentThread in
            var t = t
            t.status = ScanCore.finalStatus(content: t.status, mtime: t.lastActivity)
            return t
        })
        .filter { !(Config.hideSpawned && $0.spawned) } // mirror the UI's filters
        .sorted { $0.lastActivity > $1.lastActivity }
    for t in all {
        print("[\(t.status.label)] \(t.source.rawValue) | \(t.projectName) | \(t.title) | \(t.id.prefix(8)) | \(Int(-t.lastActivity.timeIntervalSinceNow))s ago\(t.prURL.map { " | PR \($0)" } ?? "")")
        if !t.summary.isEmpty { print("        ↳ \(t.summary.prefix(100))") }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
