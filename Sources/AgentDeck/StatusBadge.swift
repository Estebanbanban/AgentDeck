import AppKit

/// Menu-bar badge image. macOS 26.4 empirical minefield (14 bisection runs): the
/// ONLY config ever observed to materialize is a raw SF-symbol image with NOTHING
/// else set on the button — no title, no attributedTitle, no target/action, no
/// toolTip, no custom-drawn NSImage — and even that is flaky on this OS build.
/// Numbered SF symbols carry the count since a title is not an option.
enum StatusBadge {
    static func image(count: Int) -> NSImage? {
        let name: String
        switch count {
        case 0: name = "asterisk"
        case 1...50: name = "\(count).circle.fill"
        default: name = "exclamationmark.circle.fill"
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: "AgentDeck: \(count) waiting")
    }
}
