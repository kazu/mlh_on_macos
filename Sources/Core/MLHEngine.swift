// MLHEngine.swift --- Modeless Conversion Facility, ported from egg-mlh.el
//
// Original egg-mlh.el:
//   Copyright (C) 1999, 2000 Free Software Foundation, Inc
//   Author: NIIBE Yutaka <gniibe@fsij.org>
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2, or (at your option)
// any later version. See the LICENSE file.

import Foundation

// A port of egg-mlh.el (Egg Input Method Architecture).
// Function and variable names follow the original so the two can be read
// side by side. Emacs-only schemes are left out: `L` (evaluate Lisp) and
// `g` (mlh-greek, which egg never defined) fall into the "not in table"
// branch, exactly like any other character.
//
// Additions not in egg-mlh.el: `l` converts Latin-1 postfix notation
// (egg reserved `l` for an unimplemented "ligature"), and `x`, when an
// external command is configured, stands in for `mlh-userdef-function`.

/// A user-dictionary entry with several candidates, waiting for the user to choose.
public struct MLHSelection: Equatable {
    /// Character offsets into `MLHOutcome.text`.
    public let range: Range<Int>
    public let candidates: [String]
}

public struct MLHOutcome: Equatable {
    /// New text for the whole context. Each selection holds its first candidate.
    public let text: String
    /// Sorted and non-overlapping.
    public let selections: [MLHSelection]
    /// Character offset in `text` where kanji conversion starts (`henkan-begin`).
    public let henkanBegin: Int
    /// When true, `text[henkanBegin...]` goes through kanji conversion
    /// (`egg-convert-region henkan-begin (point)`).
    public let convertToKanji: Bool
    /// When set, `text[executeBegin...]` is handed to the execute backend
    /// (`x`) and replaced with its output.
    public let executeBegin: Int?
    /// The number typed before `x` (`2x/` -> "2"), selecting the settings.
    public let executeKey: String?

    public init(text: String, selections: [MLHSelection], henkanBegin: Int, convertToKanji: Bool,
                executeBegin: Int? = nil, executeKey: String? = nil) {
        self.text = text
        self.selections = selections
        self.henkanBegin = henkanBegin
        self.convertToKanji = convertToKanji
        self.executeBegin = executeBegin
        self.executeKey = executeKey
    }

    /// Re-renders `text` with the given candidate index for each selection.
    public func render(choices: [Int]) -> (text: String, henkanBegin: Int) {
        var chars = Array(text)
        var begin = henkanBegin
        for (i, sel) in selections.enumerated().reversed() {
            let choice = i < choices.count ? choices[i] : 0
            guard sel.candidates.indices.contains(choice) else { continue }
            let replacement = Array(sel.candidates[choice])
            chars.replaceSubrange(sel.range, with: replacement)
            if begin >= sel.range.upperBound {
                begin += replacement.count - sel.range.count
            }
        }
        return (String(chars), begin)
    }
}

public enum MLHResult: Equatable {
    /// Nothing to convert: the space is inserted as usual (`self-insert-command`).
    case passThrough
    /// The conversion signalled an error (e.g. a JIS code of the wrong length).
    case failure(String)
    case edit(MLHOutcome)
}

public final class MLHEngine {
    public var userDictionary: UserDictionary
    /// Whether `x` (with the number typed before it, if any) hands the line
    /// to an execute backend. Asked only when an `x/` is converted.
    public var executeAvailable: (String?) -> Bool = { _ in false }

    public init(userDictionary: UserDictionary = UserDictionary()) {
        self.userDictionary = userDictionary
    }

