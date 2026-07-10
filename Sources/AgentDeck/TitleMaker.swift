import Foundation

/// Turns a raw first-user-message into a readable thread title.
/// ponytail: pure heuristics — swap in an OpenRouter cheap-model titler if this ever feels weak.
enum TitleMaker {
    private static let fillerPrefixes = [
        "can you", "could you", "can u", "could u", "will you", "would you",
        "please", "pls", "plz", "hey", "yo", "ok so", "ok", "okay", "so",
        "i want you to", "i wan tyou to", "i want u to", "i need you to", "i'd like you to",
        "i want to", "i need", "also", "now", "next", "quick", "quickly",
        "for me", "make sure", "make sur", "u", "just",
    ]

    static func make(_ raw: String) -> String {
        var t = raw.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip leading filler words repeatedly ("ok so can you please ...").
        var stripped = true
        while stripped {
            stripped = false
            let lower = t.lowercased()
            for f in fillerPrefixes where lower.hasPrefix(f + " ") {
                t = String(t.dropFirst(f.count + 1))
                stripped = true
                break
            }
        }

        // Cut at the first sentence boundary, else at a word boundary near 64 chars.
        if let r = t.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?")),
           t.distance(from: t.startIndex, to: r.lowerBound) >= 20 {
            t = String(t[..<r.lowerBound])
        }
        if t.count > 64 {
            var cut = String(t.prefix(64))
            if let space = cut.range(of: " ", options: .backwards), cut.distance(from: cut.startIndex, to: space.lowerBound) > 40 {
                cut = String(cut[..<space.lowerBound])
            }
            t = cut + "…"
        }

        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return raw }
        return t.prefix(1).uppercased() + t.dropFirst()
    }
}
