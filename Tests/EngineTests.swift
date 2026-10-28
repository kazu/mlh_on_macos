import Foundation

private var passed = 0
private var failed = 0

private func check<T: Equatable>(_ name: String, _ got: T, _ want: T) {
    if got == want {
        passed += 1
    } else {
        failed += 1
        print("FAIL \(name)\n  got:  \(got)\n  want: \(want)")
    }
}

private func edit(_ text: String, _ hb: Int, convert: Bool,
                  _ selections: [MLHSelection] = []) -> MLHResult {
    .edit(MLHOutcome(text: text, selections: selections, henkanBegin: hb, convertToKanji: convert))
}

func runEngineTests() -> (passed: Int, failed: Int) {
    passed = 0
    failed = 0

    // Romaji (its-hira).
    let romaji: [(String, String)] = [
        ("nihongo", "にほんご"), ("kanji", "かんじ"), ("shinbun", "しんぶん"),
        ("kitte", "きって"), ("konnichiha", "こんにちは"), ("konnnichiha", "こんにちは"),
        ("kanna", "かんな"), ("n'a", "んあ"), ("kann'i", "かんい"), ("tyotto", "ちょっと"), ("hoNtou", "ほんとう"),
        ("xtu", "っ"), ("[kagi]", "「かぎ」"), ("ra-men", "らーめん"), ("desu.", "です。"),
        ("kyou", "きょう"), ("fairu", "ふぁいる"), ("dhi", "でぃ"), ("vu", "ゔ"),
    ]
    for (r, k) in romaji { check("romaji \(r)", Romaji.toHiragana(r), k) }

    // Transforms.
    check("katakana", TextTransform.katakana("にほんごゔ"), "ニホンゴヴ")
    check("zenkaku", TextTransform.zenkaku("abc 1!"), "ａｂｃ　１！")
    check("capitalize", TextTransform.capitalize("hELLO wORLD"), "Hello World")
    check("jis", TextTransform.jisCharacter(hex: "2422"), "あ")
    check("jis kanji", TextTransform.jisCharacter(hex: "3441"), "漢")

    let engine = MLHEngine()
    let cases: [(String, MLHResult)] = [
        // Kanji: the last romaji letter (a vowel or n) is the scheme char.
        ("nihongo/", edit("にほんご", 0, convert: true)),
        ("watashiha nihongo/", edit("watashiha にほんご", 10, convert: true)),
        ("kyouhaiitenkidesu./", edit("きょうはいいてんきです。", 0, convert: true)),
        ("hon/", edit("ほん", 0, convert: true)),
        // Katakana / hiragana.
        ("nihongok/", edit("ニホンゴ", 0, convert: false)),
        ("nihongof/", edit("にほんご", 4, convert: false)),
        // Chains: every word separated by "/" is converted in one go.
        ("nihongok/desu/", edit("ニホンゴです", 0, convert: true)),
        ("nihongof/desu/", edit("にほんごです", 4, convert: true)),
        ("Linuxs/nokaihatsu/", edit("Linuxのかいはつ", 0, convert: true)),
        // Latin schemes, with mlh-do-spacing between ASCII words.
        ("Hellos/", edit("Hello", 0, convert: false)),
        ("foos/bars/", edit("foo bar", 0, convert: false)),
        ("thisc/isp/", edit("This IS", 0, convert: false)),
        ("hello worldc/", edit("hello World", 6, convert: false)),
        ("abcZ/", edit("ａｂｃ", 0, convert: false)),
        ("3w/", edit("   ", 0, convert: false)),
        ("w/", edit(" ", 0, convert: false)),
        ("2W/", edit("　　", 0, convert: false)),
        ("2422j/", edit("あ", 0, convert: false)),
        ("242j/", .failure("invalid length")),
        // Quit / exit stop going backward.
        ("fooq/", edit("foo", 3, convert: false)),
        ("fooX/", edit("foo ", 4, convert: false)),
        ("nihongo/fooq/", edit("nihongo/foo", 11, convert: false)),
        ("にほんごH/", edit("にほんご", 0, convert: true)),
        ("fooxs/", edit("foox", 0, convert: false)),
        // Nothing to do: the space is inserted.
        ("foo", .passThrough), ("/", .passThrough), ("foog/", .passThrough),
        ("fooL/", .passThrough), ("", .passThrough),
    ]
    for (input, want) in cases { check("run \(input)", engine.run(input), want) }

    // User-defined table (d).
    let dict = UserDictionary.parse("# comment\nmlh\tModeless\nime\tIME\t入力\n")
    let udEngine = MLHEngine(userDictionary: dict)
    check("userdef single", udEngine.run("mlhd/"), edit("Modeless", 0, convert: false))
    check("userdef missing", udEngine.run("zzzd/"), edit("?udef?", 0, convert: false))
    let sel = MLHSelection(range: 0..<3, candidates: ["IME", "入力"])
    check("userdef multi", udEngine.run("imed/"), edit("IME", 0, convert: false, [sel]))
    if case let .edit(o) = udEngine.run("imed/nihongo/") {
        check("userdef+kanji", o, MLHOutcome(text: "IMEにほんご", selections: [sel],
                                              henkanBegin: 0, convertToKanji: true))
        check("render choice", o.render(choices: [1]).text, "入力にほんご")
    } else {
        check("userdef+kanji", "not edit", "edit")
    }
    if case let .edit(o) = udEngine.run("nihongo/imed/") {
        check("kanji+userdef sel", o.selections, [MLHSelection(range: 4..<7, candidates: ["IME", "入力"])])
        check("kanji+userdef render", o.render(choices: [1]).text, "にほんご入力")
        check("kanji+userdef convert", o.convertToKanji, true)
    } else {
        check("kanji+userdef", "not edit", "edit")
    }
    // henkan-begin after a selection moves with the chosen candidate.
    let sel2 = MLHOutcome(text: "IMEです", selections: [sel], henkanBegin: 3, convertToKanji: true)
    check("render shifts henkan-begin", sel2.render(choices: [1]).henkanBegin, 2)

    return (passed, failed)
}
