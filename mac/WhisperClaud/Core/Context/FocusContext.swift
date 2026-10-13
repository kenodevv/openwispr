import AppKit
import ApplicationServices
import Foundation

enum AppCategory: String, Sendable {
    case chat, email, documents, notes, code, browser, other

    var label: String {
        switch self {
        case .chat: return "Chat"
        case .email: return "E-Mail"
        case .documents: return "Dokument"
        case .notes: return "Notizen"
        case .code: return "Code/Terminal"
        case .browser: return "Browser"
        case .other: return "Allgemein"
        }
    }

    static func categorize(bundleId: String, windowTitle: String) -> AppCategory {
        let id = bundleId.lowercased()
        let title = windowTitle.lowercased()
        let chat = ["com.tinyspeck.slackmacgap", "com.hnc.discord", "com.apple.mobilesms", "net.whatsapp.whatsapp",
                    "ru.keepcoder.telegram", "org.telegram.desktop", "com.microsoft.teams", "com.facebook.archon", "com.signal"]
        let email = ["com.apple.mail", "com.microsoft.outlook", "com.readdle.smartemail", "com.superhuman", "com.mimestream", "com.airmail"]
        let docs = ["com.apple.iwork.pages", "com.microsoft.word", "notion.id", "md.obsidian", "com.google.docs", "com.craft", "com.apple.iwork.keynote"]
        let notes = ["com.apple.notes", "com.bear-writer", "com.apple.reminders", "com.apple.stickies"]
        let code = ["com.apple.dt.xcode", "com.microsoft.vscode", "com.todesktop.230313mzl4w4u92", "com.apple.terminal",
                    "com.googlecode.iterm2", "dev.warp", "com.jetbrains", "com.sublimetext", "dev.zed", "com.github.atom", "co.zeit.hyper", "org.alacritty", "net.kovidgoyal.kitty"]
        let browsers = ["com.apple.safari", "com.google.chrome", "org.mozilla.firefox", "company.thebrowser.browser",
                        "com.brave.browser", "com.microsoft.edgemac", "com.vivaldi", "com.operasoftware"]

        if chat.contains(where: { id.hasPrefix($0) }) { return .chat }
        if email.contains(where: { id.hasPrefix($0) }) { return .email }
        if notes.contains(where: { id.hasPrefix($0) }) { return .notes }
        if docs.contains(where: { id.hasPrefix($0) }) { return .documents }
        if code.contains(where: { id.hasPrefix($0) }) { return .code }
        if browsers.contains(where: { id.hasPrefix($0) }) {
            if title.contains("google docs") || title.contains("google tabellen") || title.contains("notion") { return .documents }
            if title.contains("gmail") || title.contains("outlook") || title.contains("mail") { return .email }
            if title.contains("slack") || title.contains("discord") || title.contains("whatsapp") || title.contains("teams") || title.contains("messenger") { return .chat }
            return .browser
        }
        return .other
    }
}

struct FocusContext: Sendable {
    var appName = ""
    var bundleId = ""
    var windowTitle = ""
    var selectedText = ""
    var textBeforeCursor = ""
    var isSecureField = false

    var category: AppCategory { AppCategory.categorize(bundleId: bundleId, windowTitle: windowTitle) }
}

/// Reads the frontmost app and (via Accessibility) the focused text element.
@MainActor
enum FocusContextProvider {
    private static let maxContextChars = 500
    private static let maxSelectionChars = 6000

    static func capture(readText: Bool) -> FocusContext {
        var ctx = FocusContext()
        guard let app = NSWorkspace.shared.frontmostApplication else { return ctx }
        ctx.appName = app.localizedName ?? ""
        ctx.bundleId = app.bundleIdentifier ?? ""
        guard AXIsProcessTrusted() else { return ctx }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        if let window = elementAttribute(appElement, kAXFocusedWindowAttribute) {
            ctx.windowTitle = stringAttribute(window, kAXTitleAttribute) ?? ""
        }
        guard let element = elementAttribute(appElement, kAXFocusedUIElementAttribute) else { return ctx }
        AXUIElementSetMessagingTimeout(element, 0.25)

        let role = stringAttribute(element, kAXRoleAttribute) ?? ""
        let subrole = stringAttribute(element, kAXSubroleAttribute) ?? ""
        ctx.isSecureField = role == "AXSecureTextField" || subrole == "AXSecureTextField"
        guard readText, !ctx.isSecureField else { return ctx }

        if let selected = stringAttribute(element, kAXSelectedTextAttribute) {
            ctx.selectedText = String(selected.prefix(maxSelectionChars))
        }
        if let range = rangeAttribute(element, kAXSelectedTextRangeAttribute) {
            let start = max(0, range.location - maxContextChars)
            var window = CFRange(location: start, length: range.location - start)
            if window.length > 0, let before = stringForRange(element, &window) {
                ctx.textBeforeCursor = before
            }
        }
        return ctx
    }

    // MARK: - AX helpers

    private static func rawAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = rawAttribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        guard let value = rawAttribute(element, name) else { return nil }
        return value as? String
    }

    private static func rangeAttribute(_ element: AXUIElement, _ name: String) -> CFRange? {
        guard let value = rawAttribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue((value as! AXValue), .cfRange, &range) else { return nil }
        return range
    }

    private static func stringForRange(_ element: AXUIElement, _ range: inout CFRange) -> String? {
        guard let param = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, param, &value)
        guard status == .success, let value else { return nil }
        return value as? String
    }
}
