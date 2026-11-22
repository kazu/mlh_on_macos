import Foundation

/// A value and the source that supplied it to the running input method.
public enum SettingsOrigin: String {
    case environment, userDefaults, file, keychain, secretService, automatic
}

public struct ResolvedSetting<Value> {
    public typealias Origin = SettingsOrigin

    public let value: Value
    public let origin: Origin

    public init(value: Value, origin: Origin) {
        self.value = value
        self.origin = origin
    }
}

public enum ExecuteBackend: String {
    case command, openai

    /// Matches the IME's existing explicit-selection and automatic fallback rules.
    public static func resolve(
        configuredName: String?, configuredOrigin: ResolvedSetting<ExecuteBackend?>.Origin,
        commandAvailable: @autoclosure () -> Bool, apiKeyAvailable: @autoclosure () -> Bool
    ) -> ResolvedSetting<ExecuteBackend?> {
        if let configuredName {
            return ResolvedSetting(value: ExecuteBackend(rawValue: configuredName), origin: configuredOrigin)
        }
        if commandAvailable() { return ResolvedSetting(value: .command, origin: .automatic) }
        if apiKeyAvailable() { return ResolvedSetting(value: .openai, origin: .automatic) }
        return ResolvedSetting(value: nil, origin: .automatic)
    }
}

public enum KanjiBackend: String {
    case azookey, google

    public static func resolve(configuredName: String?, origin: ResolvedSetting<KanjiBackend>.Origin)
        -> ResolvedSetting<KanjiBackend> {
        if let configuredName {
            return ResolvedSetting(value: configuredName == "google" ? .google : .azookey,
                                   origin: origin)
        }
        return ResolvedSetting(value: .azookey, origin: .automatic)
    }
}

public enum ZenzaiSettings {
    public static func integer(_ key: String, defaults: UserDefaults = .standard) -> ResolvedSetting<Int?> {
        guard defaults.object(forKey: key) != nil else {
            return ResolvedSetting(value: nil, origin: .automatic)
        }
        return ResolvedSetting(value: defaults.integer(forKey: key), origin: .userDefaults)
    }

    public static func modelPath(defaults: UserDefaults = .standard,
                                 home: URL = FileManager.default.homeDirectoryForCurrentUser)
        -> ResolvedSetting<String> {
        if let path = defaults.string(forKey: "ZenzaiModel") {
            return ResolvedSetting(value: (path as NSString).expandingTildeInPath, origin: .userDefaults)
        }
        return ResolvedSetting(value: home.appendingPathComponent("Library/Application Support/mlh/zenz.gguf").path,
                               origin: .automatic)
    }
}
