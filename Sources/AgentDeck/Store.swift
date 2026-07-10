import Foundation
import Combine
import SwiftUI

final class Store: ObservableObject {
    @Published var threads: [AgentThread] = []
    let notifier = Notifier()
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "agentdeck.scan", qos: .utility)
    /// Dismissed thread ids -> lastActivity at dismissal. The thread stays hidden
    /// unless it produces NEWER activity (then it earned its way back).
    private var dismissed: [String: TimeInterval] =
        (UserDefaults.standard.dictionary(forKey: "dismissed") as? [String: TimeInterval]) ?? [:]
    @Published var starred: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: "starred") ?? [])

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: Config.pollInterval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func toggleStar(_ t: AgentThread) {
        if starred.contains(t.id) { starred.remove(t.id) } else { starred.insert(t.id) }
        UserDefaults.standard.set(Array(starred), forKey: "starred")
        resort()
    }

    /// Re-apply the sort in place (starred rows float to the top of their status group).
    private func resort() {
        let star = starred
        threads.sort {
            if $0.status.rawValue != $1.status.rawValue { return $0.status.rawValue < $1.status.rawValue }
            let s0 = star.contains($0.id), s1 = star.contains($1.id)
            if s0 != s1 { return s0 }
            return $0.lastActivity > $1.lastActivity
        }
    }

    func dismiss(_ t: AgentThread) {
        dismissed[t.id] = t.lastActivity.timeIntervalSince1970
        UserDefaults.standard.set(dismissed, forKey: "dismissed")
        threads.removeAll { $0.id == t.id }
    }

    private func tick() {
        let cutoff = Date().addingTimeInterval(-Config.showWindow)
        var all = ClaudeScanner.scan(cutoff: cutoff) + CodexScanner.scan(cutoff: cutoff)
        // Dedupe by id (a resumed session can appear in several files): keep freshest.
        var byId: [String: AgentThread] = [:]
        for t in all { if let old = byId[t.id], old.lastActivity >= t.lastActivity { continue }; byId[t.id] = t }
        let dismissedNow = dismissed
        let star = starred
        all = byId.values
            .map { t -> AgentThread in
                // Scanners cache content-derived status; overlay the time rules here.
                var t = t
                t.status = ScanCore.finalStatus(content: t.status, mtime: t.lastActivity)
                return t
            }
            .filter { ($0.lastActivity.timeIntervalSince1970) > (dismissedNow[$0.id] ?? 0) }
            .sorted {
                if $0.status.rawValue != $1.status.rawValue { return $0.status.rawValue < $1.status.rawValue }
                let s0 = star.contains($0.id), s1 = star.contains($1.id)
                if s0 != s1 { return s0 }
                return $0.lastActivity > $1.lastActivity
            }
        let capped = Array(all.prefix(60))
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pruneDismissed(cutoff: cutoff)
            if capped != self.threads {
                // Animate only real structural changes (order/membership/status),
                // not every mtime tick — otherwise rows shimmer every 2s.
                let structural = capped.map { "\($0.id)|\($0.status.rawValue)" }
                    != self.threads.map { "\($0.id)|\($0.status.rawValue)" }
                if structural {
                    withAnimation(.easeOut(duration: Config.animDuration)) { self.threads = capped }
                } else {
                    self.threads = capped
                }
            }
            self.notifier.process(capped)
        }
    }

    private func pruneDismissed(cutoff: Date) {
        let old = dismissed
        dismissed = dismissed.filter { $0.value > cutoff.timeIntervalSince1970 }
        if dismissed.count != old.count { UserDefaults.standard.set(dismissed, forKey: "dismissed") }
    }

    func thread(id: String) -> AgentThread? { threads.first { $0.id == id } }
}
