import Foundation
@testable import MLHCore

func runSettingsStoreTests() -> (passed: Int, failed: Int) {
    var passed = 0
    var failed = 0
    func check(_ name: String, _ okay: Bool) {
        if okay { passed += 1 } else { failed += 1; print("FAIL: \(name)") }
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let domain = "mlh-settings-store-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    #if os(Linux)
    let execute = root.appendingPathComponent("mlh/execute.json")
    let dictionary = root.appendingPathComponent("mlh/userdict.txt")
    #else
    let execute = root.appendingPathComponent("execute.json")
    let dictionary = root.appendingPathComponent("userdict.txt")
    #endif
    let store = SettingsStore(defaults: defaults, environment: ["XDG_CONFIG_HOME": root.path],
                              executeURL: execute, userDictionaryURL: dictionary,
                              apiKeyPresent: false, commandAvailable: false)
    func request(_ json: String) throws -> SettingsApplyRequest {
        try JSONDecoder().decode(SettingsApplyRequest.self, from: Data(json.utf8))
    }
    #if os(Linux)
    do {
        let missing = try store.snapshot().fields.first { $0.id == "openai.apiKey" }!
        check("secret unavailable is read only", !missing.editable && !missing.has_value)
        let available = SettingsStore(defaults: defaults, environment: ["XDG_CONFIG_HOME": root.path],
                                      executeURL: execute, userDictionaryURL: dictionary,
                                      apiKeyPresent: false, commandAvailable: false,
                                      apiKeySecretAvailable: true, apiKeySecretPresent: true)
        let saved = try available.snapshot().fields.first { $0.id == "openai.apiKey" }!
        check("secret service value masked", saved.origin == "secretService" &&
              saved.has_value && saved.editable && saved.value == nil)
        let envStore = SettingsStore(defaults: defaults,
                                     environment: ["XDG_CONFIG_HOME": root.path, "OPENAI_API_KEY": ""],
                                     executeURL: execute, userDictionaryURL: dictionary,
                                     apiKeyPresent: true, commandAvailable: false,
                                     apiKeySecretAvailable: true, apiKeySecretPresent: true)
        let envField = try envStore.snapshot().fields.first { $0.id == "openai.apiKey" }!
        check("empty environment key has priority", envField.origin == "environment" &&
              envField.has_value && !envField.editable)
        let secretChange = try request(#"{"schema":1,"changes":[{"id":"openai.apiKey","op":"set","value":"test"}],"actions":[]}"#)
        do {
            try store.apply(secretChange) { _ in fatalError("unavailable service must not write") }
            check("unavailable service rejects write", false)
        } catch {
            check("unavailable service rejects write", error.localizedDescription.contains("Secret Service"))
        }
        var written: String?
        try available.apply(secretChange) { written = $0 }
        check("secret service write delegated", written == "test")
        do {
            try envStore.apply(secretChange) { _ in fatalError("environment key must not be overwritten") }
            check("environment key cannot be changed", false)
        } catch {
            check("environment key cannot be changed", true)
        }
    } catch {
        print("FAIL: Linux secret settings: \(error)")
        failed += 1
    }
    #endif
    do {
        let initial = try store.snapshot()
        check("schema", initial.schema == 1)
        check("all fields have sections", initial.fields.allSatisfy { field in
            initial.sections.contains { $0.id == field.section }
        })
        check("secret masked", initial.fields.first { $0.id == "openai.apiKey" }?.value == nil)
        let add = try request(#"{"schema":1,"changes":[],"actions":[{"id":"execute.entry.add","values":{"key":"2","app":""}}]}"#)
        try store.apply(add) { _ in fatalError("unexpected secret write") }
        check("numbered entry created", try store.snapshot().fields.contains { $0.id == "execute.entry.g.2.model" })
        let change = try request(#"{"schema":1,"changes":[{"id":"execute.entry.g.2.model","op":"set","value":"test-model"},{"id":"dictionary.entries","op":"set","value":"yomi\t候補\n"}],"actions":[]}"#)
        try store.apply(change) { _ in fatalError("unexpected secret write") }
        let after = try store.snapshot()
        check("entry value", after.fields.first { $0.id == "execute.entry.g.2.model" }?.value == "test-model")
        check("dictionary content", try String(contentsOf: dictionary, encoding: .utf8) == "yomi\t候補\n")
        let remove = try request(#"{"schema":1,"changes":[],"actions":[{"id":"execute.entry.remove:execute.entry.g.2","values":{}}]}"#)
        try store.apply(remove) { _ in fatalError("unexpected secret write") }
        check("numbered entry removed", try !store.snapshot().fields.contains { $0.id == "execute.entry.g.2.model" })
        let bad = try request(#"{"schema":1,"changes":[{"id":"missing","op":"set","value":"x"}],"actions":[]}"#)
        do {
            try store.apply(bad) { _ in fatalError("unexpected secret write") }
            check("unknown field rejected", false)
        } catch {
            check("unknown field rejected", true)
        }
        try Data("{ invalid".utf8).write(to: execute)
        check("malformed execute file is shown", try store.snapshot().fields.contains { $0.id == "execute.configError" })
        let unrelated = try request(#"{"schema":1,"changes":[{"id":"openai.model","op":"set","value":"unrelated"}],"actions":[]}"#)
        try store.apply(unrelated) { _ in fatalError("unexpected secret write") }
        check("unrelated setting can be saved", try String(contentsOf: execute, encoding: .utf8) == "{ invalid")
        #if os(Linux)
        let linuxFile = LinuxSettings.url(environment: ["XDG_CONFIG_HOME": root.path])
        try FileManager.default.createDirectory(at: linuxFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ broken".utf8).write(to: linuxFile)
        check("malformed Linux settings are shown", try store.snapshot().fields.contains { $0.id == "linux.configError" })
        #endif
    } catch {
        print("FAIL: settings store error: \(error)")
        failed += 1
    }
    return (passed, failed)
}
