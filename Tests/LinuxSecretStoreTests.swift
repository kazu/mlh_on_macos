#if os(Linux)
import Foundation
@testable import MLHCore

/// Run only with an isolated HOME, XDG directories, and session bus.
func runLinuxSecretStoreTests() -> (passed: Int, failed: Int) {
    guard let mode = ProcessInfo.processInfo.environment["MLH_TEST_SECRET_SERVICE"] else {
        return (0, 0)
    }
    var passed = 0
    var failed = 0
    func check(_ name: String, _ okay: Bool) {
        if okay { passed += 1 } else { failed += 1; print("FAIL: \(name)") }
    }
    let config = OpenAI.Config(defaults: UserDefaults.standard)
    do {
        switch mode {
        case "unavailable":
            check("service unavailable", !LinuxSecretStore.status().available)
            check("missing service yields no key", try LinuxSecretStore.read() == nil)
            let request = OpenAI.request("test", config: config, apiKey: try LinuxSecretStore.apiKey(environment: [:]))
            check("no key preserves unauthenticated request", request?.value(forHTTPHeaderField: "Authorization") == nil)
            check("environment key bypasses missing service",
                  try LinuxSecretStore.apiKey(environment: ["OPENAI_API_KEY": "env"]) == "env")
            do {
                try LinuxSecretStore.write("isolated-test-token")
                check("write requires service", false)
            } catch {
                check("write requires service", !error.localizedDescription.contains("isolated-test-token"))
            }
        case "available":
            check("service available", LinuxSecretStore.status().available)
            try LinuxSecretStore.write("isolated-test-token")
            defer { try? LinuxSecretStore.write(nil) }
            check("stored key found", LinuxSecretStore.status().hasValue)
            check("stored key read", try LinuxSecretStore.read() == "isolated-test-token")
            check("environment key wins", try LinuxSecretStore.apiKey(environment: ["OPENAI_API_KEY": "env"]) == "env")
            check("empty environment key wins", try LinuxSecretStore.apiKey(environment: ["OPENAI_API_KEY": ""]) == "")
            let key = try LinuxSecretStore.apiKey(environment: [:])
            let request = OpenAI.request("test", config: config, apiKey: key)
            check("stored key reaches request", request?.value(forHTTPHeaderField: "Authorization") == "Bearer isolated-test-token")
            try LinuxSecretStore.write(nil)
            check("key removed", !LinuxSecretStore.status().hasValue)
        default:
            check("recognized isolated test mode", false)
        }
    } catch {
        print("FAIL: Linux Secret Service test: \(error.localizedDescription)")
        failed += 1
    }
    return (passed, failed)
}
#endif