    /// `mlh-space-bar-backward-henkan`, run on the text that precedes the
    /// cursor (normally the current line).
    public func run(_ textBeforeCursor: String) -> MLHResult {
        let state = MLHState(text: textBeforeCursor, userDictionary: userDictionary,
                            executeAvailable: executeAvailable)
        do {
            try state.mlhBackwardHenkan()
        } catch let MLHError.message(msg) {
            return .failure(msg)
        } catch {
            return .failure("\(error)")
        }
        guard let henkanBegin = state.henkanBegin else { return .passThrough }
        let selections = state.selections.map { sel -> MLHSelection in
            let lo = min(sel.start.pos, sel.end.pos)
            return MLHSelection(range: lo..<sel.end.pos, candidates: sel.candidates)
        }.sorted { $0.range.lowerBound < $1.range.lowerBound }
        let convert = !state.inhibitHenkan && henkanBegin != state.point
        return .edit(MLHOutcome(text: String(state.buf), selections: selections,
                                henkanBegin: henkanBegin, convertToKanji: convert,
                                executeBegin: state.executeBegin, executeKey: state.executeKey))
    }
}

enum MLHError: Error { case message(String) }

/// An Emacs marker. `advances` is `marker-insertion-type`.
final class Marker {
    var pos: Int
    let advances: Bool
    init(_ pos: Int, advances: Bool) { self.pos = pos; self.advances = advances }
}

enum Scheme {
    case kanji, capitalize, userDefined, hiragana, jisCode, katakana, upcaseLetter
    case quit, smallLetter, whiteSpace, execute, hiraganaToKanji, zenkakuWhite, exit, zenkaku, latin
}

/// One activation of `mlh-backward-henkan` (its let-bound variables).
final class Frame {
    let endMarker: Marker
    var mlhBeg: Int?
    init(endMarker: Marker) { self.endMarker = endMarker }
}

final class MLHState {
    var buf: [Character]
    var point: Int
    var markers: [Marker] = []
    var henkanBegin: Int?
    var inhibitHenkan = true
    var selections: [(start: Marker, end: Marker, candidates: [String])] = []
    let userDictionary: UserDictionary
    let executeAvailable: (String?) -> Bool
    var executeBegin: Int?
    var executeKey: String?
    /// Nesting level of mlh-backward-henkan (1 for the word before the cursor).
    var depth = 0

    init(text: String, userDictionary: UserDictionary, executeAvailable: @escaping (String?) -> Bool = { _ in false }) {
        buf = Array(text)
        point = buf.count
        self.userDictionary = userDictionary
        self.executeAvailable = executeAvailable
    }

    // MARK: mlh-conversion-scheme-table

    static let conversionSchemeTable: [Character: Scheme] = [
        "-": .kanji, ",": .kanji, ".": .kanji,
        "a": .kanji, "c": .capitalize, "d": .userDefined, "e": .kanji, "f": .hiragana,
        "i": .kanji, "j": .jisCode, "k": .katakana, "l": .latin, "n": .kanji, "o": .kanji,
        "p": .upcaseLetter, "q": .quit, "s": .smallLetter, "u": .kanji,
        "w": .whiteSpace, "x": .execute,
        "H": .hiraganaToKanji, "W": .zenkakuWhite, "X": .exit, "Z": .zenkaku,
    ]

    // Character sets given to skip-chars-backward.
    static func romajiChar(_ c: Character) -> Bool {          // "-a-z,.'N[]"
        ("a"..."z").contains(c) || "-,.'N[]".contains(c)
    }
    static func graphicExceptSlash(_ c: Character) -> Bool {   // "\041-\056\060-\176"
        guard let v = c.asciiValue else { return false }
        return (0x21...0x2E).contains(v) || (0x30...0x7E).contains(v)
    }
    static func alnum(_ c: Character) -> Bool {                // "a-zA-Z0-9"
        c.isASCII && (c.isLetter || c.isNumber)
    }
    static func capitalizeChar(_ c: Character) -> Bool {       // "a-zA-Z1-9"
        c.isASCII && (c.isLetter || ("1"..."9").contains(c))
    }
    static func latinChar(_ c: Character) -> Bool {          // letters and the postfix marks
        c.isASCII && (c.isLetter || "`'^~\",*<>!?".contains(c))
    }
    static func digit(_ c: Character) -> Bool { ("0"..."9").contains(c) }
    static func hexDigit(_ c: Character) -> Bool { c.isASCII && c.isHexDigit }
    static func userDefChar(_ c: Character) -> Bool {          // "-a-zA-Z"
        c == "-" || (c.isASCII && c.isLetter)
    }
    static func hiraganaChar(_ c: Character) -> Bool {         // "ぁ-んー"
        guard c.unicodeScalars.count == 1, let u = c.unicodeScalars.first else { return false }
        return (0x3041...0x3093).contains(u.value) || u.value == 0x30FC
    }

