import Foundation
import KanaKanjiConverterModule

/// Transliterator backed by AzooKeyKanaKanjiConverter, converting locally
/// (no network) with the azooKey dictionary.
///
/// Segments follow azooKey's clause rule (`DicdataStore.isClause`): a clause
/// starts at each content word or prefix that does not follow a prefix, so
/// particles and auxiliaries stay with the word before them, as in egg.
public final class AzooKeyTransliterator: Transliterator {
    private let converter: KanaKanjiConverter
    private let options: ConvertRequestOptions
    /// KanaKanjiConverter is not thread-safe.
    private let lock = NSLock()

    /// `dictionaryURL` is the azooKey "Dictionary" directory.
    public init(dictionaryURL: URL) {
        converter = KanaKanjiConverter(dicdataStore: DicdataStore(dictionaryURL: dictionaryURL))
        let tmp = FileManager.default.temporaryDirectory
        options = ConvertRequestOptions(
            requireJapanesePrediction: false, requireEnglishPrediction: false,
            keyboardLanguage: .ja_JP, learningType: .nothing,
            memoryDirectoryURL: tmp, sharedContainerURL: tmp,
            textReplacer: .empty, specialCandidateProviders: nil, metadata: nil)
    }

    /// The dictionary bundled in the input method (Contents/Resources/Dictionary).
    public static var bundledDictionaryURL: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Dictionary", isDirectory: true),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("louds").path) else { return nil }
        return url
    }

    public func convert(_ text: String) -> [(reading: String, candidates: [String])]? {
        if text.isEmpty { return nil }
        lock.lock(); defer { lock.unlock() }
        if text.contains(",") {
            let chunks = text.split(separator: ",").map(String.init)
            return chunks.isEmpty ? nil : chunks.map { ($0, wholeCandidates($0)) }
        }
        return segments(text)
    }

    // MARK: - Private

    private func request(_ reading: String) -> [Candidate] {
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        let result = converter.requestCandidates(composing, options: options)
        converter.stopComposition()
        return result.mainResults
    }

    /// Candidates converting all of `reading`, best first.
    private func wholeCandidates(_ reading: String) -> [String] {
        var seen = Set<String>()
        return request(reading).filter { $0.rubyCount == reading.count && seen.insert($0.text).inserted }
            .map { $0.text }
    }

    /// Splits the best conversion of `text` into clauses.
    private func segments(_ text: String) -> [(reading: String, candidates: [String])]? {
        guard let best = request(text).first(where: { $0.rubyCount == text.count }) else { return nil }
        var clauses: [(count: Int, word: String)] = []
        var previous: DicdataElement?
        for d in best.data {
            if let p = previous, !Self.isClause(p.rcid, d.lcid) {
                clauses[clauses.count - 1].count += d.ruby.count
                clauses[clauses.count - 1].word += d.word
            } else {
                clauses.append((d.ruby.count, d.word))
            }
            previous = d
        }
        var rest = Substring(text)
        var result: [(reading: String, candidates: [String])] = []
        for clause in clauses {
            let reading = String(rest.prefix(clause.count))
            rest = rest.dropFirst(clause.count)
            var candidates = [clause.word]
            for c in wholeCandidates(reading) where c != clause.word { candidates.append(c) }
            result.append((reading, candidates))
        }
        return result
    }

    /// `DicdataStore.isClause`, which is not public.
    static func isClause(_ former: Int, _ latter: Int) -> Bool {
        let types = DicdataStore.wordTypes
        guard types.indices.contains(former), types.indices.contains(latter) else { return true }
        let l = types[latter], f = types[former]
        if l == 3 || f == 3 { return false }
        return (l == 0 || l == 1) && f != 0
    }
}
