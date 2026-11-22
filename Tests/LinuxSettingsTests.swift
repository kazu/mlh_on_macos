import Foundation
@testable import MLHCore

func runLinuxSettingsTests() -> (passed: Int, failed: Int) {
    var passed = 0
    var failed = 0
    func check(_ name: String, _ okay: Bool) {
        if okay { passed += 1 } else { failed += 1; print("FAIL: \(name)") }
    }
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let env = ["XDG_CONFIG_HOME": base.path]
    let path = LinuxSettings.url(environment: env)
    check("empty file defaults", LinuxSettings.resolve("MLH_OPENAI_MODEL", environment: env).value == nil)
    do {
        try LinuxSettings.save(["MLH_OPENAI_MODEL": "stored", "MLH_EXEC_BACKEND": ""], environment: env)
        check("settings file exists", FileManager.default.fileExists(atPath: path.path))
        let stored = LinuxSettings.resolve("MLH_OPENAI_MODEL", environment: env)
        check("stored value and origin", stored.value == "stored" && stored.origin == .file)
        let pinned = LinuxSettings.resolve("MLH_OPENAI_MODEL", environment: env,
                                           persisted: ["MLH_OPENAI_MODEL": "snapshot"])
        check("snapshot uses supplied generation", pinned.value == "snapshot" && pinned.origin == .file)
        let pinnedOverride = LinuxSettings.resolve("MLH_OPENAI_MODEL",
                                                   environment: env.merging(["MLH_OPENAI_MODEL": ""]) { _, new in new },
                                                   persisted: ["MLH_OPENAI_MODEL": "snapshot"])
        check("snapshot keeps environment priority", pinnedOverride.value == "" && pinnedOverride.origin == .environment)
        let overridden = LinuxSettings.resolve("MLH_OPENAI_MODEL", environment: env.merging(["MLH_OPENAI_MODEL": ""]) { _, new in new })
        check("empty environment wins", overridden.value == "" && overridden.origin == .environment)
        try LinuxSettings.save(["MLH_OPENAI_MODEL": nil], environment: env)
        check("reset removes key", LinuxSettings.resolve("MLH_OPENAI_MODEL", environment: env).value == nil)
        check("other key retained", LinuxSettings.resolve("MLH_EXEC_BACKEND", environment: env).value == "")
        let unknown = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
        var updated = unknown
        updated["futureOption"] = "keep"
        try JSONSerialization.data(withJSONObject: updated).write(to: path)
        try LinuxSettings.save(["MLH_OPENAI_MODEL": "new"], environment: env)
        let retained = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
        check("unknown JSON retained", retained["futureOption"] as? String == "keep")
        do {
            try LinuxSettings.save(["UNSUPPORTED_SETTING": "x"], environment: env)
            check("unsupported key rejected", false)
        } catch {
            check("unsupported key rejected", true)
        }
        try Data("{ broken".utf8).write(to: path)
        do {
            try LinuxSettings.save(["MLH_OPENAI_MODEL": "new"], environment: env)
            check("malformed file rejected", false)
        } catch {
            check("malformed file rejected", true)
        }
        check("malformed file retained", try String(contentsOf: path, encoding: .utf8) == "{ broken")
        check("environment works despite malformed file", LinuxSettings.resolve("MLH_OPENAI_MODEL", environment: env.merging(["MLH_OPENAI_MODEL": "process"]) { _, new in new }).value == "process")
        try FileManager.default.removeItem(at: path)
        let target = base.appendingPathComponent("real-settings.json")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: target)
        try LinuxSettings.save(["MLH_OPENAI_MODEL": "linked"], environment: env)
        check("symlink retained", (try? FileManager.default.destinationOfSymbolicLink(atPath: path.path)) != nil)
        check("symlink target updated", try String(contentsOf: target, encoding: .utf8).contains("linked"))
    } catch {
        check("settings read/write", false)
    }
    return (passed, failed)
}
