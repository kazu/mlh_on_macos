import Foundation
@testable import MLHCore

#if os(Linux)
if ProcessInfo.processInfo.environment["MLH_TEST_SETTINGS_ONLY"] == "1" {
    let linuxSettings = runLinuxSettingsTests()
    let settingsStore = runSettingsStoreTests()
    let secret = runLinuxSecretStoreTests()
    print("Linux settings: \(linuxSettings.passed) passed, \(linuxSettings.failed) failed")
    print("settings store: \(settingsStore.passed) passed, \(settingsStore.failed) failed")
    print("Linux Secret Service: \(secret.passed) passed, \(secret.failed) failed")
    exit(linuxSettings.failed + settingsStore.failed + secret.failed == 0 ? 0 : 1)
}
#endif

let engine = runEngineTests()
print("engine: \(engine.passed) passed, \(engine.failed) failed")
let kanji = runKanjiConversionTests()
print("kanji conversion: \(kanji.passed) passed, \(kanji.failed) failed")
let deletion = runSyntheticDeletionTests()
print("synthetic deletion: \(deletion.passed) passed, \(deletion.failed) failed")
let settingsDocument = runExecuteSettingsDocumentTests()
print("settings document: \(settingsDocument.passed) passed, \(settingsDocument.failed) failed")
let openAIConfig = runOpenAIConfigTests()
print("OpenAI config: \(openAIConfig.passed) passed, \(openAIConfig.failed) failed")
let settingsResolution = runSettingsResolutionTests()
print("settings resolution: \(settingsResolution.passed) passed, \(settingsResolution.failed) failed")
let linuxSettings = runLinuxSettingsTests()
print("Linux settings: \(linuxSettings.passed) passed, \(linuxSettings.failed) failed")
let settingsStore = runSettingsStoreTests()
print("settings store: \(settingsStore.passed) passed, \(settingsStore.failed) failed")
exit(engine.failed + kanji.failed + deletion.failed + settingsDocument.failed + openAIConfig.failed + settingsResolution.failed + linuxSettings.failed + settingsStore.failed == 0 ? 0 : 1)
