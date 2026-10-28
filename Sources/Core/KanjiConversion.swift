import Foundation

/// One conversion unit (egg "bunsetsu").
public struct ConversionSegment: Equatable {
    public var reading: String
    public var candidates: [String]   // never empty
    public var index: Int

    public init(reading: String, candidates: [String], index: Int = 0) {
        self.reading = reading
        self.candidates = candidates.isEmpty ? [reading] : candidates
        self.index = max(0, min(index, self.candidates.count - 1))
    }

    public var current: String { candidates[index] }
}

/// Kana -> kanji conversion state, modelled after egg's conversion mode.
public final class KanjiConversion {
    public let source: String
    public private(set) var segments: [ConversionSegment]
    public private(set) var current: Int

    private let transliterator: Transliterator

    public init(source: String, transliterator: Transliterator) {
        self.source = source
        self.transliterator = transliterator
        self.current = 0
        self.segments = []
        self.segments = query(source, fixed: false)
    }

    // MARK: - Accessors

    public var text: String { segments.map { $0.current }.joined() }

    public var readingText: String { segments.map { $0.reading }.joined() }

    /// UTF-16 ranges of each segment's current candidate inside `text`.
    public func segmentRanges() -> [NSRange] {
        var location = 0
        return segments.map { seg in
            let length = seg.current.utf16.count
            defer { location += length }
            return NSRange(location: location, length: length)
        }
    }

    public var currentSegment: ConversionSegment { segments[current] }

    // MARK: - Candidate selection

    public func nextCandidate() {
        var seg = segments[current]
        seg.index = (seg.index + 1) % seg.candidates.count
        segments[current] = seg
    }

    public func previousCandidate() {
        var seg = segments[current]
        seg.index = (seg.index - 1 + seg.candidates.count) % seg.candidates.count
        segments[current] = seg
    }

    public func selectCandidate(_ index: Int) {
        guard segments[current].candidates.indices.contains(index) else { return }
        segments[current].index = index
    }

    // MARK: - Segment movement

    public func forwardSegment() { current = min(current + 1, segments.count - 1) }
    public func backwardSegment() { current = max(current - 1, 0) }
    public func firstSegment() { current = 0 }
    public func lastSegment() { current = segments.count - 1 }

    // MARK: - Segment resizing

    /// egg C-i: make the current segment one character shorter; the removed
    /// character is prepended to the following text which is re-segmented.
    public func shrinkSegment() {
        let reading = segments[current].reading
        guard reading.count > 1 else { return }
        let newReading = String(reading.dropLast())
        let rest = String(reading.last!) + following().map { $0.reading }.joined()
        resize(to: newReading, rest: rest)
    }

    /// egg C-o: make the current segment one character longer, taking the
    /// character from the start of the following text.
    public func enlargeSegment() {
        let followingReading = following().map { $0.reading }.joined()
        guard let first = followingReading.first else { return }
        let newReading = reading(of: current) + String(first)
        let rest = String(followingReading.dropFirst())
        resize(to: newReading, rest: rest)
    }

    // MARK: - Private

    private func reading(of i: Int) -> String { segments[i].reading }

    private func following() -> ArraySlice<ConversionSegment> {
        segments[(current + 1)...]
    }

    private func resize(to newReading: String, rest: String) {
        let head = query(newReading, fixed: true)[0]
        let tail = rest.isEmpty ? [] : query(rest, fixed: false)
        segments = Array(segments[..<current]) + [head] + tail
    }

    /// Converts `reading`. When `fixed`, the reading is forced to be a single
    /// segment (by appending the "," boundary marker) and only the first
    /// returned segment is used. Falls back to a plain kana segment when the
    /// transliterator fails or returns readings that don't match.
    private func query(_ reading: String, fixed: Bool) -> [ConversionSegment] {
        let fallback = [Self.makeSegment(reading: reading, candidates: [])]
        guard let result = transliterator.convert(fixed ? reading + "," : reading),
              !result.isEmpty else { return fallback }
        let used = fixed ? Array(result.prefix(1)) : result
        guard used.map({ $0.reading }).joined() == reading,
              !used.contains(where: { $0.reading.isEmpty }) else { return fallback }
        return used.map { Self.makeSegment(reading: $0.reading, candidates: $0.candidates) }
    }

    /// Builds a segment whose candidates are deduplicated and always include
    /// the reading itself and its katakana form.
    private static func makeSegment(reading: String, candidates: [String]) -> ConversionSegment {
        var seen = Set<String>()
        var list: [String] = []
        for c in candidates + [reading, TextTransform.katakana(reading)] where !c.isEmpty {
            if seen.insert(c).inserted { list.append(c) }
        }
        return ConversionSegment(reading: reading, candidates: list, index: 0)
    }
}
