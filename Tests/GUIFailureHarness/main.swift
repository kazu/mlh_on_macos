import Foundation

let guiURL = URL(fileURLWithPath: CommandLine.arguments[1])
let backendURL = URL(fileURLWithPath: CommandLine.arguments[2])
let stateURL = URL(fileURLWithPath: CommandLine.arguments[3])

func runAppleScript(_ source: String) throws -> String {
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", source]
    process.standardOutput = output
    process.standardError = error
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "GUIFailureHarness", code: Int(process.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: String(data: errorData, encoding: .utf8) ?? "AppleScript failed"])
    }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func runOperation(_ operation: String) throws {
    try? FileManager.default.removeItem(at: stateURL)
    let reloadMarker = URL(fileURLWithPath: stateURL.path + ".reload-failed")
    try? FileManager.default.removeItem(at: reloadMarker)
    let reloadFailsOnce = operation.hasSuffix("-reload")
    let gui = Process()
    gui.executableURL = guiURL
    var environment = ProcessInfo.processInfo.environment
    environment["MLH_SETTINGS_BACKEND_PATH"] = backendURL.path
    environment["MLH_SETTINGS_FIXTURE_STATE"] = stateURL.path
    if reloadFailsOnce { environment["MLH_SETTINGS_FIXTURE_RELOAD_FAIL_ONCE"] = "1" }
    gui.environment = environment
    try gui.run()
    defer {
        gui.terminate()
        gui.waitUntilExit()
    }
    Thread.sleep(forTimeInterval: 1)
    let geometry = try runAppleScript("""
    tell application "System Events"
        tell (first application process whose unix id is \(gui.processIdentifier))
            set fieldOrigin to position of text field 1 of scroll area 2 of window 1
            set fieldSize to size of text field 1 of scroll area 2 of window 1
            set visibleOrigin to position of scroll area 2 of window 1
            set visibleSize to size of scroll area 2 of window 1
            return (item 1 of fieldOrigin as text) & "," & (item 2 of fieldOrigin as text) & "," & (item 1 of fieldSize as text) & "," & (item 2 of fieldSize as text) & "," & (item 1 of visibleOrigin as text) & "," & (item 2 of visibleOrigin as text) & "," & (item 1 of visibleSize as text) & "," & (item 2 of visibleSize as text)
        end tell
    end tell
    """)
    let dimensions = geometry.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    guard dimensions.count == 8 else {
        throw NSError(domain: "GUIFailureHarness", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "\(operation): invalid editor geometry: \(geometry)"])
    }
    let (fieldX, fieldY, fieldWidth, fieldHeight) = (dimensions[0], dimensions[1], dimensions[2], dimensions[3])
    let (visibleX, visibleY, visibleWidth, visibleHeight) = (dimensions[4], dimensions[5], dimensions[6], dimensions[7])
    guard fieldWidth >= 100, fieldHeight >= 20,
          fieldX < visibleX + visibleWidth, fieldX + fieldWidth > visibleX,
          fieldY < visibleY + visibleHeight, fieldY + fieldHeight > visibleY else {
        throw NSError(domain: "GUIFailureHarness", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "\(operation): editor is outside the visible settings area: \(geometry)"])
    }
    let trigger = operation.hasPrefix("save")
        ? "set value of text field 1 of scroll area 2 of window 1 to \"typed\"\n        click button \"保存\" of window 1"
        : "click button \"追加\" of scroll area 2 of window 1\n        delay 0.2\n        click button \"実行\" of window 1"
    let result = reloadFailsOnce
        ? "return (enabled of button \"保存\" of window 1 as text) & \",\" & (enabled of button \"追加\" of scroll area 2 of window 1 as text)"
        : "get value of text field 1 of scroll area 2 of window 1"
    let script = """
    tell application "System Events"
        tell (first application process whose unix id is \(gui.processIdentifier))
            \(trigger)
            delay 0.3
            click button 1 of window 1
            \(result)
        end tell
    end tell
    """
    let displayed = try runAppleScript(script)
    guard FileManager.default.fileExists(atPath: stateURL.path),
          displayed == (reloadFailsOnce ? "false,false" : "after") else {
        throw NSError(domain: "GUIFailureHarness", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "\(operation): unsafe GUI state after partial save: \(displayed)"])
    }
    if reloadFailsOnce {
        let reload = """
        tell application "System Events"
            tell (first application process whose unix id is \(gui.processIdentifier))
                click button "再読み込み" of window 1
                return (value of text field 1 of scroll area 2 of window 1) & "," & (enabled of button "保存" of window 1 as text) & "," & (enabled of button "追加" of scroll area 2 of window 1 as text)
            end tell
        end tell
        """
        let restored = try runAppleScript(reload)
        guard restored == "after,true,true" else {
            throw NSError(domain: "GUIFailureHarness", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "\(operation): reload did not restore editing: \(restored)"])
        }
    }
    print("\(operation): recovered after partial save")
}

var failures = 0
for operation in ["save", "action", "save-reload", "action-reload"] {
    do {
        try runOperation(operation)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        failures += 1
    }
}
try? FileManager.default.removeItem(at: stateURL)
try? FileManager.default.removeItem(atPath: stateURL.path + ".reload-failed")
exit(failures == 0 ? 0 : 1)
