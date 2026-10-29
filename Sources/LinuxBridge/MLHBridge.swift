import Foundation
import MLHCore
#if os(Linux)
import Glibc
#else
import Darwin
#endif

private final class ResultBox {
    let result: MLHResult
    init(_ result: MLHResult) { self.result = result }
}

#if os(Linux)
private final class TypedBox {
    var buffer = TypedBuffer()
}

private final class ExecutionBox {
    let task: ExecuteTask
    init(_ task: ExecuteTask) { self.task = task }
}

public typealias MLHExecuteCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int32) -> Void

@_cdecl("mlh_run_main_loop")
public func mlhRunMainLoop() -> Never { dispatchMain() }

@_cdecl("mlh_execute_start")
public func mlhExecuteStart(_ source: UnsafePointer<CChar>, _ key: UnsafePointer<CChar>?, _ app: UnsafePointer<CChar>?,
                            _ callback: @escaping MLHExecuteCallback, _ context: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    let source = String(cString: source)
    let key = key.map { String(cString: $0) }
    let app = app.map { String(cString: $0) }
    return DispatchQueue.main.sync {
        guard let task = Execute.makeTask(source: source, key: key, clientBundleID: app) else { return nil }
        task.onProgress = { text in text.withCString { callback(context, $0, 0) } }
        task.whenReady { text in
            if let text { text.withCString { callback(context, $0, 1) } }
            else { callback(context, nil, 1) }
        }
        return Unmanaged.passRetained(ExecutionBox(task)).toOpaque()
    }
}

@_cdecl("mlh_execute_cancel")
public func mlhExecuteCancel(_ execution: UnsafeMutableRawPointer) {
    let task = Unmanaged<ExecutionBox>.fromOpaque(execution).takeUnretainedValue().task
    DispatchQueue.main.async { task.cancel() }
}

@_cdecl("mlh_execute_free")
public func mlhExecuteFree(_ execution: UnsafeMutableRawPointer) {
    Unmanaged<ExecutionBox>.fromOpaque(execution).release()
}

@_cdecl("mlh_typed_new")
public func mlhTypedNew() -> UnsafeMutableRawPointer { Unmanaged.passRetained(TypedBox()).toOpaque() }

@_cdecl("mlh_typed_free")
public func mlhTypedFree(_ typed: UnsafeMutableRawPointer) { Unmanaged<TypedBox>.fromOpaque(typed).release() }

@_cdecl("mlh_typed_append")
public func mlhTypedAppend(_ typed: UnsafeMutableRawPointer, _ text: UnsafePointer<CChar>) {
    Unmanaged<TypedBox>.fromOpaque(typed).takeUnretainedValue().buffer.append(String(cString: text))
}

@_cdecl("mlh_typed_set")
public func mlhTypedSet(_ typed: UnsafeMutableRawPointer, _ text: UnsafePointer<CChar>) {
    Unmanaged<TypedBox>.fromOpaque(typed).takeUnretainedValue().buffer.set(String(cString: text))
}

@_cdecl("mlh_typed_remove")
public func mlhTypedRemove(_ typed: UnsafeMutableRawPointer) {
    Unmanaged<TypedBox>.fromOpaque(typed).takeUnretainedValue().buffer.removeLast()
}

@_cdecl("mlh_typed_reset")
public func mlhTypedReset(_ typed: UnsafeMutableRawPointer) {
    Unmanaged<TypedBox>.fromOpaque(typed).takeUnretainedValue().buffer.reset()
}

@_cdecl("mlh_typed_text")
public func mlhTypedText(_ typed: UnsafeMutableRawPointer) -> UnsafeMutablePointer<CChar>? {
    Unmanaged<TypedBox>.fromOpaque(typed).takeUnretainedValue().buffer.text.withCString { strdup($0) }
}

@_cdecl("mlh_edit_plan")
public func mlhEditPlan(_ old: UnsafePointer<CChar>, _ new: UnsafePointer<CChar>, _ scalarCount: UnsafeMutablePointer<Int>, _ characterCount: UnsafeMutablePointer<Int>) -> UnsafeMutablePointer<CChar>? {
    let old = String(cString: old)
    let new = String(cString: new)
    let prefix = TextContext.commonPrefixLength(old, new)
    let removed = String(old.dropFirst(prefix))
    scalarCount.pointee = removed.unicodeScalars.count
    characterCount.pointee = removed.count
    return String(new.dropFirst(prefix)).withCString { strdup($0) }
}
#endif

