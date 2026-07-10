import SwiftUI

extension Notification.Name {
    static let agentDeckResize = Notification.Name("agentdeck.resize")
}

struct DeckView: View {
    @ObservedObject var store: Store

    var body: some View {
        // Card pinned to the window's top: the window is often transiently taller
        // than the card (it grows instantly, shrinks after animations settle), and
        // without the Spacer the hosting view would re-center — i.e. twitch.
        VStack(spacing: 0) {
            card
            Spacer(minLength: 0)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.4)
            if store.threads.isEmpty {
                Text("No active threads")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            } else {
                // ponytail: no ScrollView — the panel resizes to fit all rows (see resizeToFit).
                VStack(spacing: 1) {
                    ForEach(store.threads) { t in
                        ThreadRow(thread: t,
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
        .frame(width: 330)
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
            Button { Notifier.log("quit clicked"); NSApp.terminate(nil) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

struct ThreadRow: View {
    let thread: AgentThread
    let starred: Bool
    let onStar: () -> Void
    let onDismiss: () -> Void
    @State private var hovering = false   // immediate: highlight + ✕ button
    @State private var expanded = false   // delayed: summary reveal (hover intent)
    @State private var expandTask: DispatchWorkItem?

    var body: some View {
        Button { Actions.open(thread) } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(dotColor).frame(width: 7, height: 7).padding(.top, 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(thread.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    (Text(thread.status.label).foregroundStyle(dotColor.opacity(0.9))
                        + Text(" · ").foregroundStyle(.secondary)
                        + Text(thread.source.short).foregroundStyle(brandColor.opacity(0.9))
                        + Text(" · \(thread.projectName) · \(relTime)")
                        .foregroundStyle(.secondary))
                        .font(.system(size: 9))
                        .lineLimit(1)
                    // Always in the layout; only its height + opacity animate, and it's
                    // clipped — so the text can never paint over neighbouring rows.
                    if !thread.summary.isEmpty {
                        Text(thread.summary)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 3)
                            // Finite -> finite so the height actually interpolates
                            // (0 <-> .infinity is not animatable and twitches).
                            .frame(maxHeight: expanded ? 160 : 0, alignment: .top)
                            .clipped()
                            .opacity(expanded ? 1 : 0)
                    }
                }
                Spacer(minLength: 0)
                // Always in the layout (opacity-only) so hovering never reflows the row.
                HStack(spacing: 5) {
                    Button(action: onStar) {
                        Image(systemName: starred ? "star.fill" : "star")
                            .font(.system(size: 10))
                            .foregroundStyle(starred ? Color.yellow : Color.secondary)
                            .scaleEffect(starred ? 1.15 : 1)
                    }
                    .buttonStyle(.plain)
                    .opacity(starred || hovering ? 1 : 0)
                    .help("Pin as priority")
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .opacity(hovering ? 1 : 0)
                    .help("Remove from deck (transcript untouched)")
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.yellow.opacity(starred ? 0.45 : 0), lineWidth: 1))
            .contentShape(Rectangle())
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: starred)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: Config.animDuration), value: expanded)
        .onHover { h in
            expandTask?.cancel()
            hovering = h
            if h {
                // Hover-intent: expand only after a short dwell, so sweeping the
                // cursor across the list doesn't cascade-expand every row.
                let task = DispatchWorkItem {
                    expanded = true
                    NotificationCenter.default.post(name: .agentDeckResize, object: nil)
                }
                expandTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
            } else if expanded {
                expanded = false
                NotificationCenter.default.post(name: .agentDeckResize, object: nil)
            }
        }
        .help(thread.cwd)
    }

    /// Claude = its signature coral/orange, Codex = blue.
    private var brandColor: Color {
        thread.source.isClaude ? Color(red: 0.85, green: 0.47, blue: 0.34) : Color.blue
    }

    private var rowBackground: Color {
        if starred { return Color.yellow.opacity(hovering ? 0.20 : 0.12) }
        return brandColor.opacity(hovering ? 0.14 : 0.06)
    }

    private var dotColor: Color {
        switch thread.status {
        case .working: return .purple
        case .done: return .green
        case .needsInput: return .orange
        case .error: return .red
        case .idle: return Color.gray.opacity(0.5)
        }
    }

    private var relTime: String {
        let s = Int(-thread.lastActivity.timeIntervalSinceNow)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h\((s % 3600) / 60)m"
    }
}
