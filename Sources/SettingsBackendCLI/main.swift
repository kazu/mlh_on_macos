import Foundation
import MLHCore
import MLHUpdates
#if canImport(Security)
import Security
#endif

private let domain = "com.github.kazu.inputmethod.mlh"

private func makeStore() -> SettingsStore {
    let environment = ProcessInfo.processInfo.environment
    #if os(Linux)
    let base = environment["XDG_CONFIG_HOME"]
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config").path
    let executeURL = URL(fileURLWithPath: LinuxSettings.resolve("MLH_EXEC_CONFIG", environment: environment).value
                             ?? "\(base)/mlh/execute.json")
    let commandURL = URL(fileURLWithPath: LinuxSettings.resolve("MLH_EXEC_COMMAND", environment: environment).value
                             ?? "\(base)/mlh/execute")
    let userDictionaryURL = URL(fileURLWithPath: LinuxSettings.resolve("MLH_USER_DICTIONARY", environment: environment).value
                                 ?? "\(base)/mlh/userdict.txt")
    let apiKeyPresent = environment["OPENAI_API_KEY"] != nil
    let secretStatus = apiKeyPresent ? LinuxSecretStore.Status(available: false, hasValue: false, error: nil)
        : LinuxSecretStore.status()
    let secretAvailable = secretStatus.available
    let secretPresent = secretStatus.hasValue
    let defaults = UserDefaults.standard
    #else
    let executeURL = ExecuteFile.defaultURL
    let userDictionaryURL = UserDictionary.defaultURL
    let commandURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/mlh/execute")
    let apiKeyPresent = hasAPIKey()
    let secretAvailable = false
    let secretPresent = false
    let defaults = UserDefaults(suiteName: domain)!
    #endif
    return SettingsStore(defaults: defaults, environment: environment,
                         executeURL: executeURL, userDictionaryURL: userDictionaryURL,
                         apiKeyPresent: apiKeyPresent,
                         commandAvailable: FileManager.default.isExecutableFile(atPath: commandURL.path),
                         apiKeySecretAvailable: secretAvailable,
                         apiKeySecretPresent: secretPresent)
}

#if canImport(Security)
private func hasAPIKey() -> Bool {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: "mlh-openai",
                                kSecMatchLimit as String: kSecMatchLimitOne]
    return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
}

private func writeAPIKey(_ value: String?) throws {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: "mlh-openai"]
    let status: OSStatus
    if let value {
        let data = Data(value.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var item = query
            item[kSecAttrAccount as String] = "mlh"
            item[kSecValueData as String] = data
            status = SecItemAdd(item as CFDictionary, nil)
        } else {
            status = update
        }
    } else {
        let deletion = SecItemDelete(query as CFDictionary)
        status = deletion == errSecItemNotFound ? errSecSuccess : deletion
    }
    guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
}
#else
private func writeAPIKey(_ value: String?) throws {
    try LinuxSecretStore.write(value)
}
#endif

do {
    let command = CommandLine.arguments.dropFirst().first
    switch command {
    case "snapshot":
        let snapshot = try makeStore().snapshot()
        FileHandle.standardOutput.write(try JSONEncoder().encode(snapshot))
    case "apply":
        let request = try JSONDecoder().decode(SettingsApplyRequest.self,
                                                from: FileHandle.standardInput.readDataToEndOfFile())
        try makeStore().apply(request, writeAPIKey: writeAPIKey)
        FileHandle.standardOutput.write(try JSONEncoder().encode(makeStore().snapshot()))
    #if os(macOS)
    case "install-update":
        let arguments = Array(CommandLine.arguments.dropFirst())
        #if MLH_TESTING
        let testSystemDestination = ProcessInfo.processInfo.environment["MLH_UPDATE_TEST_SYSTEM_DESTINATION"]
            .map { URL(fileURLWithPath: $0) }
        let testEndpoint = ProcessInfo.processInfo.environment["MLH_UPDATE_TEST_API_URL"]
            .flatMap(URL.init(string:))
        #else
        let testSystemDestination: URL? = nil
        let testEndpoint: URL? = nil
        #endif
        guard arguments.count == 4,
              let location = UpdateInstallLocation(rawValue: arguments[1]),
              arguments[3].hasPrefix("v"), ReleaseVersion(arguments[3]) != nil,
              (location == .system ? geteuid() == 0 || testSystemDestination != nil : geteuid() != 0) else {
            throw UpdateInstallError.unsupportedLocation
        }
        let destination = location == .system ? (testSystemDestination ?? location.destination) : location.destination
        guard let installed = Bundle(url: destination) else { throw UpdateInstallError.invalidBundle }
        let identity = BuildIdentity(bundle: installed)
        guard identity.isRelease,
              let current = identity.version,
              let requested = ReleaseVersion(arguments[3]), requested > current else {
            throw UpdateInstallError.invalidBundle
        }
        if location == .system {
            let release = try await ReleaseService(endpoint: testEndpoint ?? ReleaseService.latestURL).latest()
            guard release.tag == arguments[3] else { throw UpdateInstallError.invalidBundle }
            #if MLH_TESTING
            let testPrivateDirectory = ProcessInfo.processInfo.environment["MLH_UPDATE_TEST_PRIVATE_DIRECTORY"]
                .map { URL(fileURLWithPath: $0) }
            #else
            let testPrivateDirectory: URL? = nil
            #endif
            let privateDirectory = testPrivateDirectory
                ?? URL(fileURLWithPath: "/private/var/tmp/mlh-update-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: privateDirectory) }
            try UpdateInstaller.installDownloadedDMG(URL(fileURLWithPath: arguments[2]), release: release,
                                                     at: destination, in: privateDirectory,
                                                     systemOwned: testSystemDestination == nil)
        } else {
            try UpdateInstaller.install(URL(fileURLWithPath: arguments[2]),
                                        at: destination, version: arguments[3])
        }
    #endif
    default:
        throw NSError(domain: "mlh-settings-backend", code: 64,
                      userInfo: [NSLocalizedDescriptionKey: "usage: mlh-settings-backend snapshot|apply"])
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
