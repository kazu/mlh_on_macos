#if os(macOS)
import Foundation
import CryptoKit
import Darwin

public enum UpdateInstallError: Error, LocalizedError {
    case invalidChecksum
    case invalidBundle
    case invalidInstallation
    case superseded
    case unsupportedLocation
    case missingInstallation

    public var errorDescription: String? {
        switch self {
        case .invalidChecksum: "ダウンロードした dmg の検証に失敗しました。"
        case .invalidBundle: "dmg に含まれる mlh.app を検証できませんでした。"
        case .invalidInstallation: "現在の mlh.app の公開版情報を確認できませんでした。"
        case .superseded: "同じか新しい mlh が既に導入されています。設定画面を開き直して確認してください。"
        case .unsupportedLocation: "この場所の mlh は設定画面から更新できません。"
        case .missingInstallation: "更新先の mlh.app が見つかりません。"
        }
    }
}

public enum UpdateInstallLocation: String {
    case user
    case system

    public var destination: URL {
        switch self {
        case .user:
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Input Methods/mlh.app")
        case .system:
            URL(fileURLWithPath: "/Library/Input Methods/mlh.app")
        }
    }

    public static func installedApp(containing settingsBundle: URL) -> Self? {
        let parent = settingsBundle.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = parent.standardizedFileURL
        if app.path == user.destination.standardizedFileURL.path { return .user }
        if app.path == system.destination.standardizedFileURL.path { return .system }
        return nil
    }
}