@_cdecl("mlh_engine_new")
public func mlhEngineNew(_ dictionary: UnsafePointer<CChar>?, _ app: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer {
    let userDictionary = dictionary.map { UserDictionary.load(from: URL(fileURLWithPath: String(cString: $0))) } ?? UserDictionary()
    let engine = MLHEngine(userDictionary: userDictionary)
    #if os(Linux)
    let app = app.map { String(cString: $0) }
    engine.executeAvailable = { Execute.isAvailable($0, app: app) }
    #endif
    return Unmanaged.passRetained(engine).toOpaque()
}

@_cdecl("mlh_engine_free")
public func mlhEngineFree(_ engine: UnsafeMutableRawPointer) {
    Unmanaged<MLHEngine>.fromOpaque(engine).release()
}

@_cdecl("mlh_engine_run")
public func mlhEngineRun(_ engine: UnsafeMutableRawPointer, _ text: UnsafePointer<CChar>) -> UnsafeMutableRawPointer {
    let engine = Unmanaged<MLHEngine>.fromOpaque(engine).takeUnretainedValue()
    return Unmanaged.passRetained(ResultBox(engine.run(String(cString: text)))).toOpaque()
}

@_cdecl("mlh_result_free")
public func mlhResultFree(_ result: UnsafeMutableRawPointer) {
    Unmanaged<ResultBox>.fromOpaque(result).release()
}

@_cdecl("mlh_result_kind")
public func mlhResultKind(_ result: UnsafeMutableRawPointer) -> Int32 {
    switch Unmanaged<ResultBox>.fromOpaque(result).takeUnretainedValue().result {
    case .passThrough: return 0
    case .failure: return 1
    case .edit: return 2
    }
}

@_cdecl("mlh_result_text")
public func mlhResultText(_ result: UnsafeMutableRawPointer) -> UnsafeMutablePointer<CChar>? {
    let value: String
    switch Unmanaged<ResultBox>.fromOpaque(result).takeUnretainedValue().result {
    case .passThrough: return nil
    case .failure(let message): value = message
    case .edit(let outcome): value = outcome.text
    }
    return value.withCString { strdup($0) }
}

@_cdecl("mlh_result_henkan_begin")
public func mlhResultHenkanBegin(_ result: UnsafeMutableRawPointer) -> Int {
    guard case .edit(let outcome) = Unmanaged<ResultBox>.fromOpaque(result).takeUnretainedValue().result else { return -1 }
    return outcome.henkanBegin
}

@_cdecl("mlh_result_needs_kanji")
public func mlhResultNeedsKanji(_ result: UnsafeMutableRawPointer) -> Bool {
    guard case .edit(let outcome) = Unmanaged<ResultBox>.fromOpaque(result).takeUnretainedValue().result else { return false }
    return outcome.convertToKanji
}

@_cdecl("mlh_result_selection_count")
public func mlhResultSelectionCount(_ result: UnsafeMutableRawPointer) -> Int {
    guard case .edit(let outcome) = Unmanaged<ResultBox>.fromOpaque(result).takeUnretainedValue().result else { return 0 }
    return outcome.selections.count
}

@_cdecl("mlh_result_selection_candidates")
public func mlhResultSelectionCandidates(_ result: UnsafeMutableRawPointer, _ selection: Int) -> Int {
    guard case .edit(let outcome) = Unmanaged<ResultBox>.fromOpaque(result).takeUnretainedValue().result,
          outcome.selections.indices.contains(selection) else { return 0 }
    return outcome.selections[selection].candidates.count
}

@_cdecl("mlh_result_selection_candidate")
public func mlhResultSelectionCandidate(_ result: UnsafeMutableRawPointer, _ selection: Int, _ candidate: Int) -> UnsafeMutablePointer<CChar>? {
    guard case .edit(let outcome) = Unmanaged<ResultBox>.fromOpaque(result).takeUnretainedValue().result,
          outcome.selections.indices.contains(selection),
          outcome.selections[selection].candidates.indices.contains(candidate) else { return nil }
    return outcome.selections[selection].candidates[candidate].withCString { strdup($0) }
}

@_cdecl("mlh_result_render_part")
public func mlhResultRenderPart(_ result: UnsafeMutableRawPointer, _ choices: UnsafePointer<Int>, _ count: Int, _ suffix: Bool) -> UnsafeMutablePointer<CChar>? {
    guard case .edit(let outcome) = Unmanaged<ResultBox>.fromOpaque(result).takeUnretainedValue().result else { return nil }
    let rendered = outcome.render(choices: Array(UnsafeBufferPointer(start: choices, count: count)))
    let chars = Array(rendered.text)
    let begin = min(max(rendered.henkanBegin, 0), chars.count)
    let part = suffix ? String(chars[begin...]) : String(chars[..<begin])
    return part.withCString { strdup($0) }
}

private func selectionMarkStart(_ outcome: MLHOutcome) -> Int {
    let first = outcome.selections.first?.range.lowerBound ?? outcome.text.count
    if outcome.convertToKanji && outcome.henkanBegin < outcome.text.count { return min(first, outcome.henkanBegin) }
    return first
}

@_cdecl("mlh_result_selection_prefix")
public func mlhResultSelectionPrefix(_ result: UnsafeMutableRawPointer) -> UnsafeMutablePointer<CChar>? {
    guard case .edit(let outcome) = Unmanaged<ResultBox>.fromOpaque(result).takeUnretainedValue().result else { return nil }
    return String(outcome.text.prefix(selectionMarkStart(outcome))).withCString { strdup($0) }
}

@_cdecl("mlh_result_render_marked")
public func mlhResultRenderMarked(_ result: UnsafeMutableRawPointer, _ choices: UnsafePointer<Int>, _ count: Int, _ beforeKanji: Bool) -> UnsafeMutablePointer<CChar>? {
    guard case .edit(let outcome) = Unmanaged<ResultBox>.fromOpaque(result).takeUnretainedValue().result else { return nil }
    let rendered = outcome.render(choices: Array(UnsafeBufferPointer(start: choices, count: count)))
    let chars = Array(rendered.text)
    let start = min(selectionMarkStart(outcome), chars.count)
    let end = beforeKanji ? max(start, min(rendered.henkanBegin, chars.count)) : chars.count
    return String(chars[start..<end]).withCString { strdup($0) }
}

@_cdecl("mlh_result_execute_part")
public func mlhResultExecutePart(_ result: UnsafeMutableRawPointer, _ part: Int32) -> UnsafeMutablePointer<CChar>? {
    guard case .edit(let outcome) = Unmanaged<ResultBox>.fromOpaque(result).takeUnretainedValue().result,
          let begin = outcome.executeBegin else { return nil }
    if part == 2 { return outcome.executeKey?.withCString { strdup($0) } }
    let chars = Array(outcome.text)
    let offset = min(max(begin, 0), chars.count)
    let text = part == 0 ? String(chars[..<offset]) : String(chars[offset...])
    return text.withCString { strdup($0) }
}

@_cdecl("mlh_result_part")
public func mlhResultPart(_ result: UnsafeMutableRawPointer, _ suffix: Bool) -> UnsafeMutablePointer<CChar>? {
    guard case .edit(let outcome) = Unmanaged<ResultBox>.fromOpaque(result).takeUnretainedValue().result else { return nil }
    let chars = Array(outcome.text)
    let begin = min(max(outcome.henkanBegin, 0), chars.count)
    let part = suffix ? String(chars[begin...]) : String(chars[..<begin])
    return part.withCString { strdup($0) }
}

@_cdecl("mlh_conversion_new")
public func mlhConversionNew(_ source: UnsafePointer<CChar>, _ dictionary: UnsafePointer<CChar>) -> UnsafeMutableRawPointer {
    let transliterator: Transliterator
    if ProcessInfo.processInfo.environment["MLH_TRANSLITERATOR"] == "google" {
        transliterator = GoogleTransliterator()
    } else {
        transliterator = AzooKeyTransliterator(dictionaryURL: URL(fileURLWithPath: String(cString: dictionary)))
    }
    let conversion = KanjiConversion(source: String(cString: source), transliterator: transliterator)
    return Unmanaged.passRetained(conversion).toOpaque()
}

@_cdecl("mlh_conversion_free")
public func mlhConversionFree(_ conversion: UnsafeMutableRawPointer) {
    Unmanaged<KanjiConversion>.fromOpaque(conversion).release()
}

@_cdecl("mlh_conversion_text")
public func mlhConversionText(_ conversion: UnsafeMutableRawPointer) -> UnsafeMutablePointer<CChar>? {
    let text = Unmanaged<KanjiConversion>.fromOpaque(conversion).takeUnretainedValue().text
    return text.withCString { strdup($0) }
}

@_cdecl("mlh_conversion_reading")
public func mlhConversionReading(_ conversion: UnsafeMutableRawPointer) -> UnsafeMutablePointer<CChar>? {
    let text = Unmanaged<KanjiConversion>.fromOpaque(conversion).takeUnretainedValue().readingText
    return text.withCString { strdup($0) }
}

@_cdecl("mlh_conversion_candidate_count")
public func mlhConversionCandidateCount(_ conversion: UnsafeMutableRawPointer) -> Int {
    Unmanaged<KanjiConversion>.fromOpaque(conversion).takeUnretainedValue().currentSegment.candidates.count
}

@_cdecl("mlh_conversion_candidate_index")
public func mlhConversionCandidateIndex(_ conversion: UnsafeMutableRawPointer) -> Int {
    Unmanaged<KanjiConversion>.fromOpaque(conversion).takeUnretainedValue().currentSegment.index
}

@_cdecl("mlh_conversion_segment_count")
public func mlhConversionSegmentCount(_ conversion: UnsafeMutableRawPointer) -> Int {
    Unmanaged<KanjiConversion>.fromOpaque(conversion).takeUnretainedValue().segments.count
}

@_cdecl("mlh_conversion_segment_length")
public func mlhConversionSegmentLength(_ conversion: UnsafeMutableRawPointer, _ index: Int) -> Int {
    let segments = Unmanaged<KanjiConversion>.fromOpaque(conversion).takeUnretainedValue().segments
    guard segments.indices.contains(index) else { return 0 }
    return segments[index].current.unicodeScalars.count
}

@_cdecl("mlh_conversion_segment_current")
public func mlhConversionSegmentCurrent(_ conversion: UnsafeMutableRawPointer) -> Int {
    Unmanaged<KanjiConversion>.fromOpaque(conversion).takeUnretainedValue().current
}

@_cdecl("mlh_conversion_candidate")
public func mlhConversionCandidate(_ conversion: UnsafeMutableRawPointer, _ index: Int) -> UnsafeMutablePointer<CChar>? {
    let candidates = Unmanaged<KanjiConversion>.fromOpaque(conversion).takeUnretainedValue().currentSegment.candidates
    guard candidates.indices.contains(index) else { return nil }
    return candidates[index].withCString { strdup($0) }
}

@_cdecl("mlh_conversion_select")
public func mlhConversionSelect(_ conversion: UnsafeMutableRawPointer, _ index: Int) {
    Unmanaged<KanjiConversion>.fromOpaque(conversion).takeUnretainedValue().selectCandidate(index)
}

@_cdecl("mlh_conversion_step")
public func mlhConversionStep(_ conversion: UnsafeMutableRawPointer, _ action: Int32) {
    let conversion = Unmanaged<KanjiConversion>.fromOpaque(conversion).takeUnretainedValue()
    switch action {
    case 0: conversion.nextCandidate()
    case 1: conversion.previousCandidate()
    case 2: conversion.forwardSegment()
    case 3: conversion.backwardSegment()
    case 4: conversion.firstSegment()
    case 5: conversion.lastSegment()
    case 6: conversion.shrinkSegment()
    case 7: conversion.enlargeSegment()
    default: break
    }
}

@_cdecl("mlh_string_free")
public func mlhStringFree(_ text: UnsafeMutablePointer<CChar>) {
    free(text)
}
