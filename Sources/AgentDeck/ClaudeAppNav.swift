import AppKit
import ApplicationServices

/// Focus a specific session in the Claude desktop app. There is no deep link for
/// this (resume = import/duplicate), but the sidebar exposes one AXPopUpButton per
/// session described "More options for <title>", and the app maps session id ->
/// sidebar title in ~/Library/Application Support/Claude/claude-code-sessions/.
/// So: look up the title, find the row, scroll it visible, click left of the popup.
enum ClaudeAppNav {
    /// Async: retries while Electron lazily builds its AX tree after activation.
    static func focus(sessionId: String) {
        // Prompts the system Accessibility dialog on first use if not yet granted.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else { Notifier.log("nav: not AX trusted"); return }
        guard let title = appTitle(for: sessionId) else { Notifier.log("nav: no app title for \(sessionId.prefix(8))"); return }
        DispatchQueue.global(qos: .userInitiated).async {
            for attempt in 1...5 {
                Thread.sleep(forTimeInterval: attempt == 1 ? 0.8 : 0.7)
                if clickRow(title: title, expandIfNeeded: attempt == 2) {
                    Notifier.log("nav: focused '\(title)' (attempt \(attempt))")
                    return
                }
            }
            Notifier.log("nav: row '\(title)' not found — leaving app as-is")
        }
    }

    /// Newest claude-code-sessions record for this id that carries a title.
    static func appTitle(for sessionId: String) -> String? {
        let root = NSHomeDirectory() + "/Library/Application Support/Claude/claude-code-sessions"
        guard let en = FileManager.default.enumerator(atPath: root) else { return nil }
        var best: (stamp: Double, title: String)?
        for case let f as String in en where f.hasSuffix("local_\(sessionId).json") {
            guard let data = FileManager.default.contents(atPath: root + "/" + f),
                  let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let t = j["title"] as? String, !t.isEmpty else { continue }
            let stamp = (j["lastActivityAt"] as? Double) ?? 0
            if best == nil || stamp > best!.stamp { best = (stamp, t) }
        }
        return best?.title
    }

    // MARK: AX

    private static func clickRow(title: String, expandIfNeeded: Bool) -> Bool {
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop").first
        else { return false }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let win = (attr(ax, kAXWindowsAttribute) as? [AXUIElement])?.first else { return false }

        if let popup = find(win, role: "AXPopUpButton", description: "More options for \(title)") {
            if let parent = attr(popup, kAXParentAttribute) {
                AXUIElementPerformAction(parent as! AXUIElement, "AXScrollToVisible" as CFString)
                Thread.sleep(forTimeInterval: 0.15)
            }
            guard let f = frame(popup) else { return false }
            click(at: CGPoint(x: f.minX - 60, y: f.midY))
            return true
        }
        // Sidebar likely collapsed: press the expand button once, caller retries.
        if expandIfNeeded,
           let btn = find(win, role: "AXButton", descriptionContains: "sidebar",
                          excludeContains: "Collapse") {
            AXUIElementPerformAction(btn, kAXPressAction as CFString)
        }
        return false
    }

    private static func find(_ root: AXUIElement, role: String, description: String? = nil,
                             descriptionContains: String? = nil, excludeContains: String? = nil,
                             depth: Int = 0) -> AXUIElement? {
        if depth > 30 { return nil }
        if attr(root, kAXRoleAttribute) as? String == role {
            let d = (attr(root, "AXDescription") as? String) ?? ""
            let matches = description.map { $0 == d }
                ?? descriptionContains.map { d.localizedCaseInsensitiveContains($0) } ?? false
            if matches, excludeContains.map({ !d.contains($0) }) ?? true { return root }
        }
        for c in (attr(root, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            if let hit = find(c, role: role, description: description,
                              descriptionContains: descriptionContains,
                              excludeContains: excludeContains, depth: depth + 1) { return hit }
        }
        return nil
    }

    private static func attr(_ e: AXUIElement, _ a: String) -> AnyObject? {
        var v: AnyObject?
        AXUIElementCopyAttributeValue(e, a as CFString, &v)
        return v
    }

    private static func frame(_ e: AXUIElement) -> CGRect? {
        guard let posV = attr(e, kAXPositionAttribute), let sizeV = attr(e, kAXSizeAttribute)
        else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(posV as! AXValue, .cgPoint, &p)
        AXValueGetValue(sizeV as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    private static func click(at pt: CGPoint) {
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type,
                    mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
            usleep(30_000)
        }
    }
}
