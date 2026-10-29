import Cocoa
import MLHCore
import InputMethodKit
import Carbon
import os

typealias MLHClient = IMKTextInput & NSObjectProtocol

let mlhBundleIdentifier = Bundle.main.bundleIdentifier ?? "com.github.kazu.inputmethod.mlh"
private let log = Logger(subsystem: mlhBundleIdentifier, category: "input")

private let notFoundRange = NSRange(location: NSNotFound, length: 0)

/// State shared by all input controllers of this process.
final class MLHShared {
    static let shared = MLHShared()

    let engine = MLHEngine()
    private var dictionaryLoaded = false
    private var dictionaryModified: Date?

    /// Reloads the user dictionary when the file's mtime changed (or the first time).
    func reloadUserDictionaryIfNeeded() {
        let url = UserDictionary.defaultURL
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = attrs?[.modificationDate] as? Date
        if dictionaryLoaded && mtime == dictionaryModified { return }
        dictionaryLoaded = true
        dictionaryModified = mtime
        engine.userDictionary = mtime == nil ? UserDictionary() : UserDictionary.load(from: url)
        log.debug("user dictionary (re)loaded, exists: \(mtime != nil)")
    }

    /// Loaded on first use; nil when the bundle has no azooKey dictionary.
    private lazy var azooKey: AzooKeyTransliterator? =
        AzooKeyTransliterator.bundledDictionaryURL.map {
            AzooKeyTransliterator(dictionaryURL: $0, zenzaiWeightURL: Self.zenzaiModelURL,
                                  contextLength: Self.integerDefault("ZenzaiContextLength") ?? 40,
                                  inferenceLimit: Self.integerDefault("ZenzaiInferenceLimit") ?? 10)
        }

    private static func integerDefault(_ key: String) -> Int? {
        UserDefaults.standard.object(forKey: key) == nil ? nil : UserDefaults.standard.integer(forKey: key)
    }

    /// The zenz model for azooKey's neural conversion: the ZenzaiModel default,
    /// else ~/Library/Application Support/mlh/zenz.gguf, if the file exists.
    static var zenzaiModelURL: URL? {
        let path = UserDefaults.standard.string(forKey: "ZenzaiModel").map { ($0 as NSString).expandingTildeInPath }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/mlh/zenz.gguf").path
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    /// The kanji converter chosen by the KanjiBackend default: "google" (the
    /// Google CGI API) or "azookey" (local, also used when unset).
    func transliterator() -> Transliterator {
        if UserDefaults.standard.string(forKey: "KanjiBackend") != "google" {
            if let azooKey { return azooKey }
            log.error("azooKey dictionary not found; using Google")
        }
        return GoogleTransliterator()
    }

    /// Loads the azooKey dictionary and the zenz model in the background, so
    /// that the first conversion does not wait for them.
    func warmUp() {
        guard UserDefaults.standard.string(forKey: "KanjiBackend") != "google", let azooKey else { return }
        DispatchQueue.global(qos: .utility).async {
            let start = Date()
            _ = azooKey.convert("にほんご", context: "これは")
            log.debug("azooKey warmed up in \(Int(Date().timeIntervalSince(start) * 1000))ms")
        }
    }
}

/// Selection among user-dictionary candidates (mlh-select-mode-map).
struct SelectState {
    let outcome: MLHOutcome
    var choices: [Int]
    /// Index of the selection currently being edited.
    var k: Int
    /// Character offset in the rendered text where the marked text starts.
    let markStart: Int

    var currentSelection: MLHSelection { outcome.selections[k] }
}

/// A kanji conversion running in the background (the Google request takes
/// 0.1–0.3 s), so that the document can be edited meanwhile.
final class ConversionTask {
    let source: String
    private(set) var result: KanjiConversion?
    private var waiters: [(KanjiConversion) -> Void] = []

    /// `context` is the text before `source` on the same line.
    init(source: String, context: String = "") {
        self.source = source
        let transliterator = MLHShared.shared.transliterator()
        DispatchQueue.global(qos: .userInitiated).async {
            let conversion = KanjiConversion(source: source, transliterator: transliterator, context: context)
            DispatchQueue.main.async {
                self.result = conversion
                let waiters = self.waiters
                self.waiters = []
                waiters.forEach { $0(conversion) }
            }
        }
    }

