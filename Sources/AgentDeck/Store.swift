import Foundation
import Combine

final class Store: ObservableObject {
    @Published var threads: [AgentThread] = []
    let notifier = Notifier()
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "agentdeck.scan", qos: .utility)

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: Config.pollInterval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        let cutoff = Date().addingTimeInterval(-Config.showWindow)
        var all = ClaudeScanner.scan(cutoff: cutoff) + CodexScanner.scan(cutoff: cutoff)
        // Dedupe by id (a resumed session can appear in several files): keep freshest.
        var byId: [String: AgentThread] = [:]
        for t in all { if let old = byId[t.id], old.lastActivity >= t.lastActivity { continue }; byId[t.id] = t }
        all = byId.values.sorted {
            $0.status.rawValue != $1.status.rawValue
                ? $0.status.rawValue < $1.status.rawValue
                : $0.lastActivity > $1.lastActivity
        }
        let capped = Array(all.prefix(60))
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if capped != self.threads { self.threads = capped }
            self.notifier.process(capped)
        }
    }

    func thread(id: String) -> AgentThread? { threads.first { $0.id == id } }
}
