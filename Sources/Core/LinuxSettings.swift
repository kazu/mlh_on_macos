import Foundation

/// Linux's persistent overrides. Process environment remains the first source.
public enum LinuxSettings {
    public static let keys: Set<String> = [
        "MLH_EXEC_BACKEND", "MLH_EXEC_CONFIG", "MLH_EXEC_COMMAND",
        "MLH_OPENAI_BASE_URL", "MLH_OPENAI_MODEL", "MLH_OPENAI_INSTRUCTIONS",
        "MLH_OPENAI_REASONING_EFFORT", "MLH_TRANSLITERATOR", "MLH_DICTIONARY",
        "MLH_USER_DICTIONARY"
    ]

    public static func url(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let base = environment["XDG_CONFIG_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config").path
        return URL(fileURLWithPath: base).appendingPathComponent("mlh/settings.json")
    }

    public static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> [String: String] {
        let path = url(environment: environment)
        guard FileManager.default.fileExists(atPath: path.path) else { return [:] }
        let data = try Data(contentsOf: path)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SettingsError.invalidDocument
        }
        var values: [String: String] = [:]
        for key in keys {
            if let raw = root[key] {
                guard let value = raw as? String else { throw SettingsError.invalidDocument }
                values[key] = value
            }
        }
        return values
    }

    public static func resolve(_ key: String,
                               environment: [String: String] = ProcessInfo.processInfo.environment)
        -> ResolvedSetting<String?> {
        if let value = environment[key] {
            return ResolvedSetting(value: value, origin: .environment)
        }
        return resolve(key, environment: environment,
                       persisted: (try? load(environment: environment)) ?? [:])
    }

    static func resolve(_ key: String, environment: [String: String],
                        persisted: [String: String]) -> ResolvedSetting<String?> {
        if let value = environment[key] {
            return ResolvedSetting(value: value, origin: .environment)
        }
        if keys.contains(key), let value = persisted[key] {
            return ResolvedSetting(value: value, origin: .file)
        }
        return ResolvedSetting(value: nil, origin: .automatic)
    }

    /// Applies only requested keys and retains unrelated JSON properties.
    public static func save(_ changes: [String: String?],
                            environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        let path = url(environment: environment)
        let data = FileManager.default.fileExists(atPath: path.path) ? try Data(contentsOf: path) : nil
        let root: [String: Any]
        if let data {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SettingsError.invalidDocument
            }
            root = parsed
        } else {
            root = [:]
        }
        var updated = root
        for (key, value) in changes {
            guard keys.contains(key) else { throw SettingsError.invalidField }
            updated[key] = value
        }
        let encoded = try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys])
        let destination = path.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded.write(to: destination, options: .atomic)
    }

    public enum SettingsError: LocalizedError {
        case invalidDocument, invalidField

        public var errorDescription: String? {
            switch self {
            case .invalidDocument: return "settings.json の形式が正しくありません。"
            case .invalidField: return "保存できない設定項目です。"
            }
        }
    }
}
