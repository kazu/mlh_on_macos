import Foundation
@testable import MLHCore

func runSettingsResolutionTests() -> (passed: Int, failed: Int) {
    var passed = 0
    var failed = 0
    func check(_ name: String, _ okay: Bool) {
        if okay { passed += 1 } else { failed += 1; print("FAIL: \(name)") }
    }

    func unavailable() -> Bool { fatalError("availability must not be checked for explicit backend") }
    let explicit = ExecuteBackend.resolve(
        configuredName: "openai", configuredOrigin: .environment,
        commandAvailable: unavailable(), apiKeyAvailable: unavailable()
    )
    check("explicit backend", explicit.value == .openai && explicit.origin == .environment)
    let invalid = ExecuteBackend.resolve(
        configuredName: "invalid", configuredOrigin: .userDefaults,
        commandAvailable: unavailable(), apiKeyAvailable: unavailable()
    )
    check("invalid explicit backend suppresses fallback", invalid.value == nil && invalid.origin == .userDefaults)
    let empty = ExecuteBackend.resolve(
        configuredName: "", configuredOrigin: .environment,
        commandAvailable: unavailable(), apiKeyAvailable: unavailable()
    )
    check("empty explicit backend suppresses fallback", empty.value == nil && empty.origin == .environment)
    let command = ExecuteBackend.resolve(
        configuredName: nil, configuredOrigin: .environment,
        commandAvailable: true, apiKeyAvailable: false
    )
    check("command fallback", command.value == .command && command.origin == .automatic)
    let openai = ExecuteBackend.resolve(
        configuredName: nil, configuredOrigin: .userDefaults,
        commandAvailable: false, apiKeyAvailable: true
    )
    check("OpenAI fallback", openai.value == .openai && openai.origin == .automatic)
    let none = ExecuteBackend.resolve(
        configuredName: nil, configuredOrigin: .userDefaults,
        commandAvailable: false, apiKeyAvailable: false
    )
    check("unavailable fallback", none.value == nil && none.origin == .automatic)
    let local = KanjiBackend.resolve(configuredName: nil, origin: .userDefaults)
    check("default kanji backend", local.value == .azookey && local.origin == .automatic)
    let google = KanjiBackend.resolve(configuredName: "google", origin: .environment)
    check("google kanji backend", google.value == .google && google.origin == .environment)
    let unknown = KanjiBackend.resolve(configuredName: "invalid", origin: .userDefaults)
    check("unknown kanji backend uses local", unknown.value == .azookey && unknown.origin == .userDefaults)
    let defaults = UserDefaults(suiteName: "mlh-tests-settings-resolution")!
    defaults.removePersistentDomain(forName: "mlh-tests-settings-resolution")
    let unsetInteger = ZenzaiSettings.integer("ZenzaiContextLength", defaults: defaults)
    check("unset zenzai integer", unsetInteger.value == nil && unsetInteger.origin == .automatic)
    defaults.set("invalid", forKey: "ZenzaiContextLength")
    let invalidInteger = ZenzaiSettings.integer("ZenzaiContextLength", defaults: defaults)
    check("invalid zenzai integer follows UserDefaults coercion", invalidInteger.value == defaults.integer(forKey: "ZenzaiContextLength") && invalidInteger.origin == .userDefaults)
    defaults.set("~/models/zenz.gguf", forKey: "ZenzaiModel")
    let model = ZenzaiSettings.modelPath(defaults: defaults)
    check("zenzai model expands tilde", model.value == ("~/models/zenz.gguf" as NSString).expandingTildeInPath && model.origin == .userDefaults)
    defaults.removePersistentDomain(forName: "mlh-tests-settings-resolution")
    return (passed, failed)
}
