import Cocoa
import InputMethodKit

/// The text of the current line that precedes the cursor, as handed to the
/// mlh engine, together with where it lives in the client document.
struct DocumentContext {
    /// Text from the start of the current line (or at most ~1024 UTF-16 units
    /// back) up to the cursor.
    let text: String
    /// UTF-16 location of `text`'s first character in the client document, or
    /// nil when the context came from the typed-buffer fallback.
    let location: Int?

    var isFallback: Bool { location == nil }
}

/// A fallback record of the current line as typed through this IME, used for
/// clients that cannot report the text before the cursor.
struct TypedBuffer {
    static let maxLength = 512

    private(set) var text: String = ""

    mutating func reset() { text = "" }

    mutating func set(_ s: String) {
        text = ""
        append(s)
    }

    mutating func append(_ s: String) {
        guard !s.isEmpty else { return }
        text += s
        // Only the current line is of interest.
        if let idx = text.lastIndex(where: { TextContext.isLineBreak($0) }) {
            text = String(text[text.index(after: idx)...])
        }
        if text.count > Self.maxLength {
            text = String(text.suffix(Self.maxLength))
        }
    }

    mutating func removeLast() {
        if !text.isEmpty { text.removeLast() }
    }
}

enum TextContext {
    /// Maximum number of UTF-16 units requested from the client.
    static let maxLookBehind = 1024

    static func isLineBreak(_ c: Character) -> Bool {
        c == "\n" || c == "\r" || c == "\r\n" || c == "\u{2028}" || c == "\u{2029}"
    }

    private static func isLineBreakUnit(_ u: unichar) -> Bool {
        u == 0x0A || u == 0x0D || u == 0x2028 || u == 0x2029
    }

    /// Returns the text before the cursor if it ends with "/".
    ///
    /// Primary source is the client's document access API; when that is not
    /// available (or does not end with "/"), the typed buffer is used if *it*
    /// ends with "/". Returns nil if there is nothing for mlh to do.
    static func fetch(client: IMKTextInput, typed: TypedBuffer) -> DocumentContext? {
        if let api = apiContext(client: client), api.text.hasSuffix("/") {
            return api
        }
        if typed.text.hasSuffix("/") {
            return DocumentContext(text: typed.text, location: nil)
        }
        return nil
    }

    /// Reads the current line before the cursor through `IMKTextInput`.
    static func apiContext(client: IMKTextInput) -> DocumentContext? {
        let selected = client.selectedRange()
        guard selected.location != NSNotFound, selected.length == 0 else { return nil }
        let cursor = selected.location
        let length = min(maxLookBehind, cursor)
        guard length > 0 else { return DocumentContext(text: "", location: cursor) }
        let start = cursor - length
        guard let attributed = client.attributedSubstring(from: NSRange(location: start, length: length)) else {
            return nil
        }
        let ns = attributed.string as NSString
        guard ns.length == length else { return nil }

        // Trim to the part after the last line break.
        var offset = 0
        var i = ns.length - 1
        while i >= 0 {
            if isLineBreakUnit(ns.character(at: i)) {
                offset = i + 1
                break
            }
            i -= 1
        }
        // Drop a leading lone low surrogate (we may have cut a pair in half).
        if offset < ns.length, (0xDC00...0xDFFF).contains(ns.character(at: offset)) {
            offset += 1
        }
        let text = ns.substring(from: offset)
        return DocumentContext(text: text, location: start + offset)
    }

    // MARK: - Character / UTF-16 offset helpers

    /// The first `n` Characters of `s`.
    static func prefix(_ s: String, _ n: Int) -> String { String(s.prefix(max(0, n))) }

    /// Characters `[from, to)` of `s` (clamped).
    static func slice(_ s: String, _ from: Int, _ to: Int? = nil) -> String {
        let chars = Array(s)
        let lo = max(0, min(from, chars.count))
        let hi = max(lo, min(to ?? chars.count, chars.count))
        return String(chars[lo..<hi])
    }

    /// UTF-16 length of the first `n` Characters of `s`.
    static func utf16Offset(_ s: String, _ n: Int) -> Int { prefix(s, n).utf16.count }

    /// Number of leading Characters `a` and `b` have in common.
    static func commonPrefixLength(_ a: String, _ b: String) -> Int {
        var n = 0
        var ia = a.makeIterator(), ib = b.makeIterator()
        while let ca = ia.next(), let cb = ib.next(), ca == cb { n += 1 }
        return n
    }

    // MARK: - Clients that ignore replacementRange

    private static var syntheticDeletionCache: [String: Bool] = [:]

    /// Whether the client app reports the text before the cursor but ignores
    /// `replacementRange` (Chromium/Electron: Chrome, Discord, Slack, VS Code...),
    /// so the old text has to be deleted with synthetic Backspaces.
    ///
    /// Can be overridden per app with
    ///   defaults write com.github.kazu.inputmethod.mlh SyntheticDeletionApps -array <bundle id>...
    ///   defaults write com.github.kazu.inputmethod.mlh ReplacementRangeApps -array <bundle id>...
    static func needsSyntheticDeletion(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        let defaults = UserDefaults.standard
        if defaults.stringArray(forKey: "SyntheticDeletionApps")?.contains(bundleID) == true { return true }
        if defaults.stringArray(forKey: "ReplacementRangeApps")?.contains(bundleID) == true { return false }
        if let cached = syntheticDeletionCache[bundleID] { return cached }
        let result = isChromiumBased(bundleID: bundleID)
        syntheticDeletionCache[bundleID] = result
        return result
    }

    private static func isChromiumBased(bundleID: String) -> Bool {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let frameworks = app.appendingPathComponent("Contents/Frameworks")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
        return names.contains { name in
            name == "Electron Framework.framework"
                || (name.hasSuffix(" Framework.framework")
                    && ["Chrome", "Chromium", "Edge", "Brave", "Vivaldi", "Opera", "Arc"].contains { name.contains($0) })
        }
    }

    // MARK: - Synthetic key events (fallback deletion)

    static let backspaceKeyCode: CGKeyCode = 51

    /// Whether this process may post keyboard events. Prompts (once per
    /// process) for Accessibility permission when not yet granted.
    static func ensureAccessibility() -> Bool {
        if AXIsProcessTrusted() { return true }
        if !didPromptAccessibility {
            didPromptAccessibility = true
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        return false
    }

    private static var didPromptAccessibility = false

    /// Interval between synthetic Backspaces. Posting them back to back lets
    /// terminal apps receive several DEL bytes in one read, and some TUIs
    /// (e.g. Claude Code in Ghostty) then count them as a single Backspace.
    static let backspaceInterval: TimeInterval = 0.02

    /// Posts `count` Backspace key presses to the HID event tap, one every
    /// `backspaceInterval` seconds.
    static func postBackspaces(_ count: Int) {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .privateState)
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + backspaceInterval * Double(i)) {
                for down in [true, false] {
                    guard let ev = CGEvent(keyboardEventSource: source, virtualKey: backspaceKeyCode,
                                           keyDown: down) else { continue }
                    ev.flags = []
                    ev.post(tap: .cghidEventTap)
                }
            }
        }
    }
}
