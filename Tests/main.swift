import Foundation
@testable import MLHCore

let engine = runEngineTests()
print("engine: \(engine.passed) passed, \(engine.failed) failed")
let kanji = runKanjiConversionTests()
print("kanji conversion: \(kanji.passed) passed, \(kanji.failed) failed")
let deletion = runSyntheticDeletionTests()
print("synthetic deletion: \(deletion.passed) passed, \(deletion.failed) failed")
let openAIConfig = runOpenAIConfigTests()
print("OpenAI config: \(openAIConfig.passed) passed, \(openAIConfig.failed) failed")
let settingsResolution = runSettingsResolutionTests()
print("settings resolution: \(settingsResolution.passed) passed, \(settingsResolution.failed) failed")
exit(engine.failed + kanji.failed + deletion.failed + openAIConfig.failed + settingsResolution.failed == 0 ? 0 : 1)