    // MARK: Buffer primitives (Emacs semantics)

    var precedingChar: Character? { point > 0 ? buf[point - 1] : nil }
    var followingChar: Character? { point < buf.count ? buf[point] : nil }

    func makeMarker(_ pos: Int, advances: Bool) -> Marker {
        let m = Marker(pos, advances: advances)
        markers.append(m)
        return m
    }

    func releaseMarker(_ m: Marker) { markers.removeAll { $0 === m } }

    func forwardChar(_ n: Int) { point = max(0, min(buf.count, point + n)) }

    func skipCharsBackward(_ pred: (Character) -> Bool) {
        while point > 0 && pred(buf[point - 1]) { point -= 1 }
    }

    func insert(_ s: String) {
        let chars = Array(s)
        guard !chars.isEmpty else { return }
        buf.insert(contentsOf: chars, at: point)
        for m in markers where m.pos > point || (m.pos == point && m.advances) {
            m.pos += chars.count
        }
        point += chars.count
    }

    func deleteRegion(_ a: Int, _ b: Int) {
        let (lo, hi) = (min(a, b), max(a, b))
        guard lo < hi else { return }
        buf.removeSubrange(lo..<hi)
        let n = hi - lo
        for m in markers {
            if m.pos >= hi { m.pos -= n } else if m.pos > lo { m.pos = lo }
        }
        if point >= hi { point -= n } else if point > lo { point = lo }
    }

    func backwardDeleteChar(_ n: Int) { deleteRegion(point - n, point) }

    func substring(_ a: Int, _ b: Int) -> String { String(buf[min(a, b)..<max(a, b)]) }

    /// Replaces [a, b) leaving point at the end of the new text, like its-translate-region.
    func replaceRegion(_ a: Int, _ b: Int, with s: String) {
        deleteRegion(a, b)
        point = a
        insert(s)
    }

    /// Replaces [a, b) keeping point where it was (upcase-region and friends).
    func transformRegion(_ a: Int, _ b: Int, _ f: (String) -> String) {
        let saved = point
        let old = substring(a, b)
        let new = f(old)
        replaceRegion(a, b, with: new)
        let delta = new.count - old.count
        point = saved >= b ? saved + delta : saved
    }

    // MARK: mlh-backward-henkan

    func mlhBackwardHenkan() throws {
        guard precedingChar == "/" else { return }
        let frame = Frame(endMarker: makeMarker(point, advances: true))
        defer { releaseMarker(frame.endMarker) }
        depth += 1
        defer { depth -= 1 }
        forwardChar(-1)
        if let ch = precedingChar, let scheme = Self.conversionSchemeTable[ch] {
            try call(scheme, frame)
        } else {
            point = frame.endMarker.pos
        }
        if let beg = frame.mlhBeg {
            point = beg
            mlhDoSpacing()
            point = frame.endMarker.pos
        }
    }

    func call(_ scheme: Scheme, _ f: Frame) throws {
        switch scheme {
        case .kanji: try mlhKanji(f)
        case .capitalize: try mlhCaseRegion(f, Self.capitalizeChar, TextTransform.capitalize)
        case .upcaseLetter: try mlhCaseRegion(f, Self.alnum, TextTransform.upcase)
        case .userDefined: try mlhUserDefinedConversion(f)
        case .hiragana: try mlhHiragana(f)
        case .katakana: try mlhKatakana(f)
        case .jisCode: try mlhJisCode(f)
        case .quit: mlhQuit(f)
        case .exit: mlhExit(f)
        case .smallLetter: try mlhNoConversion(f)
        case .whiteSpace: try mlhWhiteSpace(f, " ")
        case .zenkakuWhite: try mlhWhiteSpace(f, "\u{3000}")
        case .execute: try mlhExecute(f)
        case .hiraganaToKanji: try mlhHiraganaToKanji(f)
        case .zenkaku: try mlhZenkaku(f)
        case .latin: try mlhCaseRegion(f, Self.latinChar, TextTransform.latin1Postfix)
        }
    }

