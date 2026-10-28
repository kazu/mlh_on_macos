import Foundation

/// `mlh-userdef-table`: words converted by the `d` scheme.
///
/// File format (UTF-8): one entry per line, fields separated by TAB.
///   key<TAB>candidate1[<TAB>candidate2...]
/// Empty lines and lines starting with "#" are ignored. A later line for
/// the same key replaces an earlier one.
public struct UserDictionary {
    public private(set) var entries: [String: [String]]

    public init() { entries = [:] }

    public init(entries: [String: [String]]) {
        self.entries = entries.filter { !$0.value.isEmpty }
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MLH/userdict.txt")
    }

    public static func load(from url: URL) -> UserDictionary {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return UserDictionary() }
        return parse(text)
    }

    public static func parse(_ text: String) -> UserDictionary {
        var entries: [String: [String]] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("#") { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: true).map(String.init)
            guard fields.count >= 2 else { continue }
            entries[fields[0]] = Array(fields.dropFirst())
        }
        return UserDictionary(entries: entries)
    }

    public func lookup(_ key: String) -> [String]? { entries[key] }
}
