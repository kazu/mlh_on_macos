import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The OpenAI Chat Completions API (or a compatible server), used by the
/// `x` scheme: the line before "x/" is sent and replaced with the reply.
public enum OpenAI {
    public static let defaultBaseURL = "https://api.openai.com/v1"
    public static let defaultModel = "gpt-4o-mini"
    public static let defaultInstructions = """
        The user text is an instruction, or a text to rewrite. Reply with only the \
        resulting text, without explanations, quotes or Markdown.
        """

    /// Settings, read from the IME's defaults domain
    /// (com.github.kazu.inputmethod.mlh): OpenAIModel, OpenAIInstructions,
    /// OpenAIBaseURL, OpenAIReasoningEffort.
    public struct Config {
        public var baseURL: String
        public var model: String
        public var instructions: String
        /// Sent as `reasoning_effort` when set (e.g. "none" turns thinking off).
        public var reasoningEffort: String?

        public init(defaults: UserDefaults = .standard) {
            baseURL = defaults.string(forKey: "OpenAIBaseURL") ?? OpenAI.defaultBaseURL
            model = defaults.string(forKey: "OpenAIModel") ?? OpenAI.defaultModel
            instructions = defaults.string(forKey: "OpenAIInstructions") ?? OpenAI.defaultInstructions
            reasoningEffort = defaults.string(forKey: "OpenAIReasoningEffort")
        }
    }

    /// A streaming chat completion request for `input`.
    /// Sent without an Authorization header when `apiKey` is nil (local
    /// servers such as LM Studio or Ollama).
    public static func request(_ input: String, config: Config, apiKey: String?) -> URLRequest? {
        guard let url = endpoint(config.baseURL) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if let apiKey { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = requestBody(input, config: config)
        return req
    }

    /// `<base>/chat/completions`; a base that already ends with it is used as is.
    static func endpoint(_ base: String) -> URL? {
        var s = base
        while s.hasSuffix("/") { s.removeLast() }
        if !s.hasSuffix("/chat/completions") { s += "/chat/completions" }
        return URL(string: s)
    }

    static func requestBody(_ input: String, config: Config) -> Data {
        var body: [String: Any] = [
            "model": config.model,
            "stream": true,
            "messages": [
                ["role": "system", "content": config.instructions],
                ["role": "user", "content": input],
            ],
        ]
        if let effort = config.reasoningEffort { body["reasoning_effort"] = effort }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    /// One line of the server-sent event stream.
    public enum StreamEvent: Equatable {
        case delta(String)
        case done
        case ignored
    }

    public static func parseStreamLine(_ line: String) -> StreamEvent {
        guard line.hasPrefix("data:") else { return .ignored }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String else { return .ignored }
        return .delta(content)
    }

    /// The error message of a non-streaming error response, if any.
    public static func errorMessage(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = obj["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }
}
