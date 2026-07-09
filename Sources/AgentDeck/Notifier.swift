import AppKit
import UserNotifications

/// Fires a sound + notification when a thread flips from working -> ready.
final class Notifier {
    private var lastStatus: [String: ThreadStatus] = [:]
    private var primed = false

    func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func process(_ threads: [AgentThread]) {
        defer {
            lastStatus = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0.status) })
            primed = true
        }
        guard primed else { return } // don't blast sounds for pre-existing state at launch
        for t in threads where t.status == .ready && lastStatus[t.id] == .working {
            notify(t)
        }
    }

    private func notify(_ t: AgentThread) {
        NSSound(named: "Glass")?.play()
        guard Bundle.main.bundleIdentifier != nil else { return } // bare binary: sound only
        let content = UNMutableNotificationContent()
        content.title = "\(t.source.rawValue) · \(t.projectName)"
        content.body = t.title
        content.userInfo = ["threadId": t.id]
        let req = UNNotificationRequest(identifier: "agentdeck-\(t.id)-\(Int(t.lastActivity.timeIntervalSince1970))",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
