import Foundation

public struct SettingsSection: Codable {
    public let id: String
    public let label: String
}

public struct SettingsOption: Codable {
    public let value: String
    public let label: String
}

public struct SettingsField: Codable {
    public let id: String
    public let section: String
    public let label: String
    public let kind: String
    public let value: String?
    public let origin: String
    public let options: [SettingsOption]
    public let editable: Bool
    public let description: String
    public let has_value: Bool
}

public struct SettingsActionInput: Codable {
    public let id: String
    public let label: String
    public let kind: String
}

public struct SettingsAction: Codable {
    public let id: String
    public let section: String
    public let label: String
    public let inputs: [SettingsActionInput]
}

public struct SettingsSnapshot: Codable {
    public let schema: Int
    public let sections: [SettingsSection]
    public let fields: [SettingsField]
    public let actions: [SettingsAction]
}

public struct SettingsChange: Codable {
    public let id: String
    public let op: String
    public let value: String?
}

public struct SettingsActionRequest: Codable {
    public let id: String
    public let values: [String: String]
}

public struct SettingsApplyRequest: Codable {
    public let schema: Int
    public let changes: [SettingsChange]
    public let actions: [SettingsActionRequest]
}

public struct SettingsStore {
    public enum StoreError: LocalizedError {
        case unsupportedSchema, unknownField, invalidOperation, invalidValue, unsupportedAction, secretUnavailable

        public var errorDescription: String? {
            switch self {
            case .unsupportedSchema: return "設定データの形式が対応していません。"
            case .unknownField: return "設定項目が見つかりません。"
            case .invalidOperation: return "この変更は適用できません。環境変数で指定された項目は画面から変更できません。"
            case .invalidValue: return "設定値を確認してください。"
            case .unsupportedAction: return "この操作は対応していません。"
            case .secretUnavailable: return "Secret Service を利用できません。対応サービスの状態を確認してください。"
            }
        }
    }
    public let defaults: UserDefaults
    public let environment: [String: String]
    public let executeURL: URL
    public let userDictionaryURL: URL
    public let apiKeyPresent: Bool
    public let apiKeySecretAvailable: Bool
    public let apiKeySecretPresent: Bool
    public let commandAvailable: Bool

    public init(defaults: UserDefaults, environment: [String: String], executeURL: URL,
                userDictionaryURL: URL,
                apiKeyPresent: Bool, commandAvailable: Bool,
                apiKeySecretAvailable: Bool = false, apiKeySecretPresent: Bool = false) {
        self.defaults = defaults
        self.environment = environment
        self.executeURL = executeURL
        self.userDictionaryURL = userDictionaryURL
        self.apiKeyPresent = apiKeyPresent
        self.apiKeySecretAvailable = apiKeySecretAvailable
        self.apiKeySecretPresent = apiKeySecretPresent
        self.commandAvailable = commandAvailable
    }

    #if os(Linux)
    private var linuxBasePath: String {
        environment["XDG_CONFIG_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config").path
    }
    #endif

