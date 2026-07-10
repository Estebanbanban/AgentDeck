import Foundation

/// AI titles + summaries via OpenRouter (openai/gpt-oss-120b), disk-cached.
/// Title is generated once per thread; the summary regenerates when a turn ends.
/// Fails silently to the heuristic text — never blocks the scan loop.
final class Titler {
    static let shared = Titler()
    struct Entry: Codable { var title: String; var summary: String; var srcStamp: TimeInterval }

    private var cache: [String: Entry]
    private var inFlight: Set<String> = []
    private var failedAt: [String: TimeInterval] = [:] // per-thread backoff on API/parse failure
    private let q = DispatchQueue(label: "agentdeck.titler")
    private let cachePath = NSHomeDirectory() + "/Library/Application Support/AgentDeck/titles.json"

    private init() {
        let data = FileManager.default.contents(atPath: cachePath)
        cache = data.flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    /// Swap in AI title/summary where cached; kick off generation where missing/stale.
    func enhance(_ threads: [AgentThread]) -> [AgentThread] {
        guard OpenRouter.apiKey != nil, !Config.aiTitlesOff else { return threads }
        return threads.map { t in
            var t = t
            let cached: Entry? = q.sync { cache[t.id] }
            if let e = cached {
                t = applying(e, to: t)
                let turnEnded = t.status != .working
                if turnEnded, e.srcStamp < t.lastActivity.timeIntervalSince1970 - 60 { generate(t, keepTitle: e.title) }
            } else if t.status != .working || t.summary.isEmpty == false {
                generate(t, keepTitle: nil)
            }
            return t
        }
    }

    private func applying(_ e: Entry, to t: AgentThread) -> AgentThread {
        AgentThread(id: t.id, source: t.source,
                    title: e.title.isEmpty ? t.title : e.title,
                    summary: e.summary.isEmpty ? t.summary : e.summary,
                    cwd: t.cwd, filePath: t.filePath, lastActivity: t.lastActivity,
                    status: t.status, spawned: t.spawned, prURL: t.prURL)
    }

    private func generate(_ t: AgentThread, keepTitle: String?) {
        q.async { [self] in
            guard !inFlight.contains(t.id), inFlight.count < 4 else { return }
            // Backoff: a failing thread must not retry every 2s tick — that burned
            // the whole hourly budget in under a minute.
            guard Date().timeIntervalSince1970 - (failedAt[t.id] ?? 0) > 600, Budget.allow() else { return }
            inFlight.insert(t.id)
            let heurTitle = t.title, heurSummary = t.summary
            DispatchQueue.global(qos: .utility).async { [self] in
                let result = call(title: heurTitle, summary: heurSummary, project: t.projectName,
                                  status: t.status.label, source: t.source.rawValue)
                q.async { [self] in
                    inFlight.remove(t.id)
                    guard var r = result else {
                        failedAt[t.id] = Date().timeIntervalSince1970
                        return
                    }
                    failedAt[t.id] = nil
                    if let keep = keepTitle, !keep.isEmpty { r.title = keep } // title stays stable
                    r.srcStamp = t.lastActivity.timeIntervalSince1970
                    cache[t.id] = r
                    persist()
                }
            }
        }
    }

    private func persist() {
        if cache.count > 400 { // keep the newest entries only
            cache = Dictionary(uniqueKeysWithValues: cache.sorted { $0.value.srcStamp > $1.value.srcStamp }
                .prefix(300).map { ($0.key, $0.value) })
        }
        try? FileManager.default.createDirectory(atPath: (cachePath as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(cache) { try? d.write(to: URL(fileURLWithPath: cachePath)) }
    }

    private func call(title: String, summary: String, project: String,
                      status: String, source: String) -> Entry? {
        let sys = """
        You title and summarize AI coding-agent threads for a glanceable dashboard. \
        Reply ONLY with JSON {"title":"...","summary":"..."}. \
        title: <=7 words, concrete, names the actual subject (project/feature/bug). \
        Never generic ("Continue task", "Coding session") — extract the real topic from the task text. \
        summary: <=2 short sentences, plain words: what the agent just did or found, and what it needs from the user (if anything). \
        If the latest message is low-signal (e.g. "ok", "no response"), summarize the overall task state instead of the message.
        """
        let user = "source: \(source)\nproject: \(project)\nstatus: \(status)\ntask: \(title)\nlatest agent message: \(summary)"
        guard let content = OpenRouter.chat(system: sys, user: user, maxTokens: 400),
              let jsonStart = content.firstIndex(of: "{"), let jsonEnd = content.lastIndex(of: "}"),
              jsonStart < jsonEnd,
              let parsed = (try? JSONSerialization.jsonObject(
                with: Data(content[jsonStart...jsonEnd].utf8))) as? [String: String]
        else { return nil }
        return Entry(title: ScanCore.clean(parsed["title"] ?? "", max: 70),
                     summary: ScanCore.clean(parsed["summary"] ?? "", max: 300), srcStamp: 0)
    }
}

/// Hard cost guardrails: 120 calls/hour, 600/day, auto-off beyond that.
enum Budget {
    static func allow() -> Bool {
        let d = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        var hour = d.array(forKey: "aiCallsHour") as? [Double] ?? []
        hour = hour.filter { now - $0 < 3600 }
        let day = (d.array(forKey: "aiCallsDay") as? [Double] ?? []).filter { now - $0 < 86400 }
        guard hour.count < 120, day.count < 600 else { return false }
        d.set(hour + [now], forKey: "aiCallsHour")
        d.set(day + [now], forKey: "aiCallsDay")
        return true
    }
}
