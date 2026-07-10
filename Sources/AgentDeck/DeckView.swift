import SwiftUI

extension Notification.Name {
    static let agentDeckResize = Notification.Name("agentdeck.resize")
}

struct DeckView: View {
    @ObservedObject var store: Store
    @AppStorage("compactMode") private var compact = false

    /// Compact mode keeps only what's actionable or in flight.
    private var visible: [AgentThread] {
        compact ? store.threads.filter { $0.status.rawValue <= ThreadStatus.working.rawValue }
                : store.threads
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
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.4)
            if visible.isEmpty {
                Text(compact ? "All quiet" : "No active threads")
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
        }
        .frame(width: compact ? 260 : 330)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.1)))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Agents").font(.system(size: 11, weight: .semibold))
            let running = store.threads.filter { $0.status == .working }.count
            let needs = store.threads.filter { $0.status == .needsInput || $0.status == .error }.count
            (Text("\(running) running").foregroundStyle(running > 0 ? Color.purple : .secondary)
                + Text(" · ").foregroundStyle(.secondary)
                + Text("\(needs) need you").foregroundStyle(needs > 0 ? Color.orange : .secondary))
                .font(.system(size: 10))
            Spacer()
            Button { compact.toggle() } label: {
                Image(systemName: compact ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(compact ? "Full view" : "Compact view (actionable + running only)")
            Button { Notifier.log("quit clicked"); NSApp.terminate(nil) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}