    /// Calls `f` on the main thread once the conversion is ready.
    func whenReady(_ f: @escaping (KanjiConversion) -> Void) {
        if let result { f(result) } else { waiters.append(f) }
    }
}

/// Waiting for a `ConversionTask` or an `ExecuteTask`; keys typed meanwhile are
/// replayed afterwards.
final class WaitState {
    /// Shown as marked text, and committed if the wait is given up.
    let source: String
    let cancel: () -> Void
    var queued: [NSEvent] = []
    init(source: String, cancel: @escaping () -> Void = {}) {
        self.source = source
        self.cancel = cancel
    }
}

enum InputState {
    case idle
    case selecting(SelectState)
    case waiting(WaitState)
    case converting(KanjiConversion)
}

/// Key codes (ANSI layout positions; independent of the keyboard layout).
private enum KeyCode {
    static let returnKey: UInt16 = 36
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let backspace: UInt16 = 51
    static let escape: UInt16 = 53
    static let keypadEnter: UInt16 = 76
    static let home: UInt16 = 115
    static let pageUp: UInt16 = 116
    static let forwardDelete: UInt16 = 117
    static let end: UInt16 = 119
    static let pageDown: UInt16 = 121
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126

    /// Letter for the key at an ANSI position, used when control is held and
    /// `charactersIgnoringModifiers` does not give a letter.
    static let ansiLetters: [UInt16: Character] = [
        0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h", 34: "i",
        38: "j", 40: "k", 37: "l", 46: "m", 45: "n", 31: "o", 35: "p", 12: "q",
        15: "r", 1: "s", 17: "t", 32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
    ]
}

/// A decoded key-down event.
private struct Key {
    let keyCode: UInt16
    let shift: Bool
    let ctrl: Bool
    let opt: Bool
    let cmd: Bool
    let characters: String

    init(_ event: NSEvent) {
        keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        shift = flags.contains(.shift)
        ctrl = flags.contains(.control)
        opt = flags.contains(.option)
        cmd = flags.contains(.command)
        characters = event.characters ?? ""
        if ctrl && !cmd && !opt {
            let base = (event.charactersIgnoringModifiers ?? "").lowercased()
            if base.count == 1, let c = base.first, c.isASCII, c.isLetter {
                ctrlLetter = c
            } else {
                ctrlLetter = KeyCode.ansiLetters[keyCode]
            }
        } else {
            ctrlLetter = nil
        }
    }

    /// The letter of a Ctrl-<letter> combination (no cmd/opt).
    let ctrlLetter: Character?

    var noModifiers: Bool { !shift && !ctrl && !opt && !cmd }

    /// Plain Space (Shift/Ctrl/Opt/Cmd all released).
    var isPlainSpace: Bool { keyCode == KeyCode.space && noModifiers }

    var isReturn: Bool {
        (keyCode == KeyCode.returnKey || keyCode == KeyCode.keypadEnter) && !ctrl && !cmd
    }

    var isPlainBackspace: Bool { keyCode == KeyCode.backspace && !ctrl && !cmd && !opt }

    /// A printable ASCII character (32...126) typed without Ctrl/Cmd.
    var printableASCII: Character? {
        guard !ctrl, !cmd, characters.unicodeScalars.count == 1,
              let u = characters.unicodeScalars.first, (0x20...0x7E).contains(u.value) else { return nil }
        return Character(u)
    }
}

@objc(MLHInputController)
final class MLHInputController: IMKInputController {
    private var state: InputState = .idle
    private var typed = TypedBuffer()
    private var currentClient: MLHClient?

    /// Candidate list visibility in conversion mode (shown after the first
    /// next/previous on the current segment).
    private var conversionPanelVisible = false

    // Fallback (typed buffer) editing: synthetic backspaces in flight.
    private var pendingSyntheticBackspaces = 0
    private var pendingContinuation: (() -> Void)?
    private var pendingTimeout: DispatchWorkItem?

    private var shared: MLHShared { MLHShared.shared }

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        currentClient = inputClient as? MLHClient
    }

