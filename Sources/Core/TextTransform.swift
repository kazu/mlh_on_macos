import Foundation

/// Region transforms used by the mlh conversion schemes.
public enum TextTransform {
    /// `japanese-katakana-region`: hiragana -> katakana.
    public static func katakana(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.map { u in
            (0x3041...0x3096).contains(u.value) ? Unicode.Scalar(u.value + 0x60)! : u
        }))
    }

    /// `japanese-zenkaku-region`: printable ASCII -> full-width forms.
    public static func zenkaku(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.map { u in
            switch u.value {
            case 0x21...0x7E: return Unicode.Scalar(u.value + 0xFEE0)!
            case 0x20: return Unicode.Scalar(0x3000)!
            default: return u
            }
        }))
    }

    /// `upcase-region`.
    public static func upcase(_ s: String) -> String { s.uppercased() }

    /// `capitalize-region`: the first letter of each word upper case, the rest lower case.
    public static func capitalize(_ s: String) -> String {
        var out = ""
        var inWord = false
        for c in s {
            let isWord = c.isLetter || c.isNumber
            if isWord {
                out += inWord ? c.lowercased() : c.uppercased()
            } else {
                out.append(c)
            }
            inWord = isWord
        }
        return out
    }

    /// Latin-1 letters typed in postfix notation (mlh `l`), after Emacs'
    /// latin-1-postfix: a` à, e' é, o^ ô, n~ ñ, u" ü, c, ç, and `*` in place
    /// of latin-1-postfix's `/` (which separates mlh words): a* å, e* æ,
    /// o* ø, d* ð, t* þ, s* ß. Also << «, >> », !* ¡, ?* ¿. Doubling the
    /// mark keeps it literal (e'' -> e').
    public static func latin1Postfix(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        var i = 0
        while i < chars.count {
            if i + 1 < chars.count, let ch = latin1Table[String(chars[i...i + 1])] {
                if i + 2 < chars.count, chars[i + 2] == chars[i + 1] {
                    out.append(chars[i])
                    out.append(chars[i + 1])
                    i += 3
                } else {
                    out += ch
                    i += 2
                }
            } else {
                out.append(chars[i])
                i += 1
            }
        }
        return out
    }

    private static let latin1Table: [String: String] = {
        var t: [String: String] = [
            "a*": "å", "A*": "Å", "e*": "æ", "E*": "Æ", "o*": "ø", "O*": "Ø",
            "d*": "ð", "D*": "Ð", "t*": "þ", "T*": "Þ", "s*": "ß",
            "<<": "«", ">>": "»", "!*": "¡", "?*": "¿",
        ]
        // Base letter + combining mark, kept only when it composes to Latin-1.
        let marks: [Character: UInt32] = ["`": 0x300, "'": 0x301, "^": 0x302, "~": 0x303, "\"": 0x308, ",": 0x327]
        for base in "aeiouyncAEIOUYNC" {
            for (mark, combining) in marks {
                let composed = (String(base) + String(UnicodeScalar(combining)!)).precomposedStringWithCanonicalMapping
                if composed.unicodeScalars.count == 1, composed.unicodeScalars.first!.value <= 0xFF {
                    t[String(base) + String(mark)] = composed
                }
            }
        }
        return t
    }()

    /// The JIS X 0208 character whose code is the 4-digit hex string (mlh `j`).
    public static func jisCharacter(hex: String) -> String? {
        guard hex.count == 4, let code = UInt16(hex, radix: 16) else { return nil }
        let hi = UInt8(code >> 8), lo = UInt8(code & 0xFF)
        guard (0x21...0x7E).contains(hi), (0x21...0x7E).contains(lo) else { return nil }
        return String(data: Data([hi | 0x80, lo | 0x80]), encoding: .japaneseEUC)
    }
}
