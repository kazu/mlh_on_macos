import Foundation
@testable import MLHCore

let engine = runEngineTests()
print("engine: \(engine.passed) passed, \(engine.failed) failed")
let kanji = runKanjiConversionTests()
print("kanji conversion: \(kanji.passed) passed, \(kanji.failed) failed")
exit(engine.failed + kanji.failed == 0 ? 0 : 1)
