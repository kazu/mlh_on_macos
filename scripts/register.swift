// Registers ~/Library/Input Methods/MLH.app with Text Input Sources and
// enables the MLH input source.
//
// usage: swift scripts/register.swift [path/to/MLH.app]
import Carbon
import Foundation

let bundleID = "com.github.kazu.inputmethod.mlh"
let args = CommandLine.arguments
let appPath = args.count >= 2
    ? args[1]
    : (NSHomeDirectory() as NSString).appendingPathComponent("Library/Input Methods/MLH.app")

guard FileManager.default.fileExists(atPath: appPath) else {
    FileHandle.standardError.write("not found: \(appPath)\n".data(using: .utf8)!)
    exit(1)
}

let appURL = URL(fileURLWithPath: appPath)
let registerStatus = TISRegisterInputSource(appURL as CFURL)
print("TISRegisterInputSource(\(appPath)) -> \(registerStatus)\(registerStatus == noErr ? " (ok)" : "")")

func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool? {
    guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
}

func findSources() -> [TISInputSource] {
    let filter = [kTISPropertyBundleID as String: bundleID] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else {
        return []
    }
    return list
}

// Registration can take a moment to become visible.
var sources: [TISInputSource] = []
for attempt in 0..<10 {
    sources = findSources()
    if !sources.isEmpty { break }
    if attempt == 0 { print("waiting for the input source to appear...") }
    Thread.sleep(forTimeInterval: 0.5)
}

guard !sources.isEmpty else {
    FileHandle.standardError.write("input source \(bundleID) not found after registration\n".data(using: .utf8)!)
    exit(1)
}

var failed = false
for source in sources {
    let id = stringProperty(source, kTISPropertyInputSourceID) ?? "?"
    let name = stringProperty(source, kTISPropertyLocalizedName) ?? "?"
    if boolProperty(source, kTISPropertyInputSourceIsEnabled) == true {
        print("already enabled: \(id) (\(name))")
        continue
    }
    let status = TISEnableInputSource(source)
    print("TISEnableInputSource(\(id) \"\(name)\") -> \(status)\(status == noErr ? " (ok)" : "")")
    if status != noErr { failed = true }
}
exit(failed ? 1 : 0)
