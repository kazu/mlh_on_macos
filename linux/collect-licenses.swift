import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let checkouts = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let files = FileManager.default

func output(_ command: String, _ arguments: [String]) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command] + arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "license collection: \(command) failed", code: Int(process.terminationStatus))
    }
    return data
}

func copyNotices(from source: URL, to name: String) throws {
    let notices = try files.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        .filter { file in ["LICENSE", "COPYING", "NOTICE"].contains { file.lastPathComponent.uppercased().hasPrefix($0) } }
    guard !notices.isEmpty else {
        throw NSError(domain: "no license notice in \(source.path)", code: 1)
    }
    let target = destination.appendingPathComponent(name, isDirectory: true)
    try files.createDirectory(at: target, withIntermediateDirectories: true)
    for notice in notices {
        let dest = target.appendingPathComponent(notice.lastPathComponent)
        if files.fileExists(atPath: dest.path) { try files.removeItem(at: dest) }
        try files.copyItem(at: notice, to: dest)
    }
}

let version = String(decoding: try output("rustc", ["-vV"]), as: UTF8.self)
let host = version.components(separatedBy: "\n").first { $0.hasPrefix("host: ") }!
    .dropFirst("host: ".count)
let metadata = try output("cargo", ["metadata", "--locked", "--format-version", "1", "--filter-platform", String(host), "--manifest-path", "linux/Cargo.toml"])
let json = try JSONSerialization.jsonObject(with: metadata) as! [String: Any]
for package in json["packages"] as! [[String: Any]] where !(package["source"] is NSNull) {
    let manifest = URL(fileURLWithPath: package["manifest_path"] as! String)
    try copyNotices(from: manifest.deletingLastPathComponent(), to: "rust/\(package["name"] as! String)-\(package["version"] as! String)")
}
for checkout in try files.contentsOfDirectory(at: checkouts, includingPropertiesForKeys: nil) {
    try copyNotices(from: checkout, to: "swift/\(checkout.lastPathComponent)")
}