    public func snapshot() throws -> SettingsSnapshot {
        #if os(Linux)
        let linuxConfig = try? LinuxSettings.load(environment: environment)
        let linuxConfigError = linuxConfig == nil
        let persisted = linuxConfig ?? [:]
        #endif
        var fields: [SettingsField] = []
        func field(_ id: String, _ section: String, _ label: String, _ kind: String,
                   _ value: String?, _ origin: SettingsOrigin, _ description: String = "",
                   _ options: [SettingsOption] = [], _ editable: Bool = true,
                   _ hasValue: Bool = false) {
            #if os(Linux)
            let canEdit = editable && origin != .environment
            #else
            let canEdit = editable
            #endif
            fields.append(SettingsField(id: id, section: section, label: label, kind: kind,
                                        value: value, origin: origin == .automatic ? "default" : origin.rawValue,
                                        options: options, editable: canEdit, description: description,
                                        has_value: hasValue))
        }
        func options(_ names: [String]) -> [SettingsOption] {
            names.map { SettingsOption(value: $0, label: $0) }
        }

        #if os(Linux)
        let backendName = LinuxSettings.resolve("MLH_EXEC_BACKEND", environment: environment, persisted: persisted)
        let openAI = OpenAI.Config.resolved(defaults: defaults, environment: environment,
                                           persisted: persisted)
        let kanjiName = LinuxSettings.resolve("MLH_TRANSLITERATOR", environment: environment, persisted: persisted)
        let kanji = KanjiBackend.resolve(configuredName: kanjiName.value, origin: kanjiName.origin)
        #else
        let rawBackend = defaults.string(forKey: "ExecuteBackend")
        let backendName = ResolvedSetting<String?>(value: rawBackend,
                                                  origin: rawBackend == nil ? .automatic : .userDefaults)
        let openAI = OpenAI.Config.resolved(defaults: defaults)
        let rawKanji = defaults.string(forKey: "KanjiBackend")
        let kanji = KanjiBackend.resolve(configuredName: rawKanji, origin: .userDefaults)
        #endif

        let backend = ExecuteBackend.resolve(configuredName: backendName.value,
                                             configuredOrigin: backendName.origin,
                                             commandAvailable: commandAvailable,
                                             apiKeyAvailable: apiKeyPresent)
        field("execute.backend", "execute", "実行方式", "select",
              backendName.value ?? "auto", backend.origin,
              "x/ で使用する処理。自動の場合はコマンド、次に OpenAI を探します。",
              options(["auto", "command", "openai"]))
        field("openai.baseURL", "openai", "API URL", "text", openAI.baseURL.value,
              openAI.baseURL.origin)
        field("openai.model", "openai", "モデル", "text", openAI.model.value,
              openAI.model.origin)
        field("openai.instructions", "openai", "指示文", "multiline",
              openAI.instructions.value, openAI.instructions.origin)
        field("openai.reasoningEffort", "openai", "推論の強さ", "text",
              openAI.reasoningEffort.value, openAI.reasoningEffort.origin)
        #if os(macOS)
        let secretOrigin: SettingsOrigin = apiKeyPresent ? .keychain : .automatic
        #else
        let secretOrigin: SettingsOrigin = apiKeyPresent ? .environment
            : (apiKeySecretPresent ? .secretService : .automatic)
        #endif
        #if os(Linux)
        let secretDescription = apiKeyPresent ? "環境変数 OPENAI_API_KEY が優先されます。値は表示しません。"
            : (apiKeySecretAvailable ? "Secret Service に保存します。値は表示しません。"
                : "Secret Service を利用できません。キーの設定には対応サービスが必要です。")
        let secretEditable = apiKeySecretAvailable && !apiKeyPresent
        let secretHasValue = apiKeyPresent || apiKeySecretPresent
        #else
        let secretDescription = "値は画面に表示しません。"
        let secretEditable = true
        let secretHasValue = apiKeyPresent
        #endif
        field("openai.apiKey", "openai", "API キー", "secret", nil,
              secretOrigin, secretDescription, [], secretEditable, secretHasValue)
        field("kanji.backend", "kanji", "漢字変換", "select", kanji.value.rawValue,
              kanji.origin, "", options(["azookey", "google"]))
        #if os(Linux)
        if linuxConfigError {
            field("linux.configError", "system", "settings.json", "text",
                  "設定ファイルを読み取れません。内容を確認してください。", .file,
                  "設定ファイルは上書きしません。", [], false)
        }
        #endif
        #if os(Linux)
        let base = linuxBasePath
        let configPath = LinuxSettings.resolve("MLH_EXEC_CONFIG", environment: environment, persisted: persisted)
        field("execute.configPath", "execute", "番号別設定ファイル", "text",
              configPath.value ?? "\(base)/mlh/execute.json", configPath.origin)
        let commandPath = LinuxSettings.resolve("MLH_EXEC_COMMAND", environment: environment, persisted: persisted)
        field("execute.commandPath", "execute", "外部コマンド", "text",
              commandPath.value ?? "\(base)/mlh/execute", commandPath.origin)
        let systemDictionary = LinuxSettings.resolve("MLH_DICTIONARY", environment: environment, persisted: persisted)
        field("dictionary.systemPath", "dictionary", "azooKey 辞書の場所", "text",
              systemDictionary.value, systemDictionary.origin)
        let userPath = LinuxSettings.resolve("MLH_USER_DICTIONARY", environment: environment, persisted: persisted)
        field("dictionary.userPath", "dictionary", "ユーザー辞書の保存先", "text",
              userPath.value ?? userDictionaryURL.path, userPath.origin)
        #endif
        let dictionaryExists = FileManager.default.fileExists(atPath: userDictionaryURL.path)
        let dictionaryText = dictionaryExists
            ? try String(contentsOf: userDictionaryURL, encoding: .utf8) : ""
        field("dictionary.entries", "dictionary", "ユーザー辞書", "multiline",
              dictionaryText, dictionaryExists ? .file : .automatic,
              "1 行に『読み<TAB>候補』を入力します。")

        #if os(macOS)
        let model = ZenzaiSettings.modelPath(defaults: defaults)
        field("zenzai.model", "zenzai", "モデルファイル", "text", model.value, model.origin)
        let context = ZenzaiSettings.integer("ZenzaiContextLength", defaults: defaults)
        field("zenzai.contextLength", "zenzai", "文脈の長さ", "integer",
              context.value.map(String.init) ?? "40", context.origin)
        let inference = ZenzaiSettings.integer("ZenzaiInferenceLimit", defaults: defaults)
        field("zenzai.inferenceLimit", "zenzai", "推論回数", "integer",
              inference.value.map(String.init) ?? "10", inference.origin)
        for (id, key, label) in [
            ("compat.syntheticDeletionApps", "SyntheticDeletionApps", "文字削除を模擬するアプリ"),
            ("compat.replacementRangeApps", "ReplacementRangeApps", "置換範囲を使うアプリ")
        ] {
            let array = defaults.stringArray(forKey: key)
            field(id, "compat", label, "list", array?.joined(separator: "\n") ?? "",
                  array == nil ? .automatic : .userDefaults)
        }
        #endif

        var actions: [SettingsAction] = []
        func addEntry(_ document: ExecuteSettingsDocument, _ key: String?, _ app: String?) {
            let effective = document.settings(for: key, app: app) ?? ExecuteSettings()
            let direct = document.entry(for: key, app: app) ?? ExecuteSettings()
            let prefix = Self.entryID(key: key, app: app)
            let name = app.map { "\($0) / \(key ?? "x/")" } ?? "\(key ?? "")x/"
            for (property, label, kind) in [
                ("backend", "処理方式", "select"), ("command", "コマンド", "text"),
                ("baseURL", "API URL", "text"), ("model", "モデル", "text"),
                ("instructions", "指示文", "multiline"), ("reasoningEffort", "推論の強さ", "text")
            ] {
                let value = Self.entryValue(effective, property)
                let own = Self.entryValue(direct, property)
                field("\(prefix).\(property)", "execute", "\(name): \(label)", kind,
                      value, own == nil ? (value == nil ? .automatic : .file) : .file,
                      own == nil && value != nil ? "共通設定を継承しています。" : "",
                      property == "backend" ? options(["command", "openai"]) : [])
            }
            if document.entry(for: key, app: app) != nil {
                actions.append(SettingsAction(id: "execute.entry.remove:\(prefix)", section: "execute",
                                              label: "\(name) を削除", inputs: []))
            }
        }
        if let document = try? executeDocument() {
            for key in document.numberedKeys { addEntry(document, key, nil) }
            for app in document.appIDs {
                addEntry(document, nil, app)
                for key in document.numberedKeys(for: app) { addEntry(document, key, app) }
            }
            actions.insert(SettingsAction(id: "execute.entry.add", section: "execute",
                                          label: "番号別またはアプリ別の設定を追加", inputs: [
                                            SettingsActionInput(id: "key", label: "番号（アプリ全体なら空）", kind: "text"),
                                            SettingsActionInput(id: "app", label: "アプリ ID（共通なら空）", kind: "text"),
                                            SettingsActionInput(id: "property", label: "アプリ全体の初期項目", kind: "text"),
                                            SettingsActionInput(id: "value", label: "初期値", kind: "text")
                                          ]), at: 0)
        } else {
            field("execute.configError", "execute", "execute.json", "text",
                  "設定ファイルを読み取れません。内容を確認してください。", .file,
                  "他の設定は編集できます。", [], false)
        }
        var sections = [
            SettingsSection(id: "execute", label: "行の書き換え"),
            SettingsSection(id: "openai", label: "OpenAI"),
            SettingsSection(id: "kanji", label: "漢字変換"),
            SettingsSection(id: "dictionary", label: "ユーザー辞書")
        ]
        #if os(Linux)
        sections.append(SettingsSection(id: "system", label: "設定ファイル"))
        #endif
        #if os(macOS)
        sections += [
            SettingsSection(id: "zenzai", label: "Zenzai"),
            SettingsSection(id: "compat", label: "アプリ互換性")
        ]
        #endif
        return SettingsSnapshot(schema: 1, sections: sections, fields: fields, actions: actions)
    }

