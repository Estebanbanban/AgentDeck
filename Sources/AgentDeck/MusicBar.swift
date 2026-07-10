import SwiftUI

/// Now-playing from any browser/app via `media-control stream` (brew install media-control —
/// the only route to MediaRemote on macOS 15.4+). One persistent process, push-based.
final class MusicWatcher: ObservableObject {
    static let shared = MusicWatcher()
    struct Now: Equatable { var title: String; var artist: String; var playing: Bool }
    @Published var now: Now?

    private let bin = "/opt/homebrew/bin/media-control"
    private let q = DispatchQueue(label: "agentdeck.music", qos: .utility)
    private var proc: Process? // retained: Process isn't self-retaining
    private var state: [String: Any] = [:]
    private var buf = ""

    // Off-main: waitUntilExit on the main thread pumps the run loop mid-init,
    // SwiftUI re-enters `shared`, and dispatch_once deadlocks (launch hang).
    private init() { q.async { self.startStream() } }

    private func startStream() {
        guard FileManager.default.isExecutableFile(atPath: bin) else { return }
        // Sweep adapters orphaned by a previous AgentDeck instance (pkill on the app
        // doesn't reach the spawned perl child). ponytail: nothing else on this
        // machine runs media-control streams.
        let sweep = Process()
        sweep.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        sweep.arguments = ["-f", "mediaremote-adapter.pl.*stream"]
        try? sweep.run(); sweep.waitUntilExit()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["stream"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            guard let self else { return }
            buf += String(decoding: fh.availableData, as: UTF8.self)
            while let nl = buf.firstIndex(of: "\n") {
                let line = String(buf[..<nl])
                buf = String(buf[buf.index(after: nl)...])
                q.async { self.ingest(line) } // state is confined to q
            }
        }
        p.terminationHandler = { [weak self] _ in // adapter died: recover quietly
            self?.q.asyncAfter(deadline: .now() + 5) { self?.startStream() }
        }
        proc = p
        try? p.run()
    }

    private func ingest(_ line: String) { // on q
        guard let j = ScanCore.json(line), j["type"] as? String == "data",
              let payload = j["payload"] as? [String: Any] else { return }
        if j["diff"] as? Bool == true {
            for (k, v) in payload { if v is NSNull { state[k] = nil } else { state[k] = v } }
        } else {
            state = payload
        }
        // media-control sometimes emits an EMPTY diff:false (full replace with {})
        // mid-stream; later diffs never re-send the title, so state stays broken
        // forever — the bar vanished and ducking's playing-gate went dead. Self-heal
        // with a one-shot full snapshot whenever a diff leaves us title-less.
        if state["title"] as? String ?? "" == "", j["diff"] as? Bool == true { refill() }
        publish()
    }

    private func refill() { // on q; blocking `get` is fine here, events are sparse
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["get"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { state = j }
    }

    private func publish() { // on q
        let title = state["title"] as? String ?? ""
        let next: Now? = title.isEmpty ? nil : Now(title: title,
                                                   artist: state["artist"] as? String ?? "",
                                                   playing: state["playing"] as? Bool ?? false)
        DispatchQueue.main.async { [self] in
            guard next != now else { return }
            let structural = (next == nil) != (now == nil)
            now = next
            if structural { NotificationCenter.default.post(name: .agentDeckResize, object: nil) }
        }
    }

    /// Ducker gate reads this on its own queue: a synchronous q-hop keeps it honest.
    var playingNow: Bool { q.sync { state["playing"] as? Bool ?? false } }

    func toggle() { now?.playing.toggle(); cmd("toggle-play-pause") } // optimistic flip
    func next() { cmd("next-track") }
    func prev() { cmd("previous-track") }

    private func cmd(_ c: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = [c]
        try? p.run()
    }
}

/// Bottom strip of the deck: track + transport controls. Hidden when nothing plays.
struct MusicBar: View {
    @ObservedObject private var watcher = MusicWatcher.shared

    var body: some View {
        if let n = watcher.now {
            Divider().opacity(0.4)
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 9))
                    .foregroundStyle(n.playing ? Color.purple : .secondary)
                Text(n.artist.isEmpty ? n.title : "\(n.title) — \(n.artist)")
                    .font(.system(size: 10))
                    .foregroundStyle(n.playing ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                transport("backward.fill") { watcher.prev() }
                transport(n.playing ? "pause.fill" : "play.fill") { watcher.toggle() }
                transport("forward.fill") { watcher.next() }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    private func transport(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