    /// The tail shared by most schemes: recurse, set mlh-beg, and drop "X/".
    private func recurseAndDropScheme(_ f: Frame) throws -> Int {
        try mlhBackwardHenkan()
        let beg = point
        f.mlhBeg = beg
        point = f.endMarker.pos
        backwardDeleteChar(2)
        return beg
    }

    // mlh-zenkaku-white / mlh-white-space
    func mlhWhiteSpace(_ f: Frame, _ space: String) throws {
        forwardChar(-1)
        skipCharsBackward(Self.digit)
        let beg = try recurseAndDropScheme(f)
        let val = Int(substring(beg, point)) ?? 0
        deleteRegion(beg, point)
        insert(String(repeating: space, count: val == 0 ? 1 : val))
        if henkanBegin == nil { henkanBegin = beg }
    }

    // mlh-exit
    func mlhExit(_ f: Frame) {
        point = f.endMarker.pos
        backwardDeleteChar(2)
        insert(" ")
        henkanBegin = point
    }

    // mlh-upcase-letter / mlh-capitalize
    func mlhCaseRegion(_ f: Frame, _ skip: (Character) -> Bool, _ transform: (String) -> String) throws {
        forwardChar(-1)
        skipCharsBackward(skip)
        let beg = try recurseAndDropScheme(f)
        transformRegion(beg, point, transform)
        if henkanBegin == nil { henkanBegin = beg }
    }

    // mlh-jis-code
    func mlhJisCode(_ f: Frame) throws {
        forwardChar(-1)
        skipCharsBackward(Self.hexDigit)
        try mlhBackwardHenkan()
        guard f.endMarker.pos - point == 6 else { throw MLHError.message("invalid length") }
        let beg = point
        f.mlhBeg = beg
        guard let ch = TextTransform.jisCharacter(hex: substring(beg, f.endMarker.pos - 2)) else {
            throw MLHError.message("invalid code")
        }
        insert(ch)
        deleteRegion(point, f.endMarker.pos)
        if henkanBegin == nil { henkanBegin = beg }
    }

    // mlh-quit
    func mlhQuit(_ f: Frame) {
        point = f.endMarker.pos
        backwardDeleteChar(2)
        henkanBegin = point
    }

    // mlh-no-conversion (= mlh-small-letter)
    func mlhNoConversion(_ f: Frame) throws {
        forwardChar(-1)
        skipCharsBackward(Self.graphicExceptSlash)
        let beg = try recurseAndDropScheme(f)
        if henkanBegin == nil { henkanBegin = beg }
    }

    // mlh-execute. The execute backend plays mlh-userdef-function: it gets
    // the whole line before "Nx/" (only for the word before the cursor; the
    // optional number N picks the settings).
    func mlhExecute(_ f: Frame) throws {
        forwardChar(-1)
        if depth == 1 {
            let x = point
            skipCharsBackward(Self.digit)
            let key = point < x ? substring(point, x) : nil
            if executeAvailable(key) {
                deleteRegion(point, f.endMarker.pos)
                executeBegin = 0
                executeKey = key
                henkanBegin = 0
                return
            }
            point = x
        }
        let beg = try recurseAndDropScheme(f)
        if henkanBegin == nil { henkanBegin = beg }
    }

    // mlh-user-defined-conversion
    func mlhUserDefinedConversion(_ f: Frame) throws {
        forwardChar(-1)
        skipCharsBackward(Self.userDefChar)
        let beg = try recurseAndDropScheme(f)
        let key = substring(beg, point)
        let candidates = userDictionary.lookup(key)
        deleteRegion(beg, point)
        if let candidates, candidates.count > 1 {
            // mlh-recursive-edit-select: shown with the first candidate; the
            // caller lets the user cycle through them.
            let start = makeMarker(point, advances: true)
            insert(candidates[0])
            let end = makeMarker(point, advances: false)
            start.pos = beg
            selections.append((start, end, candidates))
        } else {
            insert(candidates?.first ?? "?udef?")
        }
        if henkanBegin == nil { henkanBegin = beg }
    }

