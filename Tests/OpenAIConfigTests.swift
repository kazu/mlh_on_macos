import Foundation
@testable import MLHCore

func runOpenAIConfigTests() -> (passed: Int, failed: Int) {
    var passed = 0
    var failed = 0
    func check(_ name: String, _ result: Bool) {
        if result { passed += 1 } else { failed += 1; print("FAIL: \(name)") }
    }

    let defaults = UserDefaults(suiteName: "mlh-tests-openai-config")!
    defaults.removePersistentDomain(forName: "mlh-tests-openai-config")
    let initial = OpenAI.Config(defaults: defaults)
    let overridden = initial.applyingEnvironment([
        "MLH_OPENAI_BASE_URL": "https://example.test/v1",
        "MLH_OPENAI_MODEL": "local-model",
        "MLH_OPENAI_INSTRUCTIONS": "translate",
        "MLH_OPENAI_REASONING_EFFORT": "none"
    ])
    check("environment base URL", overridden.baseURL == "https://example.test/v1")
    check("environment model", overridden.model == "local-model")
    check("environment instructions", overridden.instructions == "translate")
    check("environment reasoning", overridden.reasoningEffort == "none")

    let partial = initial.applyingEnvironment(["MLH_OPENAI_MODEL": "other"])
    check("missing base URL preserves default", partial.baseURL == initial.baseURL)
    check("missing instructions preserves default", partial.instructions == initial.instructions)
    check("missing reasoning preserves default", partial.reasoningEffort == initial.reasoningEffort)
    check("model changes alone", partial.model == "other")
    defaults.set("stored-model", forKey: "OpenAIModel")
    let resolved = OpenAI.Config.resolved(defaults: defaults, environment: [
        "MLH_OPENAI_MODEL": "",
        "MLH_OPENAI_REASONING_EFFORT": "none"
    ])
    check("resolved environment empty model", resolved.model.value == "" && resolved.model.origin == .environment)
    check("resolved environment effort", resolved.reasoningEffort.value == "none" && resolved.reasoningEffort.origin == .environment)
    check("resolved defaults base URL", resolved.baseURL.value == OpenAI.defaultBaseURL && resolved.baseURL.origin == .automatic)
    check("resolved config matches runtime", resolved.config.model == OpenAI.Config(defaults: defaults).applyingEnvironment(["MLH_OPENAI_MODEL": ""]).model)
    let stored = OpenAI.Config.resolved(defaults: defaults, persisted: ["MLH_OPENAI_MODEL": "stored-from-file"])
    check("stored model value and origin", stored.model.value == "stored-from-file" && stored.model.origin == .file)
    let processWins = OpenAI.Config.resolved(defaults: defaults,
                                             environment: ["MLH_OPENAI_MODEL": "from-env"],
                                             persisted: ["MLH_OPENAI_MODEL": "stored-from-file"])
    check("environment overrides stored model", processWins.model.value == "from-env" && processWins.model.origin == .environment)
    defaults.removePersistentDomain(forName: "mlh-tests-openai-config")
    return (passed, failed)
}
