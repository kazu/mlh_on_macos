import Foundation
@testable import MLHCore

let engine = runEngineTests()
print("engine: \(engine.passed) passed, \(engine.failed) failed")
let kanji = runKanjiConversionTests()
print("kanji conversion: \(kanji.passed) passed, \(kanji.failed) failed")
let deletion = runSyntheticDeletionTests()
print("synthetic deletion: \(deletion.passed) passed, \(deletion.failed) failed")
exit(engine.failed + kanji.failed + deletion.failed == 0 ? 0 : 1)
