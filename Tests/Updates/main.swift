import Foundation
#if canImport(MLHUpdates)
import MLHUpdates
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if os(macOS)
import Darwin
#endif

private func waitForFile(_ url: URL, seconds: TimeInterval = 15) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: url.path) { return true }
        Thread.sleep(forTimeInterval: 0.01)
    }
    return false
}

private func waitForFileAsync(_ url: URL, seconds: TimeInterval = 15) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: url.path) { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return false
}

private func startChild(_ arguments: [String], timeout: TimeInterval = 15) throws -> Process {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = arguments
    child.standardOutput = FileHandle.nullDevice
    child.standardError = FileHandle.nullDevice
    try child.run()
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
        if child.isRunning { child.terminate() }
    }
    return child
}

private func runChild(_ arguments: [String], timeout: TimeInterval = 15) throws -> Int32 {
    let child = try startChild(arguments, timeout: timeout)
    child.waitUntilExit()
    return child.terminationStatus
}

private func cacheRaceFixture(in directory: URL) throws -> Bool {
    let race = directory.appendingPathComponent("race.json")
    let raceCache = UpdateCheckCache(url: race)
    let old = try ReleaseInfo(tag: "v0.1.4",
                              assetURL: URL(string: "https://github.com/kazu/mlh_on_macos/releases/download/v0.1.4/mlh-v0.1.4.dmg")!,
                              sha256: String(repeating: "a", count: 64), size: 1)
    let newer = try ReleaseInfo(tag: "v0.1.6",
                                assetURL: URL(string: "https://github.com/kazu/mlh_on_macos/releases/download/v0.1.6/mlh-v0.1.6.dmg")!,
                                sha256: String(repeating: "b", count: 64), size: 1)
    try raceCache.record(old, at: Date(timeIntervalSince1970: 100))
    let ready = directory.appendingPathComponent("race.ready")
    let proceed = directory.appendingPathComponent("race.proceed")
    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = ["--cache-failure", race.path, ready.path, proceed.path]
    try child.run()
    guard waitForFile(ready) else {
        child.terminate()
        child.waitUntilExit()
        return false
    }
    let started = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        started.signal()
        _ = try? raceCache.record(newer, at: Date(timeIntervalSince1970: 400))
        finished.signal()
    }
    started.wait()
    Thread.sleep(forTimeInterval: 0.1)
    try Data().write(to: proceed)
    let completed = finished.wait(timeout: .now() + 15) == .success
    child.waitUntilExit()
    return completed && child.terminationStatus == 0 && raceCache.read().release == newer
}

private final class MockProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url!.lastPathComponent
        if path == "network" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        if path == "delayed-old",
           let gatePath = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "gate" })?.value {
            let gate = URL(fileURLWithPath: gatePath)
            try? Data().write(to: gate.appendingPathComponent("ready"))
            DispatchQueue.global().async {
                guard waitForFile(gate.appendingPathComponent("proceed"), seconds: 30) else {
                    self.client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
                    return
                }
                self.deliver(response(tag: "v0.1.5"), status: 200)
            }
            return
        }
        let data: Data
        switch path {
        case "badtag": data = response(tag: "v0.1.5-beta")
        case "noasset": data = response(asset: false)
        case "baddigest": data = response(digest: "wrong")
        case "newer": data = response(tag: "v0.1.6")
        default: data = response()
        }
        let status = path == "http-error" ? 500 : 200
        deliver(data, status: status)
    }

    private func deliver(_ data: Data, status: Int) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func response(tag: String = "v0.1.5", asset: Bool = true,
                      digest: String = String(repeating: "a", count: 64)) -> Data {
    let name = "mlh-\(tag).dmg"
    let assets: [[String: Any]] = asset ? [[
        "name": name, "browser_download_url": "https://github.com/kazu/mlh_on_macos/releases/download/\(tag)/\(name)",
        "digest": "sha256:\(digest)", "size": 31_000_000
    ]] : []
    return try! JSONSerialization.data(withJSONObject: [
        "tag_name": tag, "draft": false, "prerelease": false, "assets": assets
    ])
}

