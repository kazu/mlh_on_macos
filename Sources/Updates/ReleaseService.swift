import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct ReleaseVersion: Comparable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]),
              major >= 0, minor >= 0, patch >= 0,
              "\(major).\(minor).\(patch)" == value else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        [lhs.major, lhs.minor, lhs.patch].lexicographicallyPrecedes([rhs.major, rhs.minor, rhs.patch])
    }
}

public struct ReleaseInfo: Codable, Equatable, Sendable {
    public let tag: String
    public let assetURL: URL
    public let sha256: String
    public let size: Int64

    public var version: ReleaseVersion { ReleaseVersion(tag)! }

    private enum CodingKeys: String, CodingKey { case tag, assetURL, sha256, size }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(tag: values.decode(String.self, forKey: .tag),
                      assetURL: values.decode(URL.self, forKey: .assetURL),
                      sha256: values.decode(String.self, forKey: .sha256),
                      size: values.decode(Int64.self, forKey: .size))
    }

    public init(tag: String, assetURL: URL, sha256: String, size: Int64) throws {
        let assetPath = "/kazu/mlh_on_macos/releases/download/\(tag)/mlh-\(tag).dmg"
        let githubAsset = assetURL.scheme == "https" && assetURL.host == "github.com"
        #if MLH_TESTING
        let fixtureAsset = assetURL.scheme == "http" && ["127.0.0.1", "localhost"].contains(assetURL.host ?? "")
        let allowedAsset = githubAsset || fixtureAsset
        #else
        let allowedAsset = githubAsset
        #endif
        guard let version = ReleaseVersion(tag), tag == "v\(version.major).\(version.minor).\(version.patch)",
              size > 0, sha256.count == 64,
              sha256.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || (97...102).contains($0.value) }),
              assetURL.path == assetPath, allowedAsset else {
            throw ReleaseError.invalidRelease
        }
        self.tag = tag
        self.assetURL = assetURL
        self.sha256 = sha256
        self.size = size
    }
}

public enum ReleaseError: Error, LocalizedError {
    case invalidResponse
    case invalidRelease

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "リリース情報を取得できませんでした。"
        case .invalidRelease: "リリースの dmg または検証情報が正しくありません。"
        }
    }
}

public struct BuildIdentity: Sendable {
    public let version: ReleaseVersion?
    public let isRelease: Bool

    public init(version: String?, channel: String?) {
        self.version = version.flatMap(ReleaseVersion.init)
        self.isRelease = channel == "release" && self.version != nil
    }

    public init(bundle: Bundle) {
        self.init(version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  channel: bundle.object(forInfoDictionaryKey: "MLHBuildChannel") as? String)
    }

    public func hasUpdate(_ release: ReleaseInfo) -> Bool {
        isRelease && version.map { release.version > $0 } == true
    }
}

private struct APIRelease: Decodable {
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
    let assets: [APIAsset]
}

private struct APIAsset: Decodable {
    let name: String
    let browser_download_url: URL
    let digest: String?
    let size: Int64
}

public struct ReleaseService: Sendable {
    public static let latestURL = URL(string: "https://api.github.com/repos/kazu/mlh_on_macos/releases/latest")!
    private let endpoint: URL
    private let session: URLSession

    public init(endpoint: URL = Self.latestURL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public func latest() async throws -> ReleaseInfo {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("mlh-update-check", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 1_000_000 else {
            throw ReleaseError.invalidResponse
        }
        let release = try JSONDecoder().decode(APIRelease.self, from: data)
        guard !release.draft, !release.prerelease,
              let version = ReleaseVersion(release.tag_name),
              release.tag_name == "v\(version.major).\(version.minor).\(version.patch)",
              let asset = release.assets.first(where: { $0.name == "mlh-\(release.tag_name).dmg" }),
              let digest = asset.digest, digest.hasPrefix("sha256:") else {
            throw ReleaseError.invalidRelease
        }
        return try ReleaseInfo(tag: release.tag_name, assetURL: asset.browser_download_url,
                               sha256: String(digest.dropFirst("sha256:".count)), size: asset.size)
    }
}

public struct UpdateCheckRecord: Codable, Equatable {
    public var lastSuccess: Date?
    public var lastAttempt: Date?
    public var release: ReleaseInfo?
}

public struct UpdateCheckCache: Sendable {
    public let url: URL

    public init(url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/mlh/update-check.json")) {
        self.url = url
    }

    public func read() -> UpdateCheckRecord {
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(UpdateCheckRecord.self, from: data) else {
            return UpdateCheckRecord()
        }
        return record
    }

    public func shouldCheck(at now: Date) -> Bool {
        let record = read()
        guard let lastAttempt = record.lastAttempt else { return true }
        let interval: TimeInterval = record.lastSuccess == lastAttempt ? 24 * 60 * 60 : 60 * 60
        return now.timeIntervalSince(lastAttempt) >= interval
    }

    @discardableResult
    public func record(_ release: ReleaseInfo?, at now: Date,
                       afterRead: (() -> Void)? = nil) throws -> ReleaseInfo? {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lock = url.appendingPathExtension("lock")
        let descriptor = lock.path.withCString { open($0, O_CREAT | O_RDWR, 0o600) }
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        var value = read()
        afterRead?()
        if value.lastAttempt.map({ now > $0 }) ?? true { value.lastAttempt = now }
        if let release {
            if value.lastSuccess.map({ now >= $0 }) ?? true {
                value.lastSuccess = now
                value.release = release
            }
        }
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        return value.release
    }
}

public actor UpdateChecker {
    private let service: ReleaseService
    public let cache: UpdateCheckCache
    private var pending: Task<ReleaseInfo, Error>?

    public init(service: ReleaseService = ReleaseService(), cache: UpdateCheckCache = UpdateCheckCache()) {
        self.service = service
        self.cache = cache
    }

    public func checkIfDue(at now: Date = Date()) async throws -> ReleaseInfo? {
        guard cache.shouldCheck(at: now) else { return cache.read().release }
        return try await checkNow(at: now)
    }

    public func checkNow(at now: Date = Date()) async throws -> ReleaseInfo {
        if let pending { return try await pending.value }
        let service = self.service
        let task = Task { try await service.latest() }
        pending = task
        do {
            let release = try await task.value
            let adopted = try cache.record(release, at: now)
            pending = nil
            return adopted ?? release
        } catch {
            _ = try? cache.record(nil, at: now)
            pending = nil
            throw error
        }
    }
}
