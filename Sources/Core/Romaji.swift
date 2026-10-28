import Foundation

/// Romaji -> hiragana translation, the equivalent of egg's
/// `its-translate-region-internal` with the its-hira table.
public enum Romaji {
    static let table: [String: String] = {
        var t: [String: String] = [:]
        func add(_ prefix: String, _ kana: [String]) {
            for (v, k) in zip(["a", "i", "u", "e", "o"], kana) where !k.isEmpty {
                t[prefix + v] = k
            }
        }
        add("", ["あ", "い", "う", "え", "お"])
        add("k", ["か", "き", "く", "け", "こ"])
        add("s", ["さ", "し", "す", "せ", "そ"])
        add("t", ["た", "ち", "つ", "て", "と"])
        add("n", ["な", "に", "ぬ", "ね", "の"])
        add("h", ["は", "ひ", "ふ", "へ", "ほ"])
        add("m", ["ま", "み", "む", "め", "も"])
        add("y", ["や", "い", "ゆ", "いぇ", "よ"])
        add("r", ["ら", "り", "る", "れ", "ろ"])
        add("w", ["わ", "うぃ", "う", "うぇ", "を"])
        add("g", ["が", "ぎ", "ぐ", "げ", "ご"])
        add("z", ["ざ", "じ", "ず", "ぜ", "ぞ"])
        add("d", ["だ", "ぢ", "づ", "で", "ど"])
        add("b", ["ば", "び", "ぶ", "べ", "ぼ"])
        add("p", ["ぱ", "ぴ", "ぷ", "ぺ", "ぽ"])
        add("v", ["ゔぁ", "ゔぃ", "ゔ", "ゔぇ", "ゔぉ"])
        add("f", ["ふぁ", "ふぃ", "ふ", "ふぇ", "ふぉ"])
        add("j", ["じゃ", "じ", "じゅ", "じぇ", "じょ"])
        add("q", ["くぁ", "くぃ", "く", "くぇ", "くぉ"])
        add("l", ["ぁ", "ぃ", "ぅ", "ぇ", "ぉ"])
        add("x", ["ぁ", "ぃ", "ぅ", "ぇ", "ぉ"])
        // Palatalized (-ya, -yu, -yo, -ye).
        let youon: [(String, String)] = [
            ("ky", "き"), ("sy", "し"), ("ty", "ち"), ("cy", "ち"), ("ny", "に"),
            ("hy", "ひ"), ("my", "み"), ("ry", "り"), ("gy", "ぎ"), ("zy", "じ"),
            ("jy", "じ"), ("dy", "ぢ"), ("by", "び"), ("py", "ぴ"), ("fy", "ふ"),
            ("vy", "ゔ"),
        ]
        for (p, k) in youon {
            add(p, [k + "ゃ", k + "ぃ", k + "ゅ", k + "ぇ", k + "ょ"])
        }
        add("sh", ["しゃ", "し", "しゅ", "しぇ", "しょ"])
        add("ch", ["ちゃ", "ち", "ちゅ", "ちぇ", "ちょ"])
        add("ts", ["つぁ", "つぃ", "つ", "つぇ", "つぉ"])
        add("th", ["てゃ", "てぃ", "てゅ", "てぇ", "てょ"])
        add("dh", ["でゃ", "でぃ", "でゅ", "でぇ", "でょ"])
        add("tw", ["とぁ", "とぃ", "とぅ", "とぇ", "とぉ"])
        add("dw", ["どぁ", "どぃ", "どぅ", "どぇ", "どぉ"])
        add("wh", ["うぁ", "うぃ", "う", "うぇ", "うぉ"])
        add("xy", ["ゃ", "", "ゅ", "", "ょ"])
        add("ly", ["ゃ", "", "ゅ", "", "ょ"])
        t["ca"] = "か"; t["ci"] = "し"; t["cu"] = "く"; t["ce"] = "せ"; t["co"] = "こ"
        t["xtu"] = "っ"; t["xtsu"] = "っ"; t["ltu"] = "っ"; t["ltsu"] = "っ"
        t["xwa"] = "ゎ"; t["lwa"] = "ゎ"; t["xka"] = "ゕ"; t["xke"] = "ゖ"
        t["wyi"] = "ゐ"; t["wye"] = "ゑ"
        t["nn"] = "ん"; t["n'"] = "ん"; t["N"] = "ん"; t["xn"] = "ん"
        t["'"] = ""   // a lone apostrophe only separates syllables ("kann'i")
        t["-"] = "ー"; t[","] = "、"; t["."] = "。"; t["["] = "「"; t["]"] = "」"
        return t
    }()

    static let maxKeyLength = 4
    static let vowels: Set<Character> = ["a", "i", "u", "e", "o"]
    static let geminateConsonants: Set<Character> = Set("bcdfghjklmpqrstvwxyz")

    public static func toHiragana(_ input: String) -> String {
        let s = Array(input)
        var out = ""
        var i = 0
        while i < s.count {
            let c = s[i]
            // Doubled consonant -> small tsu ("tte" -> "って").
            if i + 1 < s.count, s[i + 1] == c, geminateConsonants.contains(c) {
                out += "っ"
                i += 1
                continue
            }
            // "nn" before a vowel or "y" is ん plus the next mora ("konnichiha").
            if c == "n", i + 2 < s.count, s[i + 1] == "n",
               vowels.contains(s[i + 2]) || s[i + 2] == "y" {
                out += "ん"
                i += 1
                continue
            }
            var matched = false
            for len in stride(from: min(maxKeyLength, s.count - i), through: 1, by: -1) {
                if let kana = table[String(s[i..<i + len])] {
                    out += kana
                    i += len
                    matched = true
                    break
                }
            }
            if matched { continue }
            // A lone "n" not followed by a vowel or "y" is ん.
            if c == "n" {
                let next = i + 1 < s.count ? s[i + 1] : nil
                if next == nil || !(vowels.contains(next!) || next == "y") {
                    out += "ん"
                    i += 1
                    continue
                }
            }
            out.append(c)
            i += 1
        }
        return out
    }
}