#if os(macOS)
private func installerFixture(_ arguments: [String]) -> Int {
    let dmg = URL(fileURLWithPath: arguments[1])
    let digest = arguments[2]
    let size = Int64(arguments[3])!
    let work = URL(fileURLWithPath: arguments[4])
    let files = FileManager.default
    let release = try! ReleaseInfo(tag: "v9.9.9",
                                   assetURL: URL(string: "https://github.com/kazu/mlh_on_macos/releases/download/v9.9.9/mlh-v9.9.9.dmg")!,
                                   sha256: digest, size: size)
    var failures = 0
    func check(_ condition: Bool, _ name: String) {
        if !condition { fputs("failed: \(name)\n", stderr); failures += 1 }
    }
    let wrong = try! ReleaseInfo(tag: release.tag, assetURL: release.assetURL,
                                 sha256: String(repeating: "0", count: 64), size: size)
    do { try UpdateInstaller.verifyDMG(dmg, release: wrong); check(false, "bad checksum") }
    catch { }
    do {
        try UpdateInstaller.withMountedApp(from: dmg, release: release, in: work) { app in
            let oldFixture = work.appendingPathComponent("old-fixture.app")
            try files.copyItem(at: app, to: oldFixture)
            for bundle in [oldFixture, oldFixture.appendingPathComponent("Contents/Resources/mlh-settings.app")] {
                let plist = bundle.appendingPathComponent("Contents/Info.plist")
                var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist),
                                                                      format: nil) as! [String: Any]
                info["CFBundleShortVersionString"] = "9.9.8"
                info["CFBundleVersion"] = "9.9.8"
                try PropertyListSerialization.data(fromPropertyList: info, format: .xml,
                                                   options: 0).write(to: plist)
            }
            try Data("old".utf8).write(to: oldFixture.appendingPathComponent("Contents/Resources/sentinel"))
            try UpdateProcess.run("/usr/bin/codesign", ["--force", "--sign", "-",
                oldFixture.appendingPathComponent("Contents/Resources/mlh-settings.app").path])
            try UpdateProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", oldFixture.path])
            func oldApp(_ destination: URL) throws {
                try files.createDirectory(at: destination.deletingLastPathComponent(),
                                          withIntermediateDirectories: true)
                try files.copyItem(at: oldFixture, to: destination)
            }
            for name in ["user", "system"] {
                let destination = work.appendingPathComponent("\(name)/Library/Input Methods/mlh.app")
                try oldApp(destination)
                let interrupted = try runChild(["--interrupt-install", app.path, destination.path,
                                                release.tag])
                check(interrupted == 73, "\(name) interrupted fixture reached commit")
                check(files.fileExists(atPath: destination.appendingPathComponent("Contents/Resources/sentinel").path),
                      "\(name) remains installed after interruption")
                do { try UpdateInstaller.install(app, at: destination, version: release.tag) }
                catch {
                    fputs("fixture \(name): destination=\(destination.path) resolved=\(destination.resolvingSymlinksInPath().path) parent=\(destination.deletingLastPathComponent().resolvingSymlinksInPath().path)\n", stderr)
                    throw error
                }
                check((try? UpdateInstaller.verifyApp(destination, version: release.tag)) != nil,
                      "\(name) installation")
                check(!files.fileExists(atPath: destination.appendingPathComponent("Contents/Resources/sentinel").path),
                      "\(name) old app replaced")
                try files.removeItem(at: destination)
                try oldApp(destination)
                let afterSwap = try runChild(["--interrupt-after-swap", app.path,
                                              destination.path, release.tag])
                check(afterSwap == 74, "\(name) after-swap fixture reached commit")
                check((try? UpdateInstaller.verifyApp(destination, version: release.tag)) != nil,
                      "\(name) new app remains after post-swap interruption")
                try files.removeItem(at: destination)
                try oldApp(destination)
                var cleanupReportedSuccess = false
                do {
                    try UpdateInstaller.install(app, at: destination, version: release.tag,
                                                cleanupOld: { previous in
                        try files.removeItem(at: previous.appendingPathComponent("Contents/Resources/sentinel"))
                        throw UpdateInstallError.invalidBundle
                    })
                    cleanupReportedSuccess = true
                } catch { }
                check(cleanupReportedSuccess, "\(name) partial old cleanup reports installed")
                check((try? UpdateInstaller.verifyApp(destination, version: release.tag)) != nil,
                      "\(name) partial old cleanup keeps complete new app")
                try files.removeItem(at: destination)
                try oldApp(destination)
                do {
                    try UpdateInstaller.install(app, at: destination, version: release.tag,
                                                beforeCommit: { throw UpdateInstallError.invalidBundle })
                    check(false, "rollback injection")
                } catch { }
                check(files.fileExists(atPath: destination.appendingPathComponent("Contents/Resources/sentinel").path),
                      "\(name) rollback preserved old app")
                try files.removeItem(at: destination)
                let real = destination.deletingLastPathComponent().appendingPathComponent("real.app")
                try oldApp(real)
                try files.createSymbolicLink(at: destination, withDestinationURL: real)
                do { try UpdateInstaller.install(app, at: destination, version: release.tag); check(false, "symlink target") }
                catch { }
                check(files.fileExists(atPath: real.appendingPathComponent("Contents/Resources/sentinel").path),
                      "symlink left original unchanged")
            }
            let next = work.appendingPathComponent("v9.9.10.app")
            try files.copyItem(at: app, to: next)
            for bundle in [next, next.appendingPathComponent("Contents/Resources/mlh-settings.app")] {
                let plist = bundle.appendingPathComponent("Contents/Info.plist")
                var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist),
                                                                      format: nil) as! [String: Any]
                info["CFBundleShortVersionString"] = "9.9.10"
                info["CFBundleVersion"] = "9.9.10"
                try PropertyListSerialization.data(fromPropertyList: info, format: .xml,
                                                   options: 0).write(to: plist)
            }
            try UpdateProcess.run("/usr/bin/codesign", ["--force", "--sign", "-",
                next.appendingPathComponent("Contents/Resources/mlh-settings.app").path])
            try UpdateProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", next.path])
            try UpdateInstaller.verifyApp(next, version: "v9.9.10")
            let concurrent = work.appendingPathComponent("concurrent/Library/Input Methods/mlh.app")
            try oldApp(concurrent)
            let firstMarker = work.appendingPathComponent("first-install")
            let secondMarker = work.appendingPathComponent("second-install")
            let first = try startChild(["--serial-install", app.path, concurrent.path,
                                        "v9.9.9", firstMarker.path], timeout: 90)
            let firstSwapped = waitForFile(URL(fileURLWithPath: firstMarker.path + ".swapped"),
                                           seconds: 30)
            check(firstSwapped, "first updater reached exchange")
            let second = try startChild(["--serial-install", next.path, concurrent.path,
                                         "v9.9.10", secondMarker.path], timeout: 90)
            let secondSwappedEarly = waitForFile(URL(fileURLWithPath: secondMarker.path + ".swapped"),
                                                  seconds: 12)
            try Data().write(to: URL(fileURLWithPath: firstMarker.path + ".release"))
            first.waitUntilExit()
            if !secondSwappedEarly {
                check(waitForFile(URL(fileURLWithPath: secondMarker.path + ".swapped"), seconds: 30),
                      "second updater reached exchange after first")
            }
            try Data().write(to: URL(fileURLWithPath: secondMarker.path + ".release"))
            second.waitUntilExit()
            check(first.terminationStatus == 0 && second.terminationStatus == 0,
                  "concurrent updaters complete in destination order")
            check((try? UpdateInstaller.verifyApp(concurrent, version: "v9.9.10")) != nil,
                  "concurrent destination contains later upgrade")
            try files.removeItem(at: concurrent)
            try oldApp(concurrent)
            let newerMarker = work.appendingPathComponent("newer-first")
            let olderMarker = work.appendingPathComponent("older-second")
            let newerFirst = try startChild(["--serial-install", next.path, concurrent.path,
                                             "v9.9.10", newerMarker.path], timeout: 90)
            check(waitForFile(URL(fileURLWithPath: newerMarker.path + ".swapped"), seconds: 30),
                  "newer updater reached exchange")
            let olderSecond = try startChild(["--serial-install", app.path, concurrent.path,
                                              "v9.9.9", olderMarker.path], timeout: 90)
            try Data().write(to: URL(fileURLWithPath: newerMarker.path + ".release"))
            newerFirst.waitUntilExit()
            let olderSwapped = waitForFile(URL(fileURLWithPath: olderMarker.path + ".swapped"),
                                           seconds: 12)
            if olderSwapped {
                try Data().write(to: URL(fileURLWithPath: olderMarker.path + ".release"))
            }
            olderSecond.waitUntilExit()
            check(newerFirst.terminationStatus == 0 && olderSecond.terminationStatus != 0,
                  "queued older update is rejected after newer commit")
            check((try? UpdateInstaller.verifyApp(concurrent, version: "v9.9.10")) != nil,
                  "queued older update leaves newer app installed")
            do {
                try UpdateInstaller.install(app, at: concurrent, version: "v9.9.9")
                check(false, "obsolete request rejected")
            } catch UpdateInstallError.superseded {
                check(UpdateInstallError.superseded.localizedDescription.contains("同じか新しい"),
                      "obsolete request explains installed newer version")
            } catch { check(false, "obsolete request reports precise error") }
            let development = work.appendingPathComponent("development/Library/Input Methods/mlh.app")
            try oldApp(development)
            let developmentInfo = development.appendingPathComponent("Contents/Info.plist")
            var developmentMetadata = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: developmentInfo), format: nil) as! [String: Any]
            developmentMetadata["MLHBuildChannel"] = "development"
            try PropertyListSerialization.data(fromPropertyList: developmentMetadata, format: .xml,
                                               options: 0).write(to: developmentInfo)
            try UpdateProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", development.path])
            do {
                try UpdateInstaller.install(app, at: development, version: "v9.9.9")
                check(false, "development installation rejected")
            } catch UpdateInstallError.invalidInstallation { }
            catch { check(false, "development installation reports precise error") }
            check(files.fileExists(atPath: development.appendingPathComponent(
                "Contents/Resources/sentinel").path), "development installation remains unchanged")
            let bad = work.appendingPathComponent("tampered.app")
            try files.copyItem(at: app, to: bad)
            let plist = bad.appendingPathComponent("Contents/Info.plist")
            try Data("broken".utf8).write(to: plist)
            do { try UpdateInstaller.verifyApp(bad, version: release.tag); check(false, "tampered app") }
            catch { }
        }
    } catch {
        fputs("failed: mounted fixture: \(error)\n", stderr)
        failures += 1
    }
    do {
        let mutableDMG = work.appendingPathComponent("mutable.dmg")
        try files.copyItem(at: dmg, to: mutableDMG)
        let destination = work.appendingPathComponent("privileged/Library/Input Methods/mlh.app")
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.copyItem(at: work.appendingPathComponent("old-fixture.app"), to: destination)
        try UpdateInstaller.installDownloadedDMG(mutableDMG, release: release, at: destination,
                                                 in: work.appendingPathComponent("private-copy"),
                                                 afterPrivateCopy: {
            try Data("tampered after private copy".utf8).write(to: mutableDMG)
        })
        check((try? UpdateInstaller.verifyApp(destination, version: release.tag)) != nil,
              "source replacement after private copy")
        try files.removeItem(at: destination)
        try files.copyItem(at: work.appendingPathComponent("old-fixture.app"), to: destination)
        do {
            try UpdateInstaller.installDownloadedDMG(mutableDMG, release: release, at: destination,
                                                     in: work.appendingPathComponent("private-bad"))
            check(false, "invalid source before private copy")
        } catch { }
        check(files.fileExists(atPath: destination.appendingPathComponent("Contents/Resources/sentinel").path),
              "invalid source preserved old app")
    } catch {
        fputs("failed: private copy fixture: \(error)\n", stderr)
        failures += 1
    }
    do {
        let destination = work.appendingPathComponent("denied/Library/Input Methods/mlh.app")
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.copyItem(at: work.appendingPathComponent("old-fixture.app"), to: destination)
        let parent = destination.deletingLastPathComponent()
        try files.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent.path)
        do {
            try UpdateInstaller.withMountedApp(from: dmg, release: release,
                                               in: work.appendingPathComponent("denied-mount")) { app in
                try UpdateInstaller.install(app, at: destination, version: release.tag)
            }
            check(false, "permission denied")
        } catch { }
        try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path)
        check(files.fileExists(atPath: destination.appendingPathComponent("Contents/Resources/sentinel").path),
              "permission failure preserved old app")
    } catch {
        fputs("failed: permission fixture: \(error)\n", stderr)
        failures += 1
    }
    return failures
}
#endif

