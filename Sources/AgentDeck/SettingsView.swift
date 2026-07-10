import SwiftUI

/// In-card settings page. Everything is UserDefaults-backed; Config reads live.
struct SettingsView: View {
    @AppStorage("windowHours") private var windowHours = 36.0
    @AppStorage("doneRetentionHours") private var doneHours = 3.0
    @AppStorage("needsRetentionHours") private var needsHours = 12.0
    @AppStorage("dimAfterHours") private var dimHours = 24.0
    @AppStorage("overdueMinutes") private var overdueMin = 10.0
    @AppStorage("muted") private var muted = false
    @AppStorage("hideSpawned") private var hideSpawned = true
    @AppStorage("aiTitlesOff") private var aiTitlesOff = false
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toggleRow("Do not disturb (mute sounds)", $muted)
            toggleRow("Hide tool-spawned agents (Codex reviewers)", $hideSpawned)
            toggleRow("AI titles & summaries (gpt-oss-120b via OpenRouter)",
                      Binding(get: { !aiTitlesOff }, set: { aiTitlesOff = !$0 }))
            Divider().opacity(0.3)
            stepperRow("Keep done/idle threads", value: $doneHours, unit: "h", range: 1...24, step: 1)
            stepperRow("Keep needs-input threads", value: $needsHours, unit: "h", range: 1...36, step: 1)
            stepperRow("Dim threads older than", value: $dimHours, unit: "h", range: 2...36, step: 2)
            stepperRow("Hard cutoff (max age)", value: $windowHours, unit: "h", range: 6...72, step: 6)
            stepperRow("Red timer when waiting", value: $overdueMin, unit: "min", range: 2...60, step: 2)
            Divider().opacity(0.3)
            Text("£ anywhere toggles the deck · click the \"need you\" count to jump to the longest-waiting thread")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(12)
    }

    private func toggleRow(_ label: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) { Text(label).font(.system(size: 10.5)) }
            .toggleStyle(.switch).controlSize(.mini)
    }

    private func stepperRow(_ label: String, value: Binding<Double>,
                            unit: String, range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text(label).font(.system(size: 10.5))
            Spacer()
            Text("\(Int(value.wrappedValue))\(unit)")
                .font(.system(size: 10.5, weight: .medium)).monospacedDigit()
            Stepper("", value: value, in: range, step: step)
                .labelsHidden().controlSize(.mini)
        }
    }
}
