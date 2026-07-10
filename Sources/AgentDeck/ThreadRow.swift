import SwiftUI

struct ThreadRow: View {
    let thread: AgentThread
    let compact: Bool
    let starred: Bool
    let onStar: () -> Void
    let onDismiss: () -> Void
    @State private var hovering = false   // immediate: highlight + buttons
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
                    if !compact { subtitle }
                    if !compact, !thread.summary.isEmpty { summaryText }
                }
                Spacer(minLength: 0)
                if compact {
                    Text(relTime).font(.system(size: 9))
                        .foregroundStyle(overdue ? Color.red : Color.secondary).padding(.top, 2)
                }
                brandMark
                hoverButtons
            }
            .padding(.horizontal, 8).padding(.vertical, compact ? 3 : 5)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.yellow.opacity(starred ? 0.22 : 0), lineWidth: 1))
            .shadow(color: .yellow.opacity(starred ? 0.35 : 0), radius: starred ? 4 : 0)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: starred)
        }
        .buttonStyle(.plain)
        .opacity(ageOpacity)
        .animation(.easeOut(duration: Config.animDuration), value: expanded)
        .onHover(perform: hoverChanged)
        .help(thread.cwd)
    }

    private var subtitle: some View {
        let agent: Text = Text(thread.spawned ? "agent · " : "").foregroundStyle(Color.secondary.opacity(0.6))
        let proj: Text = Text("\(thread.projectName) · ").foregroundStyle(Color.secondary)
        let time: Text = Text(relTime).foregroundStyle(overdue ? Color.red : Color.secondary)
        return (agent + proj + time)
            .font(.system(size: 9))
            .lineLimit(1)
    }

    /// Brand mark: Claude's ✳ in coral, code-brackets in blue for Codex.
    private var brandMark: some View {
        Group {
            if thread.source.isClaude {
                Text("✳").font(.system(size: 10, weight: .bold))
            } else {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 7, weight: .bold))
            }
        }
        .foregroundStyle(brandColor.opacity(0.9))
        .frame(width: 12)
        .help(thread.source.rawValue)
    }

    /// Waiting on the user for too long: make the timer guilt-trip in red.
    private var overdue: Bool {
        thread.status == .needsInput && -thread.lastActivity.timeIntervalSinceNow > Config.overdueAfter
    }

    // Always in the layout; only its height + opacity animate, and it's clipped —
    // so the text can never paint over neighbouring rows. Finite -> finite heights
    // because 0 <-> .infinity is not animatable and twitches.
    private var summaryText: some View {
        Text(thread.summary)
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)
            .lineLimit(5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 3)
            .frame(maxHeight: expanded ? 160 : 0, alignment: .top)
            .clipped()
            .opacity(expanded ? 1 : 0)
    }

    // Always in the layout (opacity-only) so hovering never reflows the row.
    private var hoverButtons: some View {
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

    private func hoverChanged(_ h: Bool) {
        expandTask?.cancel()
        hovering = h
        if h, !compact {
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

    /// Claude = its signature coral/orange, Codex = blue.
    private var brandColor: Color {
        thread.source.isClaude ? Color(red: 0.85, green: 0.47, blue: 0.34) : Color.blue
    }

    private var rowBackground: Color {
        // Starred rows keep their brand tint — the glow + gold star carry the state.
        brandColor.opacity(hovering ? 0.14 : 0.06)
    }

    /// Fade stale threads: untouched >24h reads as background noise.
    private var ageOpacity: Double {
        let age = -thread.lastActivity.timeIntervalSinceNow
        if age > Config.dimAfter { return 0.45 }
        if thread.status == .idle { return 0.75 }
        return 1
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
