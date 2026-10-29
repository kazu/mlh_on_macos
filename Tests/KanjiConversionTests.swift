import Foundation
@testable import MLHCore

/// Deterministic transliterator for tests. Responses are looked up by the exact
/// query string; unknown queries are answered by splitting on "," (one segment
/// per chunk) with a fake kanji candidate "<chunk>漢".
private final class KCFakeTransliterator: Transliterator {
    var responses: [String: [(reading: String, candidates: [String])]] = [:]
    var failAll = false
    private(set) var queries: [String] = []

    func convert(_ text: String) -> [(reading: String, candidates: [String])]? {
        queries.append(text)
        if failAll { return nil }
        if let r = responses[text] { return r }
        let chunks = text.split(separator: ",").map(String.init)
        if chunks.isEmpty { return nil }
        return chunks.map { (reading: $0, candidates: [$0 + "漢"]) }
    }
}

func runKanjiConversionTests() -> (passed: Int, failed: Int) {
    var passed = 0
    var failed = 0

    func check(_ cond: @autoclosure () -> Bool, _ name: String,
               file: String = #fileID, line: Int = #line) {
        if cond() {
            passed += 1
        } else {
            failed += 1
            print("FAIL [KanjiConversion] \(name) (\(file):\(line))")
        }
    }

    func eq<T: Equatable>(_ a: T, _ b: T, _ name: String,
                          file: String = #fileID, line: Int = #line) {
        if a == b {
            passed += 1
        } else {
            failed += 1
            print("FAIL [KanjiConversion] \(name): got \(a), expected \(b) (\(file):\(line))")
        }
    }

    func makeFake() -> KCFakeTransliterator {
        let f = KCFakeTransliterator()
        f.responses["ここではきものをぬぐ"] = [
            (reading: "ここでは", candidates: ["ここでは", "個々では", "此処では"]),
            (reading: "きものを", candidates: ["着物を", "きものを", "着物を"]),
            (reading: "ぬぐ", candidates: ["脱ぐ", "ぬぐ"]),
        ]
        f.responses["ここではき,"] = [
            (reading: "ここではき", candidates: ["ここでは気", "ここではき"]),
        ]
        f.responses["ものをぬぐ"] = [
            (reading: "ものを", candidates: ["物を", "ものを"]),
            (reading: "ぬぐ", candidates: ["脱ぐ", "ぬぐ"]),
        ]
        f.responses["ここで,"] = [(reading: "ここで", candidates: ["此処で", "ここで"])]
        f.responses["はきものをぬぐ"] = [
            (reading: "はきものを", candidates: ["履物を"]),
            (reading: "ぬぐ", candidates: ["脱ぐ"]),
        ]
        return f
    }

    // --- Initial conversion -------------------------------------------------
    do {
        let f = makeFake()
        let kc = KanjiConversion(source: "ここではきものをぬぐ", transliterator: f)
        eq(f.queries, ["ここではきものをぬぐ"], "init query")
        eq(kc.segments.count, 3, "init segment count")
        eq(kc.current, 0, "init current")
        eq(kc.text, "ここでは着物を脱ぐ", "init text")
        eq(kc.readingText, "ここではきものをぬぐ", "init readingText")
        eq(kc.source, "ここではきものをぬぐ", "source")
        // Katakana appended, duplicates removed.
        eq(kc.segments[0].candidates, ["ここでは", "個々では", "此処では", "ココデハ"], "seg0 candidates")
        eq(kc.segments[1].candidates, ["着物を", "きものを", "キモノヲ"], "seg1 candidates dedup")
        eq(kc.segments.map { $0.index }, [0, 0, 0], "indexes start at 0")
        eq(kc.segmentRanges(), [NSRange(location: 0, length: 4),
                                NSRange(location: 4, length: 3),
                                NSRange(location: 7, length: 2)], "segmentRanges")
    }

    // --- Candidate cycling --------------------------------------------------
    do {
        let kc = KanjiConversion(source: "ここではきものをぬぐ", transliterator: makeFake())
        kc.nextCandidate()
        eq(kc.currentSegment.current, "個々では", "next 1")
        kc.nextCandidate(); kc.nextCandidate()
        eq(kc.currentSegment.current, "ココデハ", "next 3")
        kc.nextCandidate()
        eq(kc.currentSegment.index, 0, "next wraps")
        kc.previousCandidate()
        eq(kc.currentSegment.current, "ココデハ", "previous wraps")
        kc.selectCandidate(2)
        eq(kc.currentSegment.current, "此処では", "select 2")
        kc.selectCandidate(99)
        eq(kc.currentSegment.index, 2, "select out of range ignored")
        kc.selectCandidate(-1)
        eq(kc.currentSegment.index, 2, "select negative ignored")
        eq(kc.text, "此処では着物を脱ぐ", "text after select")
        eq(kc.segments[1].index, 0, "other segments untouched")
    }

    // --- Segment movement ---------------------------------------------------
    do {
        let kc = KanjiConversion(source: "ここではきものをぬぐ", transliterator: makeFake())
        kc.backwardSegment()
        eq(kc.current, 0, "backward clamps")
        kc.forwardSegment()
        eq(kc.current, 1, "forward")
        kc.nextCandidate()
        eq(kc.text, "ここではきものを脱ぐ", "next on seg1")
        kc.forwardSegment(); kc.forwardSegment()
        eq(kc.current, 2, "forward clamps")
        kc.firstSegment()
        eq(kc.current, 0, "first")
        kc.lastSegment()
        eq(kc.current, 2, "last")
    }

    // --- Shrink ---------------------------------------------------------------
    do {
        let f = makeFake()
        let kc = KanjiConversion(source: "ここではきものをぬぐ", transliterator: f)
        kc.forwardSegment()                // focus "きものを"
        kc.backwardSegment()               // back to "ここでは"
        kc.nextCandidate()                 // choose 個々では (will be replaced)
        // Enlarge segment 0: "ここでは" + "き"
        kc.enlargeSegment()
        eq(Array(f.queries.dropFirst()), ["ここではき,", "ものをぬぐ"], "enlarge queries")
        eq(kc.segments.map { $0.reading }, ["ここではき", "ものを", "ぬぐ"], "enlarge readings")
        eq(kc.current, 0, "enlarge keeps current")
        eq(kc.text, "ここでは気物を脱ぐ", "enlarge text")
        eq(kc.readingText, kc.source, "enlarge readingText == source")
        check(kc.segments[0].candidates.contains("ココデハキ"), "enlarge seg has katakana")

        // Shrink twice from "ここではき" -> "ここでは" -> "ここで"
        kc.shrinkSegment()
        eq(f.queries.last, "きものをぬぐ", "shrink rest query (natural)")
        eq(f.queries[f.queries.count - 2], "ここでは,", "shrink head query")
        eq(kc.segments.map { $0.reading }, ["ここでは", "きものをぬぐ"], "shrink readings (fake fallback split)")
        kc.shrinkSegment()
        eq(Array(f.queries.suffix(2)), ["ここで,", "はきものをぬぐ"], "shrink 2 queries")
        eq(kc.segments.map { $0.reading }, ["ここで", "はきものを", "ぬぐ"], "shrink 2 readings")
        eq(kc.text, "此処で履物を脱ぐ", "shrink 2 text")
        eq(kc.current, 0, "shrink keeps current")
    }

    // --- Shrink/enlarge keep previous segments and their choice ---------------
    do {
        let f = makeFake()
        let kc = KanjiConversion(source: "ここではきものをぬぐ", transliterator: f)
        kc.nextCandidate()                 // 個々では
        kc.forwardSegment()                // "きものを"
        f.responses["きもの,"] = [(reading: "きもの", candidates: ["着物"])]
        f.responses["をぬぐ"] = [(reading: "をぬぐ", candidates: ["を脱ぐ"])]
        kc.shrinkSegment()
        eq(Array(f.queries.suffix(2)), ["きもの,", "をぬぐ"], "shrink mid queries")
        eq(kc.segments.map { $0.reading }, ["ここでは", "きもの", "をぬぐ"], "shrink mid readings")
        eq(kc.segments[0].index, 1, "previous segment choice kept")
        eq(kc.current, 1, "current at resized segment")
        eq(kc.text, "個々では着物を脱ぐ", "shrink mid text")

        // Enlarge the last segment: no-op.
        kc.lastSegment()
        let before = f.queries.count
        kc.enlargeSegment()
        eq(f.queries.count, before, "enlarge last is no-op")
        eq(kc.segments.count, 3, "enlarge last keeps segments")

        // Enlarge into the final segment until it disappears.
        kc.firstSegment(); kc.forwardSegment()  // "きもの"
        f.responses["きものを,"] = [(reading: "きものを", candidates: ["着物を"])]
        kc.enlargeSegment()
        eq(Array(f.queries.suffix(2)), ["きものを,", "ぬぐ"], "enlarge mid queries")
        f.responses["きものをぬぐ,"] = [(reading: "きものをぬぐ", candidates: ["着物を脱ぐ"])]
        kc.enlargeSegment(); kc.enlargeSegment()
        eq(f.queries.last, "きものをぬぐ,", "enlarge to end: no rest query when rest empty")
        eq(kc.segments.map { $0.reading }, ["ここでは", "きものをぬぐ"], "enlarge to end readings")
        eq(kc.current, 1, "enlarge to end current")
        eq(kc.text, "個々では着物を脱ぐ", "enlarge to end text")

        // Shrink a single-character segment: no-op.
        let one = KanjiConversion(source: "き", transliterator: makeFake())
        let n = one.segments.count
        one.shrinkSegment()
        eq(one.segments.count, n, "shrink single char no-op")
        eq(one.readingText, "き", "shrink single char reading")
    }

    // --- Fallback -------------------------------------------------------------
    do {
        let f = KCFakeTransliterator()
        f.failAll = true
        let kc = KanjiConversion(source: "かな", transliterator: f)
        eq(kc.segments.count, 1, "fallback single segment")
        eq(kc.segments[0].candidates, ["かな", "カナ"], "fallback candidates")
        eq(kc.text, "かな", "fallback text")
        kc.shrinkSegment()
        eq(kc.segments.map { $0.reading }, ["か", "な"], "fallback shrink readings")
        eq(kc.segments[1].candidates, ["な", "ナ"], "fallback shrink rest candidates")
        eq(kc.readingText, "かな", "fallback readingText")

        // Mismatched readings => fallback.
        let g = KCFakeTransliterator()
        g.responses["あいう"] = [(reading: "あい", candidates: ["愛"])]
        let kc2 = KanjiConversion(source: "あいう", transliterator: g)
        eq(kc2.segments.map { $0.reading }, ["あいう"], "mismatch fallback")
        eq(kc2.segments[0].candidates, ["あいう", "アイウ"], "mismatch fallback candidates")

        // Empty result => fallback. Katakana-only / ASCII source dedups.
        let h = KCFakeTransliterator()
        h.responses["abc"] = []
        let kc3 = KanjiConversion(source: "abc", transliterator: h)
        eq(kc3.segments[0].candidates, ["abc"], "empty result fallback, ascii dedup")
    }

    // --- segmentRanges with surrogate pairs -------------------------------------
    do {
        let f = KCFakeTransliterator()
        f.responses["よしのやで"] = [
            (reading: "よしのや", candidates: ["𠮷野家"]),
            (reading: "で", candidates: ["で"]),
        ]
        let kc = KanjiConversion(source: "よしのやで", transliterator: f)
        eq(kc.text, "𠮷野家で", "surrogate text")
        eq(kc.segmentRanges(), [NSRange(location: 0, length: 4),
                                NSRange(location: 4, length: 1)], "surrogate ranges")
        let ns = kc.text as NSString
        eq(ns.substring(with: kc.segmentRanges()[0]), "𠮷野家", "surrogate substring 0")
        eq(ns.substring(with: kc.segmentRanges()[1]), "で", "surrogate substring 1")
    }

    // --- Google transliterator: URL building and parsing (offline) ---------------
    do {
        let url = GoogleTransliterator.makeURL("ここ,で+a")
        let s = url?.absoluteString ?? ""
        check(s.hasPrefix("https://www.google.com/transliterate?"), "url prefix")
        check(s.contains("langpair=ja-Hira%7Cja"), "url encodes |")
        check(s.contains("%2C") && s.contains("%2B"), "url encodes , and +")
        check(!s.contains("こ"), "url encodes kana")

        let json = #"[["ここでは",["ここでは","個々では","ここでは"]],["ぬぐ",["脱ぐ"]]]"#
        let parsed = GoogleTransliterator.parse(Data(json.utf8))
        eq(parsed?.count, 2, "parse count")
        eq(parsed?[0].candidates ?? [], ["ここでは", "個々では"], "parse dedup")
        check(GoogleTransliterator.parse(Data("[]".utf8)) == nil, "parse empty => nil")
        check(GoogleTransliterator.parse(Data("garbage".utf8)) == nil, "parse garbage => nil")
        check(GoogleTransliterator.parse(Data(#"[[1,2]]"#.utf8)) == nil, "parse bad shape => nil")
    }

    // --- Live network test (optional) -------------------------------------------
    if ProcessInfo.processInfo.environment["MLH_SKIP_NETWORK"] != nil {
        print("NOTE [KanjiConversion] live Google test skipped (MLH_SKIP_NETWORK set)")
        passed += 1
    } else {
        let g = GoogleTransliterator(timeout: 5)
        if let r = g.convert("ここではきものをぬぐ") {
            eq(r.map { $0.reading }.joined(), "ここではきものをぬぐ", "live readings")
            check(r.contains { $0.candidates.contains("脱ぐ") }, "live has 脱ぐ")
            if let fixed = g.convert("ここではき,ものをぬぐ") {
                eq(fixed.map { $0.reading }, ["ここではき", "ものをぬぐ"], "live comma boundary")
            } else {
                print("NOTE [KanjiConversion] live comma request failed; skipped")
                passed += 1
            }
            let kc = KanjiConversion(source: "にほんごにゅうりょく", transliterator: g)
            eq(kc.readingText, "にほんごにゅうりょく", "live KanjiConversion reading")
            kc.shrinkSegment()
            eq(kc.readingText, "にほんごにゅうりょく", "live shrink reading preserved")
        } else {
            print("NOTE [KanjiConversion] live Google request failed; test skipped")
            passed += 1
        }
    }

    // --- azooKey (local) ---------------------------------------------------------
    // The dictionary comes with the AzooKeyKanaKanjiConverter checkout; set
    // MLH_AZOOKEY_DICTIONARY to use another one.
    let dictionary = ProcessInfo.processInfo.environment["MLH_AZOOKEY_DICTIONARY"]
        ?? ".build/checkouts/AzooKeyKanaKanjiConverter/Sources/KanaKanjiConverterModuleWithDefaultDictionary/azooKey_dictionary_storage/Dictionary"
    if !FileManager.default.fileExists(atPath: dictionary + "/louds") {
        print("NOTE [KanjiConversion] azooKey dictionary not found at \(dictionary); test skipped")
        passed += 1
    } else {
        let a = AzooKeyTransliterator(dictionaryURL: URL(fileURLWithPath: dictionary, isDirectory: true))
        let r = a.convert("ここではきものをぬいでください")
        eq(r?.map { $0.reading } ?? [], ["ここでは", "きものを", "ぬいでください"], "azooKey segments")
        eq(r?.map { $0.candidates.first ?? "" } ?? [], ["ここでは", "着物を", "脱いでください"], "azooKey best")
        check(r?[0].candidates.contains("個々では") == true, "azooKey candidates")
        let fixed = a.convert("ここではき,ものを")
        eq(fixed?.map { $0.reading } ?? [], ["ここではき", "ものを"], "azooKey comma boundary")
        eq(a.convert("きもの,")?.count, 1, "azooKey fixed segment")
        check(a.convert("") == nil, "azooKey empty => nil")
        let kc = KanjiConversion(source: "にほんごにゅうりょく", transliterator: a)
        eq(kc.text, "日本語入力", "azooKey KanjiConversion")
        kc.shrinkSegment()
        eq(kc.readingText, "にほんごにゅうりょく", "azooKey shrink reading preserved")
        check(kc.segments.count >= 2, "azooKey shrink splits")
    }

    return (passed, failed)
}
