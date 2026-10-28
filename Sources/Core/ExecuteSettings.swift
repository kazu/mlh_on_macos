import Foundation

/// Settings for `x`, read from ~/Library/Application Support/MLH/execute.json:
///
///   {
///     "2": { "instructions": "Translate into English." },
///     "5": { "model": "qwen/qwen3.5-35b-a3b", "reasoningEffort": "low" },
///     "9": { "command": "~/bin/mlh-filter" },
///     "apps": {
///       "com.tinyspeck.slackmacgap": {
///         "instructions": "... casual ...",
///         "2": { "instructions": "... casual English ..." }
///       }
///     }
///   }
///
/// A number N (any the user picks) is used by `Nx/`. Under "apps", entries
/// for the app being typed into (by bundle ID) override the settings: its
/// own fields for plain `x/`, its numbered entries for `Nx/`.
public struct ExecuteFile: Equatable {
    public var entries: [String: ExecuteSettings] = [:]
    public var apps: [String: AppSettings] = [:]

    public struct AppSettings: Equatable {
        /// For plain `x/`.
        public var base: ExecuteSettings?
        public var entries: [String: ExecuteSettings] = [:]
    }

    public init() {}

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MLH/execute.json")
    }

    public static func load(from url: URL = defaultURL) -> ExecuteFile {
        guard let data = try? Data(contentsOf: url) else { return ExecuteFile() }
        return parse(data)
    }

    public static func parse(_ data: Data) -> ExecuteFile {
        var file = ExecuteFile()
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return file }
        file.entries = numberedEntries(obj)
        for (bundleID, value) in obj["apps"] as? [String: Any] ?? [:] {
            guard let d = value as? [String: Any] else { continue }
            let base = ExecuteSettings(d)
            file.apps[bundleID] = AppSettings(base: base.isEmpty ? nil : base, entries: numberedEntries(d))
        }
        return file
    }

    private static func numberedEntries(_ obj: [String: Any]) -> [String: ExecuteSettings] {
        var result: [String: ExecuteSettings] = [:]
        for (key, value) in obj where !key.isEmpty && key.allSatisfy({ ("0"..."9").contains($0) }) {
            if let d = value as? [String: Any] { result[key] = ExecuteSettings(d) }
        }
        return result
    }

    /// The settings for `x/` (key nil) or `Nx/` typed into `app`, or nil when
    /// nothing is configured for it (plain `x/` then uses the defaults).
    public func settings(for key: String?, app: String?) -> ExecuteSettings? {
        var result = key.flatMap { entries[$0] }
        if let app, let a = apps[app], let o = key == nil ? a.base : a.entries[key!] {
            result = (result ?? ExecuteSettings()).merged(with: o)
        }
        return result
    }
}

public struct ExecuteSettings: Equatable {
    public var backend: String?
    public var command: String?
    public var baseURL: String?
    public var model: String?
    public var instructions: String?
    public var reasoningEffort: String?

    public init(backend: String? = nil, command: String? = nil, baseURL: String? = nil, model: String? = nil,
                instructions: String? = nil, reasoningEffort: String? = nil) {
        self.backend = backend
        self.command = command
        self.baseURL = baseURL
        self.model = model
        self.instructions = instructions
        self.reasoningEffort = reasoningEffort
    }

    init(_ d: [String: Any]) {
        self.init(backend: d["backend"] as? String, command: d["command"] as? String,
                  baseURL: d["baseURL"] as? String, model: d["model"] as? String,
                  instructions: d["instructions"] as? String, reasoningEffort: d["reasoningEffort"] as? String)
    }

    var isEmpty: Bool { self == ExecuteSettings() }

    /// `self` with the fields set in `other` replaced.
    public func merged(with other: ExecuteSettings) -> ExecuteSettings {
        ExecuteSettings(backend: other.backend ?? backend, command: other.command ?? command,
                        baseURL: other.baseURL ?? baseURL, model: other.model ?? model,
                        instructions: other.instructions ?? instructions,
                        reasoningEffort: other.reasoningEffort ?? reasoningEffort)
    }

    /// The backend name for this entry: "command" or "openai".
    public var resolvedBackend: String {
        backend ?? (command != nil ? "command" : "openai")
    }

    /// `config` with this entry's fields applied.
    public func apply(to config: OpenAI.Config) -> OpenAI.Config {
        var c = config
        if let baseURL { c.baseURL = baseURL }
        if let model { c.model = model }
        if let instructions { c.instructions = instructions }
        if let reasoningEffort { c.reasoningEffort = reasoningEffort }
        return c
    }
}
