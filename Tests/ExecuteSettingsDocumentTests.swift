import Foundation
@testable import MLHCore

func runExecuteSettingsDocumentTests() -> (passed: Int, failed: Int) {
    var passed = 0
    var failed = 0
    func check(_ name: String, _ result: Bool) {
        if result {
            passed += 1
        } else {
            failed += 1
            print("FAIL: \(name)")
        }
    }

    let original = Data(#"""
        {"2":{"model":"old","instructions":"common","unknown":"keep"},
         "apps":{"com.slack":{"instructions":"casual","2":{"model":"app"},"other":42}},
         "opaque":{"nested":true}}
        """#.utf8)
    do {
        var document = try ExecuteSettingsDocument(data: original)
        check("list numbered keys", document.numberedKeys == ["2"])
        check("list apps", document.appIDs == ["com.slack"])
        check("list app numbered keys", document.numberedKeys(for: "com.slack") == ["2"])
        check("read existing merged settings", document.settings(for: "2", app: "com.slack") ==
              ExecuteSettings(model: "app", instructions: "common"))
        check("read direct entry without inherited fields", document.entry(for: "2", app: "com.slack") ==
              ExecuteSettings(model: "app"))
        try document.setSettings(ExecuteSettings(model: "new"), for: "2", app: nil)
        try document.setSettings(ExecuteSettings(instructions: "formal"), for: nil, app: "com.slack")
        let output = try document.encode()
        let root = try JSONSerialization.jsonObject(with: output) as? [String: Any]
        let entry = root?["2"] as? [String: Any]
        let app = (root?["apps"] as? [String: Any])?["com.slack"] as? [String: Any]
        check("edit selected numbered entry", entry?["model"] as? String == "new")
        check("preserve unknown entry field", entry?["unknown"] as? String == "keep")
        check("preserve unrelated root", (root?["opaque"] as? [String: Bool])?["nested"] == true)
        check("preserve app number", ((app?["2"] as? [String: String])?["model"]) == "app")
        check("preserve unknown app field", app?["other"] as? Int == 42)
        check("edit app base", app?["instructions"] as? String == "formal")
        check("read edited settings", document.settings(for: "2", app: nil) == ExecuteSettings(model: "new"))
    } catch {
        check("edit valid document: \(error)", false)
    }

    check("reject malformed JSON", (try? ExecuteSettingsDocument(data: Data("{".utf8))) == nil)
    do {
        var document = try ExecuteSettingsDocument(data: original)
        do {
            try document.setSettings(ExecuteSettings(model: "x"), for: nil, app: nil)
            check("reject missing target", false)
        } catch {
            check("reject missing target", true)
        }
    } catch {
        check("prepare missing-target test", false)
    }

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mlh-settings-document-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
        let url = directory.appendingPathComponent("execute.json")
        var document = try ExecuteSettingsDocument(data: original)
        try document.save(to: url)
        let first = try Data(contentsOf: url)
        check("save creates parent and file", first == (try document.encode()))
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
        try document.setSettings(ExecuteSettings(model: "saved"), for: "2", app: nil)
        try document.save(to: url)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        check("existing permissions preserved", mode?.intValue == 0o640)
        let saved = try ExecuteSettingsDocument(data: Data(contentsOf: url))
        check("save writes edited setting", saved.entry(for: "2", app: nil)?.model == "saved")
        check("save preserves unrelated app", saved.entry(for: "2", app: "com.slack")?.model == "app")
    } catch {
        check("save valid document: \(error)", false)
    }
    return (passed, failed)
}
