import Foundation

/// Editable `execute.json` document. Unknown fields are retained when an entry changes.
public struct ExecuteSettingsDocument {
    public enum EditError: LocalizedError {
        case invalidRoot
        case invalidTarget
        case invalidStructure

        public var errorDescription: String? {
            switch self {
            case .invalidRoot, .invalidStructure: return "execute.json の形式が正しくありません。"
            case .invalidTarget: return "番号またはアプリ ID を確認してください。"
            }
        }
    }

    private var root: [String: Any]
    private var file: ExecuteFile

    public var numberedKeys: [String] { file.entries.keys.sorted() }
    public var appIDs: [String] { file.apps.keys.sorted() }

    public func numberedKeys(for app: String) -> [String] {
        file.apps[app]?.entries.keys.sorted() ?? []
    }

    public init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EditError.invalidRoot
        }
        self.root = root
        file = ExecuteFile.parse(data)
    }

    /// Returns the effective settings for a numbered or app-specific `x/` entry.
    public func settings(for key: String?, app: String?) -> ExecuteSettings? {
        file.settings(for: key, app: app)
    }

    /// Returns only fields written in this entry, without inherited settings.
    public func entry(for key: String?, app: String?) -> ExecuteSettings? {
        if let app {
            guard let appSettings = file.apps[app] else { return nil }
            if let key { return appSettings.entries[key] }
            return appSettings.base
        }
        return key.flatMap { file.entries[$0] }
    }

    /// Replaces the known fields of one entry; nil removes the entry.
    public mutating func setSettings(_ settings: ExecuteSettings?, for key: String?, app: String?) throws {
        guard key != nil || app != nil else { throw EditError.invalidTarget }
        if let key, key.isEmpty || !key.allSatisfy({ ("0"..."9").contains($0) }) {
            throw EditError.invalidTarget
        }
        if let app {
            guard !app.isEmpty else { throw EditError.invalidTarget }
            if root["apps"] != nil && !(root["apps"] is [String: Any]) { throw EditError.invalidStructure }
            var apps = root["apps"] as? [String: Any] ?? [:]
            if apps[app] != nil && !(apps[app] is [String: Any]) { throw EditError.invalidStructure }
            var entry = apps[app] as? [String: Any] ?? [:]
            if let key {
                if entry[key] != nil && !(entry[key] is [String: Any]) { throw EditError.invalidStructure }
                if let settings {
                    entry[key] = Self.settingFields(settings, retaining: entry[key] as? [String: Any] ?? [:])
                } else {
                    entry.removeValue(forKey: key)
                }
            } else if let settings {
                entry = Self.settingFields(settings, retaining: entry)
            } else {
                entry = Self.settingFields(ExecuteSettings(), retaining: entry)
            }
            if entry.isEmpty { apps.removeValue(forKey: app) } else { apps[app] = entry }
            if apps.isEmpty { root.removeValue(forKey: "apps") } else { root["apps"] = apps }
        } else if let key {
            if root[key] != nil && !(root[key] is [String: Any]) { throw EditError.invalidStructure }
            if let settings {
                root[key] = Self.settingFields(settings, retaining: root[key] as? [String: Any] ?? [:])
            } else {
                root.removeValue(forKey: key)
            }
        }
        file = ExecuteFile.parse(try encode())
    }

    /// Encodes the document as JSON for atomic writing by its caller.
    public func encode() throws -> Data {
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    /// Atomically replaces the file, retaining its permissions when it exists.
    public func save(to url: URL) throws {
        let data = try encode()
        let destination = url.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }

    private static func settingFields(_ settings: ExecuteSettings, retaining entry: [String: Any]) -> [String: Any] {
        var entry = entry
        let fields: [(String, String?)] = [
            ("backend", settings.backend), ("command", settings.command),
            ("baseURL", settings.baseURL), ("model", settings.model),
            ("instructions", settings.instructions), ("reasoningEffort", settings.reasoningEffort)
        ]
        for (key, value) in fields {
            if let value { entry[key] = value } else { entry.removeValue(forKey: key) }
        }
        return entry
    }
}
