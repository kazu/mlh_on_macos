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

    /// The JIS X 0208 character whose code is the 4-digit hex string (mlh `j`).
    public static func jisCharacter(hex: String) -> String? {
        guard hex.count == 4, let code = UInt16(hex, radix: 16) else { return nil }
        let hi = UInt8(code >> 8), lo = UInt8(code & 0xFF)
        guard (0x21...0x7E).contains(hi), (0x21...0x7E).contains(lo) else { return nil }
        return String(data: Data([hi | 0x80, lo | 0x80]), encoding: .japaneseEUC)
    }
}