public enum UpdateProcess {
    @discardableResult
    public static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "mlh-update", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "更新処理に失敗しました。"
            ])
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public enum UpdateInstaller {
    private static func metadata(_ bundleURL: URL) -> [String: Any]? {
        let info = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: info),
              let value = try? PropertyListSerialization.propertyList(from: data,
                                                                       format: nil) as? [String: Any] else {
            return nil
        }
        return value
    }

    private static func exchange(_ first: URL, _ second: URL) throws {
        let result = first.path.withCString { oldPath in
            second.path.withCString { newPath in
                renamex_np(oldPath, newPath, UInt32(RENAME_SWAP))
            }
        }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    /// The caller owns a private directory. Verify the copied bytes, never a user-writable source.
    public static func installDownloadedDMG(_ sourceDMG: URL, release: ReleaseInfo,
                                            at destination: URL, in privateDirectory: URL,
                                            systemOwned: Bool = false,
                                            afterPrivateCopy: (() throws -> Void)? = nil) throws {
        let files = FileManager.default
        guard sourceDMG.resolvingSymlinksInPath().path == sourceDMG.path,
              privateDirectory.resolvingSymlinksInPath().path == privateDirectory.path else {
            throw UpdateInstallError.unsupportedLocation
        }
        try files.createDirectory(at: privateDirectory, withIntermediateDirectories: false,
                                  attributes: [.posixPermissions: 0o700])
        let copiedDMG = privateDirectory.appendingPathComponent("release.dmg")
        try files.copyItem(at: sourceDMG, to: copiedDMG)
        guard copiedDMG.resolvingSymlinksInPath().path == copiedDMG.path else {
            throw UpdateInstallError.unsupportedLocation
        }
        try afterPrivateCopy?()
        try withMountedApp(from: copiedDMG, release: release, in: privateDirectory) { app in
            try install(app, at: destination, version: release.tag, systemOwned: systemOwned)
        }
    }

    public static func verifyDMG(_ dmg: URL, release: ReleaseInfo) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: dmg.path)
        guard (attributes[.size] as? NSNumber)?.int64Value == release.size else {
            throw UpdateInstallError.invalidChecksum
        }
        let file = try FileHandle(forReadingFrom: dmg)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty {
            hash.update(data: data)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == release.sha256 else { throw UpdateInstallError.invalidChecksum }
    }

    public static func withMountedApp<T>(from dmg: URL, release: ReleaseInfo,
                                         in directory: URL, _ body: (URL) throws -> T) throws -> T {
        try verifyDMG(dmg, release: release)
        let mount = directory.appendingPathComponent("mount")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try UpdateProcess.run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, dmg.path])
        defer { _ = try? UpdateProcess.run("/usr/bin/hdiutil", ["detach", mount.path]) }
        let app = mount.appendingPathComponent("mlh.app")
        try verifyApp(app, version: release.tag)
        return try body(app)
    }

    public static func verifyApp(_ app: URL, version: String) throws {
        guard let parsed = ReleaseVersion(version),
              version == "v\(parsed.major).\(parsed.minor).\(parsed.patch)",
              app.resolvingSymlinksInPath().path == app.path,
              let info = metadata(app),
              info["CFBundleIdentifier"] as? String == "com.github.kazu.inputmethod.mlh",
              info["CFBundleShortVersionString"] as? String == "\(parsed.major).\(parsed.minor).\(parsed.patch)",
              info["MLHBuildChannel"] as? String == "release" else {
            throw UpdateInstallError.invalidBundle
        }
        let settingsURL = app.appendingPathComponent("Contents/Resources/mlh-settings.app")
        guard let settings = metadata(settingsURL),
              settings["CFBundleIdentifier"] as? String == "com.github.kazu.inputmethod.mlh.settings",
              settings["CFBundleShortVersionString"] as? String == "\(parsed.major).\(parsed.minor).\(parsed.patch)",
              settings["MLHBuildChannel"] as? String == "release" else {
            throw UpdateInstallError.invalidBundle
        }
        try UpdateProcess.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        let binaries = [
            "Contents/MacOS/mlh",
            "Contents/Resources/mlh-settings.app/Contents/MacOS/mlh-settings",
            "Contents/Resources/mlh-settings.app/Contents/MacOS/mlh-settings-backend",
            "Contents/Resources/mlh-settings.app/Contents/MacOS/mlh-settings-tui"
        ]
        for binary in binaries {
            let path = app.appendingPathComponent(binary).path
            let architectures = try UpdateProcess.run("/usr/bin/lipo", ["-archs", path])
            let set = Set(architectures.split(whereSeparator: \.isWhitespace).map(String.init))
            guard set.contains("arm64"), set.contains("x86_64") else {
                throw UpdateInstallError.invalidBundle
            }
        }
    }

    /// Replaces only an already installed app. The caller must authorize system-wide writes.
    public static func install(_ source: URL, at destination: URL, version: String,
                               systemOwned: Bool = false,
                               beforeCommit: (() throws -> Void)? = nil,
                               afterCommit: (() throws -> Void)? = nil,
                               cleanupOld: ((URL) throws -> Void)? = nil) throws {
        let files = FileManager.default
        let parent = destination.deletingLastPathComponent()
        guard destination.lastPathComponent == "mlh.app",
              parent.resolvingSymlinksInPath().path == parent.path,
              destination.resolvingSymlinksInPath().path == destination.path else {
            throw UpdateInstallError.unsupportedLocation
        }
        // Keep one lock inode beside the destination; removing it would let waiting updaters split locks.
        let lock = parent.appendingPathComponent(".mlh.app.update.lock")
        let descriptor = lock.path.withCString { open($0, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600) }
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        guard files.fileExists(atPath: destination.path) else { throw UpdateInstallError.missingInstallation }
        guard let installed = metadata(destination),
              installed["CFBundleIdentifier"] as? String == "com.github.kazu.inputmethod.mlh" else {
            throw UpdateInstallError.invalidInstallation
        }
        let identity = BuildIdentity(version: installed["CFBundleShortVersionString"] as? String,
                                     channel: installed["MLHBuildChannel"] as? String)
        guard identity.isRelease, let current = identity.version else {
            throw UpdateInstallError.invalidInstallation
        }
        guard let requested = ReleaseVersion(version), requested > current else {
            throw UpdateInstallError.superseded
        }
        try verifyApp(source, version: version)
        let stage = parent.appendingPathComponent(".mlh.app.next-\(UUID().uuidString)")
        var exchanged = false
        do {
            try files.copyItem(at: source, to: stage)
            if systemOwned {
                try UpdateProcess.run("/usr/sbin/chown", ["-R", "root:wheel", stage.path])
                try UpdateProcess.run("/bin/chmod", ["-R", "go-w", stage.path])
            }
            try verifyApp(stage, version: version)
            // This release is not notarized; the documented dmg install removes quarantine.
            _ = try? UpdateProcess.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", stage.path])
            try beforeCommit?()
            // Both bundles exist on the same volume. The exchange has no interval with a missing destination.
            try exchange(stage, destination)
            exchanged = true
            try afterCommit?()
            try verifyApp(destination, version: version)
        } catch {
            var restored = !exchanged
            if exchanged {
                restored = (try? exchange(stage, destination)) != nil
            }
            if restored, files.fileExists(atPath: stage.path) { try? files.removeItem(at: stage) }
            throw error
        }
        // The new app is committed and verified. Cleanup cannot safely roll back a partly deleted old app.
        do {
            if let cleanupOld { try cleanupOld(stage) }
            else { try files.removeItem(at: stage) }
        } catch {
            NSLog("mlh update: previous app cleanup failed: %@", error.localizedDescription)
            if files.fileExists(atPath: stage.path) { try? files.removeItem(at: stage) }
        }
    }
}
#endif
