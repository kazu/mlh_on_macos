#if os(Linux)
import Foundation
import CLinuxSecret

/// The OpenAI credential in the desktop Secret Service, when one is available.
public enum LinuxSecretStore {
    public struct Status {
        public let available: Bool
        public let hasValue: Bool
        public let error: String?

        public init(available: Bool, hasValue: Bool, error: String?) {
            self.available = available
            self.hasValue = hasValue
            self.error = error
        }
    }

    public struct StoreError: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    private static func message(_ pointer: UnsafeMutablePointer<CChar>?) -> String {
        defer { mlh_secret_error_free(pointer) }
        return "Secret Service の操作に失敗しました。サービスの状態を確認してください。"
    }

    public static func status() -> Status {
        var value: UnsafeMutablePointer<CChar>?
        var failure: UnsafeMutablePointer<CChar>?
        let result = mlh_secret_read(&value, &failure)
        defer {
            mlh_secret_free(value)
            mlh_secret_error_free(failure)
        }
        switch result {
        case 0: return Status(available: true, hasValue: false, error: nil)
        case 1: return Status(available: true, hasValue: true, error: nil)
        default: return Status(available: false, hasValue: false,
                               error: "Secret Service を利用できません。")
        }
    }

    public static func read() throws -> String? {
        var value: UnsafeMutablePointer<CChar>?
        var failure: UnsafeMutablePointer<CChar>?
        let result = mlh_secret_read(&value, &failure)
        defer { mlh_secret_free(value) }
        switch result {
        case 0, -1:
            mlh_secret_error_free(failure)
            return nil
        case 1:
            mlh_secret_error_free(failure)
            return value.map { String(cString: $0) }
        default:
            throw StoreError(message: message(failure))
        }
    }

    public static func write(_ value: String?) throws {
        var failure: UnsafeMutablePointer<CChar>?
        let success = value.map { mlh_secret_write($0, &failure) }
            ?? mlh_secret_clear(&failure)
        guard success != 0 else { throw StoreError(message: message(failure)) }
        mlh_secret_error_free(failure)
    }

    public static func apiKey(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> String? {
        if let value = environment["OPENAI_API_KEY"] { return value }
        return try read()
    }
}
#endif
