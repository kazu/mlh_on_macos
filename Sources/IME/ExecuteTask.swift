import Foundation
import Security
import os

private let log = Logger(subsystem: mlhBundleIdentifier, category: "execute")

/// What the `x` scheme runs (in place of egg's `mlh-userdef-function`). It
/// gets the line before "x/" and its result replaces that line.
protocol ExecuteTask: AnyObject {
    var source: String { get }
    /// Called on the main thread with the output so far (streaming backends).
    var onProgress: ((String) -> Void)? { get set }
    /// Output received so far.
    var partial: String { get }
    /// Calls `f` on the main thread with the result, or nil on failure.
    func whenReady(_ f: @escaping (String?) -> Void)
    func cancel()
}

/// Chooses the backend for `x`:
///   defaults write com.github.kazu.inputmethod.mlh ExecuteBackend command|openai
/// Without the setting: the command if ~/Library/Application Support/MLH/execute
/// exists, else OpenAI if its API key is in the keychain, else nothing (`x/`
/// is just removed, as in egg without mlh-userdef-function).
enum Execute {
    enum Backend: String { case command, openai }

    static var backend: Backend? {
        if let name = UserDefaults.standard.string(forKey: "ExecuteBackend") {
            return Backend(rawValue: name)
        }
        if CommandTask.isAvailable { return .command }
        if OpenAITask.hasAPIKey { return .openai }
        return nil
    }

    static func makeTask(source: String, clientBundleID: String?) -> ExecuteTask? {
        switch backend {
        case .command: return CommandTask(source: source, clientBundleID: clientBundleID)
        case .openai: return OpenAITask(source: source)
        case nil: return nil
        }
    }
}

/// Shared bookkeeping for finishing once and notifying waiters.
class ExecuteTaskBase {
    static let timeout: TimeInterval = 60

    let source: String
    var onProgress: ((String) -> Void)?
    var partial = ""
    private var finished = false
    private var result: String?
    private var waiters: [(String?) -> Void] = []

    init(source: String) {
        self.source = source
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
            guard let self, !self.finished else { return }
            log.error("execute timed out")
            self.cancel()
            self.finish(nil)
        }
    }

    func whenReady(_ f: @escaping (String?) -> Void) {
        if finished { f(result) } else { waiters.append(f) }
    }

    func cancel() {}

    /// Main thread only.
    func finish(_ text: String?) {
        guard !finished else { return }
        finished = true
        result = text
        let waiters = self.waiters
        self.waiters = []
        waiters.forEach { $0(text) }
    }
}

/// Runs the executable ~/Library/Application Support/MLH/execute with the
/// line on standard input; its standard output (without the trailing
/// newline) is the result. A non-zero exit status is a failure.
final class CommandTask: ExecuteTaskBase, ExecuteTask {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MLH/execute")
    }

    static var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: url.path) }

    private let process = Process()

    init(source: String, clientBundleID: String?) {
        super.init(source: source)
        process.executableURL = Self.url
        var env = ProcessInfo.processInfo.environment
        env["MLH_CLIENT_BUNDLE_ID"] = clientBundleID ?? ""
        process.environment = env
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let process = self.process
        DispatchQueue.global(qos: .userInitiated).async {
            var text: String?
            do {
                try process.run()
                input.fileHandleForWriting.write(Data(source.utf8))
                try? input.fileHandleForWriting.close()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    var s = String(decoding: data, as: UTF8.self)
                    while s.hasSuffix("\n") || s.hasSuffix("\r") { s.removeLast() }
                    text = s
                } else {
                    log.error("command exited with status \(process.terminationStatus)")
                }
            } catch {
                log.error("command failed to run: \(error.localizedDescription, privacy: .public)")
            }
            DispatchQueue.main.async { self.finish(text) }
        }
    }

    override func cancel() {
        if process.isRunning { process.terminate() }
    }
}

/// Sends the line to the OpenAI Chat Completions API (or a compatible
/// server, see `OpenAI.Config`) and streams the reply. The API key is the
/// generic password with service "mlh-openai" in the login keychain; without
/// one the request is sent unauthenticated (local servers).
// State is only touched on the main thread; the request task hops there.
final class OpenAITask: ExecuteTaskBase, ExecuteTask, @unchecked Sendable {
    static let keychainService = "mlh-openai"

    /// One session for all requests, so the connection is reused.
    private static let session = URLSession(configuration: .default)

    /// Whether the key exists (doesn't read the secret, so no keychain prompt).
    static var hasAPIKey: Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: keychainService,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func apiKey() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: keychainService,
                                    kSecMatchLimit as String: kSecMatchLimitOne,
                                    kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var task: Task<Void, Never>?

    override init(source: String) {
        super.init(source: source)
        let config = OpenAI.Config()
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let key = Self.apiKey()
            if key == nil {
                log.debug("no API key in the keychain (service \(Self.keychainService, privacy: .public)); sending without one")
            }
            guard var request = OpenAI.request(source, config: config, apiKey: key) else {
                DispatchQueue.main.async { self?.finish(nil) }
                return
            }
            request.timeoutInterval = Self.timeout
            var reply = ""
            var ok = false
            do {
                let (bytes, response) = try await Self.session.bytes(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 {
                    for try await line in bytes.lines {
                        switch OpenAI.parseStreamLine(line) {
                        case .delta(let d):
                            reply += d
                            let soFar = reply
                            DispatchQueue.main.async {
                                guard let self else { return }
                                self.partial = soFar
                                self.onProgress?(soFar)
                            }
                        case .done:
                            break
                        case .ignored:
                            continue
                        }
                    }
                    ok = !reply.isEmpty
                } else {
                    var body = Data()
                    for try await b in bytes { body.append(b) }
                    let message = OpenAI.errorMessage(body) ?? String(decoding: body, as: UTF8.self)
                    log.error("OpenAI HTTP \(status): \(message, privacy: .public)")
                }
            } catch {
                log.error("OpenAI request failed: \(error.localizedDescription, privacy: .public)")
            }
            let result = ok ? reply.trimmingCharacters(in: .newlines) : nil
            DispatchQueue.main.async { self?.finish(result) }
        }
    }

    override func cancel() {
        task?.cancel()
    }
}