    /// Applies scalar settings. The API key is supplied to the platform secret store by the caller.
    public func apply(_ request: SettingsApplyRequest,
                      writeAPIKey: (String?) throws -> Void) throws {
        guard request.schema == 1 else { throw StoreError.unsupportedSchema }
        var document: ExecuteSettingsDocument?
        var documentChanged = false
        for action in request.actions {
            if document == nil { document = try executeDocument() }
            if action.id == "execute.entry.add" {
                let key = action.values["key"].flatMap { $0.isEmpty ? nil : $0 }
                let app = action.values["app"].flatMap { $0.isEmpty ? nil : $0 }
                var settings = ExecuteSettings()
                if let property = action.values["property"], !property.isEmpty {
                    try Self.setEntryValue(&settings, property, action.values["value"])
                }
                if key == nil && settings.isEmpty { throw StoreError.invalidValue }
                try document!.setSettings(settings, for: key, app: app)
                documentChanged = true
            } else if action.id.hasPrefix("execute.entry.remove:") {
                guard let target = Self.decodeEntryID(String(action.id.dropFirst("execute.entry.remove:".count)))
                else { throw StoreError.unsupportedAction }
                try document!.setSettings(nil, for: target.key, app: target.app)
                documentChanged = true
            } else {
                throw StoreError.unsupportedAction
            }
        }
        var defaultsChanges: [(String, Any?)] = []
        var linuxChanges: [String: String?] = [:]
        var secret: String?? = nil
        var dictionaryText: String?? = nil
        for change in request.changes {
            guard change.op == "set" || change.op == "reset" else { throw StoreError.invalidOperation }
            if change.op == "set" && change.value == nil { throw StoreError.invalidValue }
            #if os(Linux)
            if let key = Self.linuxKey(for: change.id), environment[key] != nil {
                throw StoreError.invalidOperation
            }
            #endif
            let value = change.op == "reset" ? nil : change.value
            switch change.id {
            case let id where id.hasPrefix("execute.entry."):
                guard let target = Self.decodeFieldID(id) else { throw StoreError.unknownField }
                if document == nil { document = try executeDocument() }
                var settings = document!.entry(for: target.key, app: target.app) ?? ExecuteSettings()
                try Self.setEntryValue(&settings, target.property, value)
                try document!.setSettings(settings, for: target.key, app: target.app)
                documentChanged = true
            case "execute.backend":
                if let value, !["auto", "command", "openai"].contains(value) { throw StoreError.invalidValue }
                #if os(Linux)
                linuxChanges["MLH_EXEC_BACKEND"] = .some(value == "auto" ? nil : value)
                #else
                defaultsChanges.append(("ExecuteBackend", value == "auto" ? nil : value))
                #endif
            case "openai.baseURL", "openai.model", "openai.instructions", "openai.reasoningEffort":
                #if os(Linux)
                let mapping = ["openai.baseURL": "MLH_OPENAI_BASE_URL", "openai.model": "MLH_OPENAI_MODEL",
                               "openai.instructions": "MLH_OPENAI_INSTRUCTIONS",
                               "openai.reasoningEffort": "MLH_OPENAI_REASONING_EFFORT"]
                linuxChanges[mapping[change.id]!] = .some(value)
                #else
                let mapping = ["openai.baseURL": "OpenAIBaseURL", "openai.model": "OpenAIModel",
                               "openai.instructions": "OpenAIInstructions", "openai.reasoningEffort": "OpenAIReasoningEffort"]
                defaultsChanges.append((mapping[change.id]!, value))
                #endif
            case "openai.apiKey":
                #if os(Linux)
                guard environment["OPENAI_API_KEY"] == nil else { throw StoreError.invalidOperation }
                guard apiKeySecretAvailable else { throw StoreError.secretUnavailable }
                #endif
                secret = .some(value)
            case "kanji.backend":
                if let value, !["azookey", "google"].contains(value) { throw StoreError.invalidValue }
                #if os(Linux)
                linuxChanges["MLH_TRANSLITERATOR"] = .some(value)
                #else
                defaultsChanges.append(("KanjiBackend", value))
                #endif
            case "dictionary.entries":
                dictionaryText = .some(value)
            #if os(Linux)
            case "execute.configPath":
                linuxChanges["MLH_EXEC_CONFIG"] = .some(value)
            case "execute.commandPath":
                linuxChanges["MLH_EXEC_COMMAND"] = .some(value)
            case "dictionary.systemPath":
                linuxChanges["MLH_DICTIONARY"] = .some(value)
            case "dictionary.userPath":
                linuxChanges["MLH_USER_DICTIONARY"] = .some(value)
            #endif
            #if os(macOS)
            case "zenzai.model":
                defaultsChanges.append(("ZenzaiModel", value))
            case "zenzai.contextLength", "zenzai.inferenceLimit":
                let key = change.id == "zenzai.contextLength" ? "ZenzaiContextLength" : "ZenzaiInferenceLimit"
                guard let value else { defaultsChanges.append((key, nil)); break }
                guard let integer = Int(value) else { throw StoreError.invalidValue }
                defaultsChanges.append((key, integer))
            case "compat.syntheticDeletionApps", "compat.replacementRangeApps":
                let key = change.id == "compat.syntheticDeletionApps" ? "SyntheticDeletionApps" : "ReplacementRangeApps"
                defaultsChanges.append((key, value.map { $0.isEmpty ? [] : $0.components(separatedBy: "\n") }))
            #endif
            default:
                throw StoreError.unknownField
            }
        }
        #if os(Linux)
        if !linuxChanges.isEmpty { try LinuxSettings.save(linuxChanges, environment: environment) }
        let base = linuxBasePath
        let currentExecuteURL = URL(fileURLWithPath: LinuxSettings.resolve("MLH_EXEC_CONFIG", environment: environment).value
                                            ?? "\(base)/mlh/execute.json")
        #else
        let currentExecuteURL = executeURL
        #endif
        if documentChanged { try document!.save(to: currentExecuteURL) }
        if let dictionaryText {
            let text = dictionaryText ?? ""
            #if os(Linux)
            let base = linuxBasePath
            let currentDictionaryURL = URL(fileURLWithPath: LinuxSettings.resolve("MLH_USER_DICTIONARY", environment: environment).value
                                                ?? "\(base)/mlh/userdict.txt")
            #else
            let currentDictionaryURL = userDictionaryURL
            #endif
            let destination = currentDictionaryURL.resolvingSymlinksInPath()
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try text.write(to: destination, atomically: true, encoding: .utf8)
        }
        if let secret { try writeAPIKey(secret) }
        for (key, value) in defaultsChanges {
            if let value { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
    }

    private func executeDocument() throws -> ExecuteSettingsDocument {
        let data = FileManager.default.fileExists(atPath: executeURL.path)
            ? try Data(contentsOf: executeURL) : Data("{}".utf8)
        return try ExecuteSettingsDocument(data: data)
    }

    private static func entryID(key: String?, app: String?) -> String {
        let scope = app.map { "a" + ($0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0) } ?? "g"
        return "execute.entry.\(scope).\(key ?? "base")"
    }

    #if os(Linux)
    private static func linuxKey(for id: String) -> String? {
        switch id {
        case "execute.backend": return "MLH_EXEC_BACKEND"
        case "execute.configPath": return "MLH_EXEC_CONFIG"
        case "execute.commandPath": return "MLH_EXEC_COMMAND"
        case "openai.baseURL": return "MLH_OPENAI_BASE_URL"
        case "openai.model": return "MLH_OPENAI_MODEL"
        case "openai.instructions": return "MLH_OPENAI_INSTRUCTIONS"
        case "openai.reasoningEffort": return "MLH_OPENAI_REASONING_EFFORT"
        case "kanji.backend": return "MLH_TRANSLITERATOR"
        case "dictionary.userPath": return "MLH_USER_DICTIONARY"
        case "dictionary.systemPath": return "MLH_DICTIONARY"
        default: return nil
        }
    }
    #endif

    private static func decodeEntryID(_ id: String) -> (key: String?, app: String?)? {
        let parts = id.components(separatedBy: ".")
        guard parts.count == 4, parts[0] == "execute", parts[1] == "entry" else { return nil }
        let app: String?
        if parts[2] == "g" { app = nil }
        else if parts[2].hasPrefix("a") { app = String(parts[2].dropFirst()).removingPercentEncoding }
        else { return nil }
        let key = parts[3] == "base" ? nil : parts[3]
        return (key, app)
    }

    private static func decodeFieldID(_ id: String) -> (key: String?, app: String?, property: String)? {
        let parts = id.components(separatedBy: ".")
        guard parts.count == 5,
              let target = decodeEntryID(parts.prefix(4).joined(separator: ".")) else { return nil }
        return (target.key, target.app, parts[4])
    }

    private static func entryValue(_ settings: ExecuteSettings, _ property: String) -> String? {
        switch property {
        case "backend": return settings.backend
        case "command": return settings.command
        case "baseURL": return settings.baseURL
        case "model": return settings.model
        case "instructions": return settings.instructions
        case "reasoningEffort": return settings.reasoningEffort
        default: return nil
        }
    }

    private static func setEntryValue(_ settings: inout ExecuteSettings, _ property: String,
                                      _ value: String?) throws {
        switch property {
        case "backend":
            if let value, !["command", "openai"].contains(value) { throw StoreError.invalidValue }
            settings.backend = value
        case "command": settings.command = value
        case "baseURL": settings.baseURL = value
        case "model": settings.model = value
        case "instructions": settings.instructions = value
        case "reasoningEffort": settings.reasoningEffort = value
        default: throw StoreError.unknownField
        }
    }
}