@main
struct UpdateTests {
    static func main() async {
        let arguments = CommandLine.arguments
        if arguments.count == 5, arguments[1] == "--cache-failure" {
            let cache = UpdateCheckCache(url: URL(fileURLWithPath: arguments[2]))
            let ready = URL(fileURLWithPath: arguments[3])
            let proceed = URL(fileURLWithPath: arguments[4])
            do {
                try cache.record(nil, at: Date(timeIntervalSince1970: 300), afterRead: {
                    try? Data().write(to: ready)
                    _ = waitForFile(proceed)
                })
                exit(0)
            } catch { exit(2) }
        }
        #if os(macOS)
        if arguments.count == 2, arguments[1] == "--emit-stderr" {
            FileHandle.standardError.write(Data(repeating: 65, count: 1_000_000))
            FileHandle.standardOutput.write(Data("ok".utf8))
            exit(0)
        }
        if arguments.count == 2, arguments[1] == "--pipe-probe" {
            do {
                let output = try UpdateProcess.run(arguments[0], ["--emit-stderr"])
                exit(output.contains("ok") ? 0 : 2)
            } catch { exit(2) }
        }
        if arguments.count == 5, arguments[1] == "--interrupt-install" {
            do {
                try UpdateInstaller.install(URL(fileURLWithPath: arguments[2]),
                                            at: URL(fileURLWithPath: arguments[3]),
                                            version: arguments[4], beforeCommit: { _exit(73) })
                exit(2)
            } catch { exit(2) }
        }
        if arguments.count == 5, arguments[1] == "--interrupt-after-swap" {
            do {
                try UpdateInstaller.install(URL(fileURLWithPath: arguments[2]),
                                            at: URL(fileURLWithPath: arguments[3]),
                                            version: arguments[4], afterCommit: { _exit(74) })
                exit(2)
            } catch { exit(2) }
        }
        if arguments.count == 6, arguments[1] == "--serial-install" {
            let marker = arguments[5]
            do {
                try UpdateInstaller.install(URL(fileURLWithPath: arguments[2]),
                                            at: URL(fileURLWithPath: arguments[3]),
                                            version: arguments[4], afterCommit: {
                    try Data().write(to: URL(fileURLWithPath: marker + ".swapped"))
                    guard waitForFile(URL(fileURLWithPath: marker + ".release"), seconds: 75) else {
                        throw UpdateInstallError.invalidBundle
                    }
                })
                exit(0)
            } catch { exit(2) }
        }
        #endif
        var failures = 0
        func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
            if !condition() { fputs("failed: \(name)\n", stderr); failures += 1 }
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        let session = URLSession(configuration: config)
        func service(_ path: String) -> ReleaseService {
            ReleaseService(endpoint: URL(string: "https://api.github.com/\(path)")!, session: session)
        }
        let release = try! ReleaseInfo(tag: "v0.1.5",
                                       assetURL: URL(string: "https://github.com/kazu/mlh_on_macos/releases/download/v0.1.5/mlh-v0.1.5.dmg")!,
                                       sha256: String(repeating: "a", count: 64), size: 31_000_000)
        expect(ReleaseVersion("v0.1.5")! > ReleaseVersion("0.1.4")!, "semantic order")
        expect(ReleaseVersion("v0.1.5-beta") == nil, "prerelease rejected")
        expect(ReleaseVersion("v01.1.5") == nil, "noncanonical version rejected")
        expect(BuildIdentity(version: "0.1.4", channel: "release").hasUpdate(release), "newer release")
        expect(!BuildIdentity(version: "0.1.5", channel: "release").hasUpdate(release), "same release")
        expect(!BuildIdentity(version: "0.2.0", channel: "release").hasUpdate(release), "older release")
        expect(!BuildIdentity(version: "0.1.0", channel: "development").hasUpdate(release), "development build")

        do {
            let latest = try await service("good").latest()
            expect(latest == release, "latest release")
        }
        catch { expect(false, "latest release: \(error)") }
        for (name, path) in [
            ("invalid tag", "badtag"),
            ("missing asset", "noasset"),
            ("invalid digest", "baddigest")
        ] {
            do { _ = try await service(path).latest(); expect(false, name) }
            catch { }
        }
        do { _ = try await service("http-error").latest(); expect(false, "HTTP failure") }
        catch { }
        do { _ = try await service("network").latest(); expect(false, "network failure") }
        catch { }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mlh-update-tests-\(UUID().uuidString)")
        let cache = UpdateCheckCache(url: directory.appendingPathComponent("check.json"))
        let now = Date()
        expect(cache.shouldCheck(at: now), "first check due")
        try! cache.record(release, at: now)
        let secondProcess = UpdateCheckCache(url: cache.url)
        expect(secondProcess.read().release == release, "cross-process cache read")
        expect(!secondProcess.shouldCheck(at: now.addingTimeInterval(23 * 3600)), "daily limit")
        expect(secondProcess.shouldCheck(at: now.addingTimeInterval(24 * 3600)), "daily check due")
        try! cache.record(nil, at: now.addingTimeInterval(25 * 3600))
        expect(!secondProcess.shouldCheck(at: now.addingTimeInterval(25.5 * 3600)), "error retry delay")
        expect(secondProcess.shouldCheck(at: now.addingTimeInterval(26 * 3600)), "error retry due")
        let withdrawn = try! ReleaseInfo(tag: "v1.2.0",
                                         assetURL: URL(string: "https://github.com/kazu/mlh_on_macos/releases/download/v1.2.0/mlh-v1.2.0.dmg")!,
                                         sha256: String(repeating: "a", count: 64), size: 1)
        let replacement = try! ReleaseInfo(tag: "v1.1.9",
                                           assetURL: URL(string: "https://github.com/kazu/mlh_on_macos/releases/download/v1.1.9/mlh-v1.1.9.dmg")!,
                                           sha256: String(repeating: "b", count: 64), size: 1)
        try! cache.record(withdrawn, at: now.addingTimeInterval(27 * 3600))
        try! cache.record(replacement, at: now.addingTimeInterval(28 * 3600))
        expect(cache.read().release == replacement, "withdrawn release replaced by newer check")
        try! cache.record(withdrawn, at: now.addingTimeInterval(27.5 * 3600))
        expect(cache.read().release == replacement, "older completed check cannot restore withdrawal")
        do {
            let preserved = try cacheRaceFixture(in: directory)
            expect(preserved, "concurrent failure preserves newer release")
        }
        catch { expect(false, "cache race fixture: \(error)") }
        do {
            let gate = directory.appendingPathComponent("response-gate")
            try FileManager.default.createDirectory(at: gate, withIntermediateDirectories: true)
            var olderURL = URLComponents(string: "https://api.github.com/delayed-old")!
            olderURL.queryItems = [URLQueryItem(name: "gate", value: gate.path)]
            let responseCache = UpdateCheckCache(url: directory.appendingPathComponent("response.json"))
            let olderChecker = UpdateChecker(service: ReleaseService(endpoint: olderURL.url!,
                session: URLSession(configuration: config)), cache: responseCache)
            let newerChecker = UpdateChecker(service: ReleaseService(
                endpoint: URL(string: "https://api.github.com/newer")!,
                session: URLSession(configuration: config)), cache: responseCache)
            let olderTask = Task {
                try await olderChecker.checkNow(at: Date(timeIntervalSince1970: 100))
            }
            let ready = await waitForFileAsync(gate.appendingPathComponent("ready"))
            expect(ready, "older response held before newer check")
            let newer = try await newerChecker.checkNow(at: Date(timeIntervalSince1970: 200))
            try Data().write(to: gate.appendingPathComponent("proceed"))
            let shown = try await olderTask.value
            expect(shown == newer && responseCache.read().release == newer,
                   "older response returns adopted latest release")
        } catch { expect(false, "concurrent response fixture: \(error)") }
        try? FileManager.default.removeItem(at: directory)

        #if os(macOS)
        do {
            let result = try runChild(["--pipe-probe"], timeout: 5)
            expect(result == 0, "large stderr does not block")
        }
        catch { expect(false, "pipe fixture: \(error)") }
        let nested = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods/mlh.app/Contents/Resources/mlh-settings.app")
        expect(UpdateInstallLocation.installedApp(containing: nested) == .user,
               "user installation location")
        expect(UpdateInstallLocation.installedApp(containing: URL(fileURLWithPath:
            "/Library/Input Methods/mlh.app/Contents/Resources/mlh-settings.app")) == .system,
               "system installation location")
        if CommandLine.arguments.count == 5 { failures += installerFixture(CommandLine.arguments) }
        #endif

        print("updates: \(failures == 0 ? "passed" : "\(failures) failed")")
        exit(failures == 0 ? 0 : 1)
    }
}
