import Foundation

/// Per-number settings for `Nx/` (N is any number the user picks), read from
/// ~/Library/Application Support/MLH/execute.json:
///
///   {
///     "2": { "instructions": "Translate into English." },
///     "5": { "model": "qwen/qwen3.5-35b-a3b", "reasoningEffort": "low" },
///     "9": { "command": "~/bin/mlh-filter" }
///   }
///
/// Missing fields fall back to the defaults (OpenAIModel etc.). An entry
/// with "command" runs that command; otherwise it uses the OpenAI backend
/// unless "backend" says "command".
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

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MLH/execute.json")
    }

    public static func load(from url: URL = defaultURL) -> [String: ExecuteSettings] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return parse(data)
    }

    public static func parse(_ data: Data) -> [String: ExecuteSettings] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var result: [String: ExecuteSettings] = [:]
        for (key, value) in obj {
            guard let d = value as? [String: Any] else { continue }
            result[key] = ExecuteSettings(backend: d["backend"] as? String,
                                          command: d["command"] as? String,
                                          baseURL: d["baseURL"] as? String,
                                          model: d["model"] as? String,
                                          instructions: d["instructions"] as? String,
                                          reasoningEffort: d["reasoningEffort"] as? String)
        }
        return result
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