    // MARK: - IMKStateSetting

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.leftMouseDown.rawValue)
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        if let client = sender as? MLHClient { currentClient = client }
        typed.reset()
        shared.reloadUserDictionaryIfNeeded()
    }

    override func deactivateServer(_ sender: Any!) {
        commit(client: (sender as? MLHClient) ?? currentClient)
        cancelPendingEdit()
        CandidatePanel.shared.hide()
        typed.reset()
        super.deactivateServer(sender)
    }

    override func commitComposition(_ sender: Any!) {
        commit(client: (sender as? MLHClient) ?? currentClient)
    }

    override func candidates(_ sender: Any!) -> [Any]! { [] }

    // MARK: - Event entry point

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else { return false }
        guard let client = (sender as? MLHClient) ?? currentClient else { return false }
        currentClient = client

        if event.type == .leftMouseDown {
            if case .idle = state {
                typed.reset()
            } else {
                commit(client: client)
            }
            return false
        }
        guard event.type == .keyDown else { return false }

        if pendingSyntheticBackspaces > 0 {
            if event.keyCode == KeyCode.backspace {
                pendingSyntheticBackspaces -= 1
                if pendingSyntheticBackspaces == 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + TextContext.backspaceInterval) { [weak self] in
                        self?.runPendingContinuation()
                    }
                }
                return false
            }
            return true   // ignore other keys while our deletion is in flight
        }

        let key = Key(event)
        switch state {
        case .idle:
            return handleIdle(key, event: event, client: client)
        case .selecting(let s):
            return handleSelecting(s, key: key, event: event, client: client)
        case .waiting(let w):
            if key.cmd {
                w.cancel()
                finish(committing: w.source, client: client)
                return false
            }
            if key.keyCode == KeyCode.escape || key.ctrlLetter == "g" {
                w.cancel()
                finish(committing: w.source, client: client)
                return true
            }
            if w.queued.count < 64 { w.queued.append(event) }
            return true
        case .converting(let conversion):
            return handleConverting(conversion, key: key, event: event, client: client)
        }
    }

    // MARK: - Idle

    private func handleIdle(_ key: Key, event: NSEvent, client: MLHClient) -> Bool {
        if key.isPlainSpace {
            return handleSpace(client: client)
        }
        updateTypedBuffer(key)
        return false
    }

    private func updateTypedBuffer(_ key: Key) {
        if key.cmd || key.ctrl { typed.reset(); return }
        switch key.keyCode {
        case KeyCode.backspace:
            typed.removeLast()
            return
        case KeyCode.returnKey, KeyCode.keypadEnter, KeyCode.tab, KeyCode.escape,
             KeyCode.left, KeyCode.right, KeyCode.up, KeyCode.down,
             KeyCode.home, KeyCode.end, KeyCode.pageUp, KeyCode.pageDown, KeyCode.forwardDelete:
            typed.reset()
            return
        default:
            break
        }
        let chars = key.characters
        let printable = !chars.isEmpty && chars.unicodeScalars.allSatisfy { u in
            u.value >= 0x20 && u.value != 0x7F && !(0xF700...0xF8FF).contains(u.value)
        }
        if printable {
            typed.append(chars)
        } else {
            typed.reset()
        }
    }

    private func handleSpace(client: MLHClient) -> Bool {
        guard let context = TextContext.fetch(client: client, typed: typed) else {
            log.debug("space: no context ending with '/'; pass through")
            typed.append(" ")
            return false
        }
        log.debug("space: context from \(context.isFallback ? "typed buffer" : "client API", privacy: .public): \(context.text, privacy: .private)")

        let app = client.bundleIdentifier()
        shared.engine.executeAvailable = { Execute.isAvailable($0, app: app) }
        let result = shared.engine.run(context.text)
        switch result {
        case .passThrough:
            log.debug("engine: passThrough")
            typed.append(" ")
            return false
        case .failure(let message):
            log.debug("engine: failure \(message, privacy: .public)")
            NSSound.beep()
            return true
        case .edit(let outcome):
            log.debug("engine: edit, \(outcome.selections.count) selection(s), kanji: \(outcome.convertToKanji)")
            let synthetic = context.isFallback
                || TextContext.needsSyntheticDeletion(bundleID: client.bundleIdentifier())
            log.debug("client \(client.bundleIdentifier() ?? "?", privacy: .public): synthetic deletion \(synthetic)")
            if synthetic && !TextContext.ensureAccessibility() {
                log.debug("synthetic deletion needed but no Accessibility permission; pass through")
                NSSound.beep()
                typed.append(" ")
                return false
            }
            apply(outcome, context: context, syntheticDeletion: synthetic, client: client)
            // With synthetic deletion the Space is let through on purpose and
            // deleted together with the old text: some apps (Ghostty) insert it
            // even when the IME reports the key as handled.
            return !synthetic
        }
    }

    private static func needsKanji(_ convert: Bool, henkanBegin: Int, textCount: Int) -> Bool {
        convert && henkanBegin < textCount
    }

    private enum Pending {
        case none
        case select(SelectState)
        case convert(ConversionTask)
        case execute(ExecuteTask)
    }

    /// Replaces the context with the engine's outcome, entering selection or
    /// conversion state for the part that stays marked.
    private func apply(_ outcome: MLHOutcome, context: DocumentContext, syntheticDeletion: Bool,
                       client: MLHClient) {
        let newText = outcome.text
        let newCount = newText.count
        let kanji = Self.needsKanji(outcome.convertToKanji, henkanBegin: outcome.henkanBegin, textCount: newCount)

        var markStart: Int? = outcome.selections.first?.range.lowerBound
        if kanji { markStart = min(markStart ?? Int.max, outcome.henkanBegin) }
        let executeTask = outcome.executeBegin.flatMap {
            Execute.makeTask(source: TextContext.slice(newText, $0), key: outcome.executeKey,
                             clientBundleID: client.bundleIdentifier())
        }
        if executeTask != nil, let begin = outcome.executeBegin { markStart = min(markStart ?? Int.max, begin) }

        let old = context.text
        let prefixLength = min(TextContext.commonPrefixLength(old, newText), markStart ?? Int.max)
        let committed = TextContext.slice(newText, prefixLength, markStart)
        let oldSuffix = TextContext.slice(old, prefixLength)

        // Prepare what will be marked before touching the document (the kanji
        // conversion does a synchronous network request).
        let pending: Pending
        if let markStart {
            if let executeTask {
                pending = .execute(executeTask)
            } else if !outcome.selections.isEmpty {
                pending = .select(SelectState(outcome: outcome,
                                              choices: Array(repeating: 0, count: outcome.selections.count),
                                              k: 0, markStart: markStart))
            } else {
                let source = TextContext.slice(newText, outcome.henkanBegin)
                let context = TextContext.slice(newText, 0, outcome.henkanBegin)
                pending = .convert(ConversionTask(source: source, context: context))
            }
        } else {
            pending = .none
        }

        typed.set(TextContext.prefix(newText, markStart ?? newCount))

        if let location = context.location, !syntheticDeletion {
            let replacement = NSRange(location: location + TextContext.utf16Offset(old, prefixLength),
                                      length: oldSuffix.utf16.count)
            if case .none = pending {
                if !committed.isEmpty || replacement.length > 0 {
                    client.insertText(committed, replacementRange: replacement)
                }
            } else if committed.isEmpty {
                enter(pending, client: client, replacement: replacement)
            } else {
                client.insertText(committed, replacementRange: replacement)
                enter(pending, client: client, replacement: notFoundRange)
            }
        } else {
            let continuation: () -> Void = { [weak self] in
                guard let self else { return }
                let target = self.currentClient ?? client
                if !committed.isEmpty {
                    target.insertText(committed, replacementRange: notFoundRange)
                }
                self.enter(pending, client: target, replacement: notFoundRange)
            }
            // +1 for the Space, which is passed through to the app (see handleSpace).
            startSyntheticDeletion(count: oldSuffix.count + 1, continuation: continuation)
        }
    }

    private func enter(_ pending: Pending, client: MLHClient, replacement: NSRange) {
        switch pending {
        case .none:
            state = .idle
            CandidatePanel.shared.hide()
        case .select(let s):
            state = .selecting(s)
            updateSelecting(s, client: client, replacement: replacement)
        case .convert(let task):
            enterConversion(task, client: client, replacement: replacement)
        case .execute(let task):
            enterExecution(task, client: client, replacement: replacement)
        }
    }

    /// Shows the reading as marked text right away and switches to the
    /// conversion once the background request finishes; keys typed in
    /// between are replayed then.
    private func enterConversion(_ task: ConversionTask, client: MLHClient, replacement: NSRange) {
        if let conversion = task.result {
            enterConversion(conversion, client: client, replacement: replacement)
            return
        }
        let wait = WaitState(source: task.source)
        startWaiting(wait, client: client, replacement: replacement)
        task.whenReady { [weak self] conversion in
            guard let self, case .waiting(let current) = self.state, current === wait else { return }
            let target = self.currentClient ?? client
            self.enterConversion(conversion, client: target, replacement: notFoundRange)
            self.replay(wait.queued, client: target)
        }
    }

    /// Shows the line as marked text while the `x` backend runs (replaced by
    /// the output as it streams in), then commits the output, or the line
    /// unchanged, with a beep, when it failed.
    private func enterExecution(_ task: ExecuteTask, client: MLHClient, replacement: NSRange) {
        let wait = WaitState(source: task.source, cancel: task.cancel)
        startWaiting(wait, client: client, replacement: replacement)
        if !task.partial.isEmpty { showMarked(task.partial, client: client) }
        task.onProgress = { [weak self] text in
            guard let self, case .waiting(let current) = self.state, current === wait else { return }
            self.showMarked(text, client: self.currentClient ?? client)
        }
        task.whenReady { [weak self] output in
            guard let self, case .waiting(let current) = self.state, current === wait else { return }
            let target = self.currentClient ?? client
            if output == nil { NSSound.beep() }
            self.finish(committing: output ?? task.source, client: target)
            self.replay(wait.queued, client: target)
        }
    }

    private func startWaiting(_ wait: WaitState, client: MLHClient, replacement: NSRange) {
        state = .waiting(wait)
        showMarked(wait.source, client: client, replacement: replacement)
    }

    private func showMarked(_ text: String, client: MLHClient, replacement: NSRange = notFoundRange) {
        let attributed = NSMutableAttributedString(string: text)
        let range = NSRange(location: 0, length: attributed.length)
        attributed.addAttributes(markAttributes(style: Int(kTSMHiliteConvertedText), range: range), range: range)
        client.setMarkedText(attributed, selectionRange: NSRange(location: range.length, length: 0),
                             replacementRange: replacement)
    }

    /// Handles keys typed while waiting.
    private func replay(_ events: [NSEvent], client: MLHClient) {
        for event in events {
            // Keys that aren't consumed would have gone to the app.
            if !handle(event, client: client), let chars = event.characters, !chars.isEmpty,
               !event.modifierFlags.contains(.control),
               chars.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F && $0.value < 0xF700 }) {
                client.insertText(chars, replacementRange: notFoundRange)
                typed.append(chars)
            }
        }
    }

    // MARK: - Synthetic deletion (fallback context)

    private func startSyntheticDeletion(count: Int, continuation: @escaping () -> Void) {
        cancelPendingEdit()
        pendingSyntheticBackspaces = count
        pendingContinuation = continuation
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.pendingContinuation != nil else { return }
            log.debug("synthetic backspaces timed out (\(self.pendingSyntheticBackspaces) left)")
            self.runPendingContinuation()
        }
        pendingTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + TextContext.backspaceInterval * Double(count),
                                      execute: timeout)
        log.debug("posting \(count) synthetic backspace(s)")
        TextContext.postBackspaces(count)
    }

    private func runPendingContinuation() {
        pendingTimeout?.cancel()
        pendingTimeout = nil
        pendingSyntheticBackspaces = 0
        let continuation = pendingContinuation
        pendingContinuation = nil
        continuation?()
    }

    private func cancelPendingEdit() {
        pendingTimeout?.cancel()
        pendingTimeout = nil
        pendingSyntheticBackspaces = 0
        pendingContinuation = nil
    }

    // MARK: - Selecting (mlh-select-mode-map)

    private func handleSelecting(_ s: SelectState, key: Key, event: NSEvent, client: MLHClient) -> Bool {
        var s = s
        let count = s.currentSelection.candidates.count
        if key.isPlainSpace || key.ctrlLetter == "f" {
            // mlh-select-next-candidate
            s.choices[s.k] = (s.choices[s.k] + 1) % count
            state = .selecting(s)
            updateSelecting(s, client: client)
            return true
        }
        if key.isPlainBackspace || key.ctrlLetter == "b" {
            // mlh-select-prev-candidate
            s.choices[s.k] = (s.choices[s.k] - 1 + count) % count
            state = .selecting(s)
            updateSelecting(s, client: client)
            return true
        }
        if key.printableASCII == "/" {
            // mlh-select-kakutei
            fixSelection(s, client: client)
            return true
        }
        if key.isReturn || key.ctrlLetter == "m" || key.printableASCII != nil {
            // mlh-select-kakutei-and-self-insert: the event is read again.
            fixSelection(s, client: client)
            return handle(event, client: client)
        }
        // Anything else: fix everything, commit, and let the app have the key.
        commitSelecting(s, client: client)
        return false
    }

    /// Fixes the current selection and moves to the next one, or finishes.
    private func fixSelection(_ s: SelectState, client: MLHClient) {
        var s = s
        s.k += 1
        if s.k < s.outcome.selections.count {
            state = .selecting(s)
            updateSelecting(s, client: client)
            return
        }
        let rendered = s.outcome.render(choices: s.choices)
        let begin = max(rendered.henkanBegin, s.markStart)
        if Self.needsKanji(s.outcome.convertToKanji, henkanBegin: begin, textCount: rendered.text.count) {
            let committed = TextContext.slice(rendered.text, s.markStart, begin)
            let source = TextContext.slice(rendered.text, begin)
            let task = ConversionTask(source: source, context: TextContext.slice(rendered.text, 0, begin))
            if !committed.isEmpty {
                client.insertText(committed, replacementRange: notFoundRange)
                typed.append(committed)
            }
            enterConversion(task, client: client, replacement: notFoundRange)
        } else {
            commitSelecting(s, client: client)
        }
    }

    private func commitSelecting(_ s: SelectState, client: MLHClient) {
        let rendered = s.outcome.render(choices: s.choices)
        let text = TextContext.slice(rendered.text, s.markStart)
        finish(committing: text, client: client)
    }

    private func updateSelecting(_ s: SelectState, client: MLHClient, replacement: NSRange = notFoundRange) {
        let rendered = s.outcome.render(choices: s.choices)
        let marked = TextContext.slice(rendered.text, s.markStart)

        // Position of selection k in the rendered text: earlier selections may
        // have changed length.
        var shift = 0
        for j in 0..<s.k {
            let sel = s.outcome.selections[j]
            shift += sel.candidates[s.choices[j]].count - sel.range.count
        }
        let sel = s.currentSelection
        let lo = sel.range.lowerBound + shift - s.markStart
        let hi = lo + sel.candidates[s.choices[s.k]].count
        let loU = TextContext.utf16Offset(marked, lo)
        let hiU = TextContext.utf16Offset(marked, hi)
        let totalU = marked.utf16.count

        let attributed = NSMutableAttributedString(string: marked)
        var clause = 0
        for (range, style) in [(NSRange(location: 0, length: loU), kTSMHiliteConvertedText),
                               (NSRange(location: loU, length: hiU - loU), kTSMHiliteSelectedConvertedText),
                               (NSRange(location: hiU, length: totalU - hiU), kTSMHiliteConvertedText)]
            where range.length > 0 {
            attributed.addAttributes(markAttributes(style: Int(style), range: range), range: range)
            attributed.addAttribute(.markedClauseSegment, value: clause, range: range)
            clause += 1
        }
        client.setMarkedText(attributed, selectionRange: NSRange(location: hiU, length: 0),
                             replacementRange: replacement)
        showPanel(candidates: sel.candidates, selected: s.choices[s.k], client: client)
    }

    // MARK: - Converting (egg conversion mode)

    private func enterConversion(_ conversion: KanjiConversion, client: MLHClient, replacement: NSRange) {
        state = .converting(conversion)
        conversionPanelVisible = false
        updateConversion(conversion, client: client, replacement: replacement)
    }

    private func handleConverting(_ conv: KanjiConversion, key: Key, event: NSEvent, client: MLHClient) -> Bool {
        if key.cmd {
            finish(committing: conv.text, client: client)
            return false
        }

        // Digits pick from the visible candidate list.
        if conversionPanelVisible, !key.opt, let c = key.printableASCII, let d = c.wholeNumberValue, (1...9).contains(d) {
            let seg = conv.currentSegment
            let index = CandidatePanel.page(of: seg.index) * CandidatePanel.pageSize + (d - 1)
            if index < seg.candidates.count {
                conv.selectCandidate(index)
                conversionPanelVisible = false
                updateConversion(conv, client: client)
            } else {
                NSSound.beep()
            }
            return true
        }

        enum Action { case next, previous, forward, backward, first, last, shrink, enlarge, commit, abort }
        var action: Action?
        if let letter = key.ctrlLetter {
            switch letter {
            case "n": action = .next
            case "p": action = .previous
            case "f": action = .forward
            case "b": action = .backward
            case "a": action = .first
            case "e": action = .last
            case "i": action = .shrink
            case "o": action = .enlarge
            case "m", "l": action = .commit
            case "g", "c": action = .abort
            default: break
            }
        } else if !key.opt {
            switch key.keyCode {
            case KeyCode.space where !key.shift: action = .next
            case KeyCode.down: action = .next
            case KeyCode.up: action = .previous
            case KeyCode.left: action = key.shift ? .shrink : .backward
            case KeyCode.right: action = key.shift ? .enlarge : .forward
            case KeyCode.tab: action = .shrink          // TAB == C-i
            case KeyCode.returnKey, KeyCode.keypadEnter: action = .commit
            case KeyCode.escape, KeyCode.backspace: action = .abort
            default: break
            }
        }

        guard let action else {
            // egg-exit-conversion-unread-char: commit, then process the key normally.
            finish(committing: conv.text, client: client)
            return handle(event, client: client)
        }

        switch action {
        case .next:
            conv.nextCandidate()
            conversionPanelVisible = true
        case .previous:
            conv.previousCandidate()
            conversionPanelVisible = true
        case .forward:
            conv.forwardSegment()
            conversionPanelVisible = false
        case .backward:
            conv.backwardSegment()
            conversionPanelVisible = false
        case .first:
            conv.firstSegment()
            conversionPanelVisible = false
        case .last:
            conv.lastSegment()
            conversionPanelVisible = false
        case .shrink:
            conv.shrinkSegment()
            conversionPanelVisible = false
        case .enlarge:
            conv.enlargeSegment()
            conversionPanelVisible = false
        case .commit:
            finish(committing: conv.text, client: client)
            return true
        case .abort:
            finish(committing: conv.readingText, client: client)
            return true
        }
        updateConversion(conv, client: client)
        return true
    }

    private func updateConversion(_ conv: KanjiConversion, client: MLHClient, replacement: NSRange = notFoundRange) {
        let text = conv.text
        let attributed = NSMutableAttributedString(string: text)
        for (i, range) in conv.segmentRanges().enumerated() where range.length > 0 {
            let style = i == conv.current ? kTSMHiliteSelectedConvertedText : kTSMHiliteConvertedText
            attributed.addAttributes(markAttributes(style: Int(style), range: range), range: range)
            attributed.addAttribute(.markedClauseSegment, value: i, range: range)
        }
        client.setMarkedText(attributed, selectionRange: NSRange(location: text.utf16.count, length: 0),
                             replacementRange: replacement)
        if conversionPanelVisible {
            let seg = conv.currentSegment
            showPanel(candidates: seg.candidates, selected: seg.index, client: client)
        } else {
            CandidatePanel.shared.hide()
        }
    }

    // MARK: - Commit helpers

    /// Commits whatever is in progress.
    private func commit(client: MLHClient?) {
        switch state {
        case .idle:
            return
        case .selecting(let s):
            if let client {
                commitSelecting(s, client: client)
            }
        case .waiting(let w):
            w.cancel()
            if let client {
                finish(committing: w.source, client: client)
            }
        case .converting(let conv):
            if let client {
                finish(committing: conv.text, client: client)
            }
        }
        state = .idle
        CandidatePanel.shared.hide()
    }

    /// Replaces the marked text with `text` and returns to idle.
    private func finish(committing text: String, client: MLHClient) {
        client.insertText(text, replacementRange: notFoundRange)
        typed.append(text)
        state = .idle
        conversionPanelVisible = false
        CandidatePanel.shared.hide()
    }

    // MARK: - Presentation helpers

    private func markAttributes(style: Int, range: NSRange) -> [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [:]
        guard let dict = mark(forStyle: style, at: range) else {
            result[.underlineStyle] = style == Int(kTSMHiliteSelectedConvertedText)
                ? NSUnderlineStyle.thick.rawValue : NSUnderlineStyle.single.rawValue
            return result
        }
        for (k, v) in dict {
            if let name = k as? String {
                result[NSAttributedString.Key(name)] = v
            } else if let name = k as? NSAttributedString.Key {
                result[name] = v
            }
        }
        return result
    }

    private func showPanel(candidates: [String], selected: Int, client: MLHClient) {
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        CandidatePanel.shared.show(candidates: candidates, selected: selected, anchor: rect)
    }
}
