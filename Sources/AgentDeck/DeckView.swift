import SwiftUI

extension Notification.Name {
    static let agentDeckResize = Notification.Name("agentdeck.resize")
}

struct DeckView: View {
    @ObservedObject var store: Store
    @AppStorage("compactMode") private var compact = false
    @AppStorage("focusStarred") private var focus = false
    @State private var showSettings = false

    /// Compact keeps only what's actionable or in flight; focus keeps starred only.
    private var visible: [AgentThread] {
        var list = store.threads
        if focus { list = list.filter { store.starred.contains($0.id) } }
        if compact { list = list.filter { $0.status.rawValue <= ThreadStatus.working.rawValue } }
        return list
    }

    var body: some View {
        // Card pinned to the window's top: the window is often transiently taller
        // than the card (it grows instantly, shrinks after animations settle), and
        // without the Spacer the hosting view would re-center — i.e. twitch.
        VStack(spacing: 0) {
            card
            Spacer(minLength: 0)
        }
        .onChange(of: compact) { _ in
            NotificationCenter.default.post(name: .agentDeckResize, object: nil)
        }
        .onChange(of: focus) { _ in
            NotificationCenter.default.post(name: .agentDeckResize, object: nil)
        }
        .onChange(of: showSettings) { _ in
            NotificationCenter.default.post(name: .agentDeckResize, object: nil)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.4)
            if showSettings {
                SettingsView { showSettings = false }
            } else if visible.isEmpty {
                Text(focus ? "No starred threads" : compact ? "All quiet" : "No active threads")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
            } else {
                // ponytail: no ScrollView — the panel resizes to fit all rows (see resizeToFit).
                VStack(spacing: 1) {
                    ForEach(visible) { t in
                        ThreadRow(thread: t,
                                  compact: compact,
                                  starred: store.starred.contains(t.id),
                                  onStar: {
                                      withAnimation(.easeOut(duration: Config.animDuration)) { store.toggleStar(t) }
                                  },
                                  onDismiss: {
                                      withAnimation(.easeOut(duration: Config.animDuration)) { store.dismiss(t) }
                                  })
                        .transition(.opacity) // no move/scale: nothing slides over neighbours
                    }
                }
                .padding(6)
            }
            MusicBar()
        }
        .frame(width: compact ? 260 : 330)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.1)))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Agents").font(.system(size: 11, weight: .semibold))
            let running = store.threads.filter { $0.status == .working }.count
            let needs = store.threads.filter { $0.status.actionable }.count
            Text("\(running) running").font(.system(size: 10))
                .foregroundStyle(running > 0 ? Color.purple : .secondary)
            // Clicking the count jumps to the thread that's been waiting the longest.
            Button(action: jumpToOldestNeedsInput) {
                Text("· \(needs) need you").font(.system(size: 10))
                    .foregroundStyle(needs > 0 ? Color.orange : .secondary)
            }
            .buttonStyle(.plain)
            .help("Jump to the longest-waiting thread")
            Spacer()
            headerButton(focus ? "star.fill" : "star", size: 9,
                         color: focus ? .yellow : nil,
                         help: "Show starred only") { focus.toggle() }
            headerButton(compact ? "rectangle.expand.vertical" : "rectangle.compress.vertical", size: 9,
                         help: compact ? "Full view" : "Compact view (actionable + running only)") { compact.toggle() }
            headerButton("gearshape", size: 9, help: "Settings") { showSettings.toggle() }
            headerButton("xmark", size: 8, help: "Quit AgentDeck") {
                Notifier.log("quit clicked"); NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func headerButton(_ symbol: String, size: CGFloat, color: Color? = nil,
                              help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .bold))
                .foregroundStyle(color ?? Color(nsColor: .tertiaryLabelColor))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func jumpToOldestNeedsInput() {
        let waiting = store.threads.filter { $0.status.actionable }
        guard let oldest = waiting.min(by: { $0.lastActivity < $1.lastActivity }) else { return }
        Actions.open(oldest)
    }
}
