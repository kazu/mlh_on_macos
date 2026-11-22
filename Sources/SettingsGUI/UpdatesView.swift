import AppKit
import Foundation
import MLHUpdates

final class UpdatesViewController: NSObject, URLSessionDownloadDelegate {
    let view: NSView
    var availabilityChanged: ((Bool) -> Void)?
    var hasAvailableUpdate: Bool { latestRelease.map(identity.hasUpdate) ?? false }

    private let identity: BuildIdentity
    private let cache: UpdateCheckCache
    private let checker: UpdateChecker
    private let currentLabel: NSTextField
    private let latestLabel: NSTextField
    private let statusLabel: NSTextField
    private let checkButton: NSButton
    private let installButton: NSButton
    private let progress: NSProgressIndicator
    private var latestRelease: ReleaseInfo?
    private var installedTag: String?
    private var downloadRelease: ReleaseInfo?
    private var downloadTask: URLSessionDownloadTask?
    private var downloadCancelled = false
    private var downloadSession: URLSession?
    private var workDirectory: URL?
    private var processing = false

    override init() {
        #if MLH_TESTING
        let environment = ProcessInfo.processInfo.environment
        identity = BuildIdentity(version: environment["MLH_UPDATE_TEST_VERSION"]
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                                 channel: environment["MLH_UPDATE_TEST_CHANNEL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "MLHBuildChannel") as? String)
        let cacheURL = environment["MLH_UPDATE_TEST_CACHE"].map { URL(fileURLWithPath: $0) }
        cache = UpdateCheckCache(url: cacheURL ?? UpdateCheckCache().url)
        let endpoint = environment["MLH_UPDATE_TEST_API_URL"].flatMap(URL.init(string:)) ?? ReleaseService.latestURL
        checker = UpdateChecker(service: ReleaseService(endpoint: endpoint), cache: cache)
        #else
        identity = BuildIdentity(bundle: .main)
        cache = UpdateCheckCache()
        checker = UpdateChecker()
        #endif

        let page = NSStackView()
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 18
        let heading = NSTextField(labelWithString: "アップデート")
        heading.font = .boldSystemFont(ofSize: 22)
        page.addArrangedSubview(heading)

        currentLabel = NSTextField(labelWithString: "")
        currentLabel.font = .systemFont(ofSize: 13, weight: .medium)
        page.addArrangedSubview(currentLabel)
        latestLabel = NSTextField(labelWithString: "公開版を確認していません。")
        page.addArrangedSubview(latestLabel)
        statusLabel = NSTextField(wrappingLabelWithString: "")
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.widthAnchor.constraint(equalToConstant: 400).isActive = true
        page.addArrangedSubview(statusLabel)

        checkButton = NSButton(title: "今すぐ確認", target: nil, action: nil)
        installButton = NSButton(title: "アップグレード…", target: nil, action: nil)
        installButton.bezelStyle = .rounded
        let buttons = NSStackView(views: [checkButton, installButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        page.addArrangedSubview(buttons)
        progress = NSProgressIndicator()
        progress.style = .bar
        progress.minValue = 0
        progress.maxValue = 100
        progress.widthAnchor.constraint(equalToConstant: 300).isActive = true
        progress.isHidden = true
        page.addArrangedSubview(progress)

        let warning = NSTextField(wrappingLabelWithString:
            "更新すると、現在開いているアプリと mlh の接続が切れる場合があります。作業を保存し、アプリと mlh を再起動できるときに実行してください。")
        warning.textColor = .secondaryLabelColor
        warning.widthAnchor.constraint(equalToConstant: 400).isActive = true
        page.addArrangedSubview(warning)
        view = page
        super.init()
        checkButton.target = self
        checkButton.action = #selector(checkNow)
        installButton.target = self
        installButton.action = #selector(upgrade)
        currentLabel.stringValue = identity.isRelease
            ? "現在のバージョン: \(identity.version.map { "\($0.major).\($0.minor).\($0.patch)" } ?? "不明")"
            : "開発版: 公開版への自動判定・置き換えは行いません。"
        present(cache.read().release)
    }

    func checkOnOpen() {
        guard identity.isRelease else { return }
        statusLabel.stringValue = "公開版を確認しています…"
        Task {
            do {
                let release = try await checker.checkIfDue()
                await MainActor.run { self.present(release) }
            } catch {
                await MainActor.run { self.statusLabel.stringValue = "確認できませんでした: \(error.localizedDescription)" }
            }
        }
    }

    @objc private func checkNow() {
        guard !processing, downloadTask == nil else { return }
        checkButton.isEnabled = false
        statusLabel.stringValue = "公開版を確認しています…"
        Task {
            do {
                let release = try await checker.checkNow()
                await MainActor.run {
                    self.present(release)
                    self.checkButton.isEnabled = true
                }
            } catch {
                await MainActor.run {
                    self.statusLabel.stringValue = "確認できませんでした: \(error.localizedDescription)"
                    self.checkButton.isEnabled = true
                }
            }
        }
    }

    private func present(_ release: ReleaseInfo?) {
        latestRelease = release
        latestLabel.stringValue = release.map { "最新の公開版: \($0.tag)" } ?? "公開版を確認していません。"
        let available = release.map(identity.hasUpdate) ?? false
        availabilityChanged?(available)
        installButton.isEnabled = available && installedTag != release?.tag && !processing && downloadTask == nil
        if !processing && downloadTask == nil {
            statusLabel.stringValue = identity.isRelease
                ? (release == nil ? "公開版を確認していません。"
                   : available ? "新しいバージョンを利用できます。" : "現在のバージョンが最新です。")
                : "開発版は公開版より新しい変更を含む場合があるため、ここから置き換えません。"
        }
    }

    @objc private func upgrade() {
        if let downloadTask {
            downloadCancelled = true
            downloadTask.cancel()
            statusLabel.stringValue = "ダウンロードを中止しています…"
            return
        }
        guard !processing, let release = latestRelease, identity.hasUpdate(release) else { return }
        #if MLH_TESTING
        let testDestination = ProcessInfo.processInfo.environment["MLH_UPDATE_TEST_DESTINATION"]
        #else
        let testDestination: String? = nil
        #endif
        guard testDestination != nil || UpdateInstallLocation.installedApp(containing: Bundle.main.bundleURL) != nil else {
            statusLabel.stringValue = UpdateInstallError.unsupportedLocation.localizedDescription
            return
        }
        let alert = NSAlert()
        alert.messageText = "\(release.tag) にアップグレードしますか？"
        alert.informativeText = "現在開いているアプリと mlh の接続が切れる場合があります。作業を保存し、再起動できるときに実行してください。"
        alert.addButton(withTitle: "アップグレード")
        alert.addButton(withTitle: "キャンセル")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches/mlh/update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            workDirectory = directory
            let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
            downloadSession = session
            let task = session.downloadTask(with: release.assetURL)
            task.taskDescription = directory.path
            downloadRelease = release
            downloadCancelled = false
            downloadTask = task
            checkButton.isEnabled = false
            installButton.title = "中止"
            installButton.isEnabled = true
            progress.isIndeterminate = true
            progress.isHidden = false
            progress.startAnimation(nil)
            statusLabel.stringValue = "dmg をダウンロードしています…"
            task.resume()
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        DispatchQueue.main.async {
            guard self.downloadTask === downloadTask else { return }
            if totalBytesExpectedToWrite > 0 {
                self.progress.isIndeterminate = false
                self.progress.doubleValue = Double(totalBytesWritten) * 100 / Double(totalBytesExpectedToWrite)
            } else {
                self.progress.isIndeterminate = true
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let path = downloadTask.taskDescription,
              let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200 else {
            DispatchQueue.main.async {
                guard self.downloadTask === downloadTask else { return }
                self.finish("dmg の取得に失敗しました。")
            }
            return
        }
        let directory = URL(fileURLWithPath: path)
        let dmg = directory.appendingPathComponent("release.dmg")
        do {
            try FileManager.default.copyItem(at: location, to: dmg)
        } catch {
            DispatchQueue.main.async {
                guard self.downloadTask === downloadTask else { return }
                self.finish(error.localizedDescription)
            }
            return
        }
        DispatchQueue.main.async {
            guard self.downloadTask === downloadTask else { return }
            guard !self.downloadCancelled, let release = self.downloadRelease else {
                self.finish("ダウンロードを中止しました。")
                return
            }
            self.downloadTask = nil
            self.processing = true
            self.installButton.isEnabled = false
            self.progress.isIndeterminate = true
            self.statusLabel.stringValue = "dmg とアプリを検証しています…"
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try UpdateInstaller.withMountedApp(from: dmg, release: release, in: directory) { app in
                        #if MLH_TESTING
                        if let path = ProcessInfo.processInfo.environment["MLH_UPDATE_TEST_DESTINATION"] {
                            try UpdateInstaller.install(app, at: URL(fileURLWithPath: path), version: release.tag)
                            return
                        }
                        #endif
                        try self.install(app, dmg: dmg, version: release.tag)
                    }
                    DispatchQueue.main.async {
                        self.finish("インストールしました。使用中の mlh とアプリを再起動すると反映されます。",
                                    installed: true)
                    }
                } catch {
                    DispatchQueue.main.async { self.finish("更新できませんでした: \(error.localizedDescription)") }
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        DispatchQueue.main.async {
            guard self.downloadTask === task else { return }
            self.finish((error as? URLError)?.code == .cancelled
                ? "ダウンロードを中止しました。" : "更新できませんでした: \(error.localizedDescription)")
        }
    }

    private func install(_ app: URL, dmg: URL, version: String) throws {
        guard let location = UpdateInstallLocation.installedApp(containing: Bundle.main.bundleURL) else {
            throw UpdateInstallError.unsupportedLocation
        }
        let backend = Bundle.main.executableURL!.deletingLastPathComponent()
            .appendingPathComponent("mlh-settings-backend")
        if location == .user {
            try UpdateProcess.run(backend.path, ["install-update", "user", app.path, version])
        } else {
            let script = """
            on run argv
                set toolPath to quoted form of (item 1 of argv)
                set appPath to quoted form of (item 2 of argv)
                set releaseTag to quoted form of (item 3 of argv)
                do shell script toolPath & " install-update system " & appPath & " " & releaseTag with administrator privileges
            end run
            """
            try UpdateProcess.run("/usr/bin/osascript", ["-e", script, backend.path, dmg.path, version])
        }
    }

    private func finish(_ message: String, installed: Bool = false) {
        if installed { installedTag = downloadRelease?.tag }
        downloadTask = nil
        downloadRelease = nil
        downloadCancelled = false
        processing = false
        downloadSession?.finishTasksAndInvalidate()
        downloadSession = nil
        if let workDirectory { try? FileManager.default.removeItem(at: workDirectory) }
        workDirectory = nil
        progress.stopAnimation(nil)
        progress.isHidden = true
        checkButton.isEnabled = true
        installButton.title = installedTag == latestRelease?.tag ? "インストール済み" : "アップグレード…"
        installButton.isEnabled = latestRelease.map { identity.hasUpdate($0) && installedTag != $0.tag } ?? false
        statusLabel.stringValue = message
    }
}
