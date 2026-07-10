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
        for t in threads where lastStatus[t.id] == .working
            && [.done, .needsInput, .error].contains(t.status) {
            notify(t)
        }
    }

    private func notify(_ t: AgentThread) {
        let sound = [ThreadStatus.done: "Glass", .needsInput: "Ping", .error: "Basso"][t.status] ?? "Glass"
        NSSound(named: sound)?.play()
        guard Bundle.main.bundleIdentifier != nil else { return } // bare binary: sound only
        let content = UNMutableNotificationContent()
        content.title = "\(t.status.label.capitalized) — \(t.source.rawValue) · \(t.projectName)"
        content.body = t.title
        content.userInfo = ["threadId": t.id]
        let req = UNNotificationRequest(identifier: "agentdeck-\(t.id)-\(Int(t.lastActivity.timeIntervalSince1970))",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { err in
            Notifier.log("notified \(t.source.rawValue) '\(t.title.prefix(40))' err=\(err?.localizedDescription ?? "none")")
        }
    }

    static func log(_ msg: String) {
        let line = "\(Date()) \(msg)\n"
        let path = NSHomeDirectory() + "/Library/Logs/AgentDeck.log"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile(); fh.write(line.data(using: .utf8)!); try? fh.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
