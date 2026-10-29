import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Converts a kana reading into kanji candidates, segment by segment.
public protocol Transliterator {
    /// Synchronous. `text` may contain "," as fixed segment boundaries.
    /// Returns nil on failure (network error, timeout, bad JSON).
    func convert(_ text: String) -> [(reading: String, candidates: [String])]?
}

/// Transliterator backed by Google's CGI API for Japanese input:
/// `GET https://www.google.com/transliterate?langpair=ja-Hira|ja&text=...`
///
/// The response is JSON of the form
/// `[["ここでは",["ここでは","個々では",...]],["きものを",["着物を",...]],...]`.
///
/// A half-width ASCII "," in `text` is a segment boundary marker: every
/// comma-separated chunk comes back as exactly one segment (and the comma itself
/// does not appear in the returned readings). Without commas Google segments the
/// text naturally. Callers must therefore not pass literal ASCII commas that are
/// meant to be part of the reading.
public final class GoogleTransliterator: Transliterator {
    private let timeout: TimeInterval
    private let session: URLSession
    private static let endpoint = "https://www.google.com/transliterate"

    public init(timeout: TimeInterval = 2.5) {
        self.timeout = timeout
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Delegate queue nil => URLSession uses its own serial queue, so the
        // completion handler never needs the (possibly blocked) main thread.
        self.session = URLSession(configuration: config)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    public func convert(_ text: String) -> [(reading: String, candidates: [String])]? {
        if text.isEmpty { return nil }
        guard let url = Self.makeURL(text) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "GET"

        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            if error == nil,
               let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode) {
                box.set(data)
            }
            semaphore.signal()
        }
        task.resume()

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.cancel()
            return nil
        }
        guard let data = box.get() else { return nil }
        return Self.parse(data)
    }

    // MARK: - Helpers

    static func makeURL(_ text: String) -> URL? {
        // URLComponents.queryItems leaves "+" and "|" partly unescaped; encode
        // the values ourselves with a strict unreserved set.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        // `alphanumerics` contains non-ASCII letters (kana/kanji); restrict to ASCII.
        allowed = allowed.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(0x7F)))
        func enc(_ s: String) -> String? { s.addingPercentEncoding(withAllowedCharacters: allowed) }

        guard var comps = URLComponents(string: endpoint),
              let langpair = enc("ja-Hira|ja"),
              let encodedText = enc(text) else { return nil }
        comps.percentEncodedQueryItems = [
            URLQueryItem(name: "langpair", value: langpair),
            URLQueryItem(name: "text", value: encodedText),
        ]
        return comps.url
    }

    static func parse(_ data: Data) -> [(reading: String, candidates: [String])]? {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let array = json as? [Any] else { return nil }
        var result: [(reading: String, candidates: [String])] = []
        for item in array {
            guard let pair = item as? [Any], pair.count >= 2,
                  let reading = pair[0] as? String,
                  let rawCandidates = pair[1] as? [Any] else { return nil }
            var seen = Set<String>()
            var candidates: [String] = []
            for case let c as String in rawCandidates where !c.isEmpty {
                if seen.insert(c).inserted { candidates.append(c) }
            }
            result.append((reading: reading, candidates: candidates))
        }
        return result.isEmpty ? nil : result
    }
}

/// Thread-safe holder for the response data handed across queues.
private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    func set(_ d: Data?) {
        lock.lock(); defer { lock.unlock() }
        data = d
    }

    func get() -> Data? {
        lock.lock(); defer { lock.unlock() }
        return data
    }
}