    // mlh-kanji-with-henkan-region-function
    func mlhKanji(_ f: Frame) throws {
        skipCharsBackward(Self.romajiChar)
        try mlhBackwardHenkan()
        inhibitHenkan = false
        let beg = point
        f.mlhBeg = beg
        point = f.endMarker.pos
        forwardChar(-1)
        replaceRegion(beg, point, with: Romaji.toHiragana(substring(beg, point)))
        deleteRegion(point, f.endMarker.pos)
        if henkanBegin == nil { henkanBegin = beg }
    }

    // mlh-hiragana
    func mlhHiragana(_ f: Frame) throws {
        forwardChar(-1)
        skipCharsBackward(Self.romajiChar)
        try mlhBackwardHenkan()
        let beg = point
        f.mlhBeg = beg
        point = f.endMarker.pos
        forwardChar(-2)
        replaceRegion(beg, point, with: Romaji.toHiragana(substring(beg, point)))
        deleteRegion(point, f.endMarker.pos)
        henkanBegin = point
    }

    // mlh-hiragana-to-kanji
    func mlhHiraganaToKanji(_ f: Frame) throws {
        forwardChar(-1)
        skipCharsBackward(Self.hiraganaChar)
        let beg = try recurseAndDropScheme(f)
        inhibitHenkan = false
        if henkanBegin == nil { henkanBegin = beg }
    }

    // mlh-katakana
    func mlhKatakana(_ f: Frame) throws {
        forwardChar(-1)
        skipCharsBackward(Self.romajiChar)
        try mlhBackwardHenkan()
        let beg = point
        f.mlhBeg = beg
        point = f.endMarker.pos
        forwardChar(-2)
        replaceRegion(beg, point, with: TextTransform.katakana(Romaji.toHiragana(substring(beg, point))))
        deleteRegion(point, f.endMarker.pos)
        if henkanBegin == nil { henkanBegin = beg }
    }

    // mlh-zenkaku
    func mlhZenkaku(_ f: Frame) throws {
        forwardChar(-1)
        skipCharsBackward(Self.graphicExceptSlash)
        let beg = try recurseAndDropScheme(f)
        transformRegion(beg, point, TextTransform.zenkaku)
        if henkanBegin == nil { henkanBegin = beg }
    }

    // MARK: mlh-do-spacing

    /// Syntax class of an ASCII character in mlh-syntax-table (a copy of
    /// emacs-lisp-mode-syntax-table with a few changes).
    static func syntaxClass(_ c: Character) -> Character? {
        guard let v = c.asciiValue else { return nil }
        let ch = Character(UnicodeScalar(v))
        if ch.isLetter || ch.isNumber { return "w" }
        switch ch {
        case " ", "\t", "\u{0C}": return " "
        case "\n": return ">"
        case ";": return "<"
        case "!": return "."
        case "$", "%", "&", "`", "'", ",", "#": return "'"
        case "\"": return "\""
        case "\\": return "\\"
        case "(", "[", "{": return "("
        case ")", "]", "}": return ")"
        default: return v < 0x20 || v == 0x7F ? nil : "_"
        }
    }

    /// mlh-space-control. Only the ASCII/ASCII pairs can ever match: the
    /// Japanese entries expect a syntax class `e`, which doesn't exist.
    static let spaceControl: Set<String> = ["ww", "w_", "_w", "__", ".w", "._"]

    func mlhDoSpacing() {
        guard let pc = precedingChar, let fc = followingChar,
              let sp = Self.syntaxClass(pc), let sf = Self.syntaxClass(fc),
              Self.spaceControl.contains(String([sp, sf])) else { return }
        if let hb = henkanBegin, hb >= point { henkanBegin = hb + 1 }
        insert(" ")
    }
}
