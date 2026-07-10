import SwiftUI

extension Notification.Name {
    static let agentDeckResize = Notification.Name("agentdeck.resize")
}

struct DeckView: View {
    @ObservedObject var store: Store

    var body: some View {
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
                    ForEach(store.threads) { ThreadRow(thread: $0) }
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
            let working = store.threads.filter { $0.status == .working }.count
            let ready = store.threads.filter { $0.status == .ready }.count
            Text("\(working) working · \(ready) ready")
                .font(.system(size: 10)).foregroundStyle(.secondary)
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
    @State private var hovering = false

    var body: some View {
        Button { Actions.open(thread) } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(dotColor).frame(width: 7, height: 7).padding(.top, 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(thread.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Text("\(thread.source.short) · \(thread.projectName) · \(relTime)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if hovering, !thread.summary.isEmpty {
                        Text(thread.summary)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 3)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(hovering ? Color.white.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            NotificationCenter.default.post(name: .agentDeckResize, object: nil)
        }
        .help(thread.cwd)
    }

    private var dotColor: Color {
        switch thread.status {
        case .working: return .green
        case .ready: return .orange
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
