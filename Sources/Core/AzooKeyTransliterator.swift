import Foundation
import KanaKanjiConverterModule

/// Transliterator backed by AzooKeyKanaKanjiConverter, converting locally
/// (no network) with the azooKey dictionary, and with its neural model (zenz)
/// when one is given: zenz also reads the text before the conversion.
///
/// Segments follow azooKey's clause rule (`DicdataStore.isClause`): a clause
/// starts at each content word or prefix that does not follow a prefix, so
/// particles and auxiliaries stay with the word before them, as in egg.
public final class AzooKeyTransliterator: Transliterator {
    private let converter: KanaKanjiConverter
    private let options: ConvertRequestOptions
    private let zenzaiWeightURL: URL?
    private let contextLength: Int
    private let inferenceLimit: Int
    /// KanaKanjiConverter is not thread-safe.
    private let lock = NSLock()

    /// `dictionaryURL` is the azooKey "Dictionary" directory; `zenzaiWeightURL`
    /// a zenz model (gguf), used only when azooKey is built with Zenzai. zenz
    /// reads the last `contextLength` characters before the conversion, and
    /// re-evaluates candidates at most `inferenceLimit` times per request.
    public init(dictionaryURL: URL, zenzaiWeightURL: URL? = nil, contextLength: Int = 40, inferenceLimit: Int = 10) {
        self.zenzaiWeightURL = zenzaiWeightURL
        self.contextLength = contextLength
        self.inferenceLimit = inferenceLimit
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
        convert(text, context: nil)
    }

    public func convert(_ text: String, context: String?) -> [(reading: String, candidates: [String])]? {
        if text.isEmpty { return nil }
        lock.lock(); defer { lock.unlock() }
        let context = context ?? ""
        if text.contains(",") {
            var result: [(reading: String, candidates: [String])] = []
            var before = context
            for chunk in text.split(separator: ",").map(String.init) {
                let candidates = wholeCandidates(chunk, context: before, zenz: true)
                result.append((chunk, candidates))
                before += candidates.first ?? chunk
            }
            return result.isEmpty ? nil : result
        }
        return segments(text, context: context)
    }

    // MARK: - Private

    /// Converts `reading`; with `zenz`, the zenz model (if any) re-ranks the
    /// candidates using `context`. Each zenz request runs the model, so it is
    /// used only for the best conversion, not for the alternatives.
    private func request(_ reading: String, context: String, zenz: Bool) -> [Candidate] {
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        var options = self.options
        if zenz, let zenzaiWeightURL {
            let context = contextLength > 0 && !context.isEmpty ? context : nil
            options.zenzaiMode = .on(weight: zenzaiWeightURL, inferenceLimit: inferenceLimit, personalizationMode: nil,
                                     versionDependentMode: .v3(.init(leftSideContext: context,
                                                                     maxLeftSideContextLength: contextLength)))
        }
        let result = converter.requestCandidates(composing, options: options)
        converter.stopComposition()
        return result.mainResults
    }

    /// Candidates converting all of `reading`, best first.
    private func wholeCandidates(_ reading: String, context: String, zenz: Bool) -> [String] {
        var seen = Set<String>()
        return request(reading, context: context, zenz: zenz).filter { $0.rubyCount == reading.count && seen.insert($0.text).inserted }
            .map { $0.text }
    }

    /// Splits the best conversion of `text` into clauses.
    private func segments(_ text: String, context: String) -> [(reading: String, candidates: [String])]? {
        guard let best = request(text, context: context, zenz: true).first(where: { $0.rubyCount == text.count }) else { return nil }
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
        var before = context
        var result: [(reading: String, candidates: [String])] = []
        for clause in clauses {
            let reading = String(rest.prefix(clause.count))
            rest = rest.dropFirst(clause.count)
            var candidates = [clause.word]
            for c in wholeCandidates(reading, context: before, zenz: false) where c != clause.word { candidates.append(c) }
            result.append((reading, candidates))
            before += clause.word
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
