import AppKit
import Foundation

private struct Section: Decodable {
    let id: String
    let label: String
}

private struct Option: Decodable {
    let value: String
    let label: String
}

private struct Field: Decodable {
    let id: String
    let section: String
    let label: String
    let kind: String
    let value: String?
    let origin: String
    let options: [Option]
    let editable: Bool
    let description: String
    let has_value: Bool
}

private struct ActionInput: Decodable {
    let id: String
    let label: String
    let kind: String
}

private struct SettingsAction: Decodable {
    let id: String
    let section: String
    let label: String
    let inputs: [ActionInput]
}

private struct Snapshot: Decodable {
    let schema: Int
    let sections: [Section]
    let fields: [Field]
    let actions: [SettingsAction]
}

private struct Change: Encodable {
    let id: String
    let op: String
    let value: String?
}

private struct ActionRequest: Encodable {
    let id: String
    let values: [String: String]
}

private struct ApplyRequest: Encodable {
    let schema = 1
    let changes: [Change]
    let actions: [ActionRequest]
}

private enum Editor {
    case text(NSTextField)
    case multiline(NSTextView)
    case select(NSPopUpButton)

    func value() -> String {
        switch self {
        case .text(let view): return view.stringValue
        case .multiline(let view): return view.string
        case .select(let view): return view.selectedItem?.representedObject as? String ?? ""
        }
    }
}

private final class SettingsBackendClient {
    private let executable: URL

    init() throws {
        if let override = ProcessInfo.processInfo.environment["MLH_SETTINGS_BACKEND_PATH"] {
            executable = URL(fileURLWithPath: override)
        } else {
            executable = Bundle.main.executableURL!
                .deletingLastPathComponent().appendingPathComponent("mlh-settings-backend")
        }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw NSError(domain: "mlh-settings", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "設定バックエンドが見つかりません: \(executable.path)"])
        }
    }

    func snapshot() throws -> Snapshot { try invoke("snapshot", input: nil) }

    func apply(_ changes: [Change], actions: [ActionRequest] = []) throws -> Snapshot {
        try invoke("apply", input: JSONEncoder().encode(ApplyRequest(changes: changes, actions: actions)))
    }

    private func invoke(_ command: String, input: Data?) throws -> Snapshot {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = executable
        process.arguments = [command]
        process.standardOutput = output
        process.standardError = error
        if input != nil { process.standardInput = Pipe() }
        try process.run()
        if let input, let pipe = process.standardInput as? Pipe {
            pipe.fileHandleForWriting.write(input)
            try pipe.fileHandleForWriting.close()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "設定の読み書きに失敗しました"
            throw NSError(domain: "mlh-settings", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard snapshot.schema == 1 else {
            throw NSError(domain: "mlh-settings", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "設定形式のバージョンが異なります"])
        }
        return snapshot
    }
}

private final class SettingsDocumentView: NSStackView {
    override var isFlipped: Bool { true }
}

private final class SettingsWindowController: NSObject, NSApplicationDelegate, NSWindowDelegate,
                                             NSTableViewDataSource, NSTableViewDelegate, URLSessionDownloadDelegate {
    private var window: NSWindow!
    private var scroll: NSScrollView!
    private var content: NSStackView!
    private var sidebar: NSTableView!
    private var saveButton: NSButton!
    private var reloadButton: NSButton!
    private var sections: [Section] = []
    private var sectionViews: [String: NSView] = [:]
    private var selectedSectionID: String?
    private var snapshot: Snapshot?
    private var editors: [String: Editor] = [:]
    private var pendingReset: Set<String> = []
    private var backend: SettingsBackendClient?
    private var actions: [String: SettingsAction] = [:]
    private var applyButtons: [NSButton] = []
    private var canApply = true
    private var modelStatus: NSTextField?
    private var modelDownloadButton: NSButton?
    private var modelProgress: NSProgressIndicator?
    private var modelPathControls: [(NSControl, Bool)] = []
    private var downloadProgress: Double?
    private var flexibleWidths: [(NSLayoutConstraint, CGFloat)] = []
    private var downloadTask: URLSessionDownloadTask?
    private var downloadCancelled = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rect = NSRect(x: 0, y: 0, width: 920, height: 680)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "mlh 設定"
        window.center()
        window.minSize = NSSize(width: 680, height: 420)
        window.delegate = self

        let root = SettingsDocumentView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 20
        root.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 32, right: 28)
        content = root
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.documentView = root
        self.scroll = scroll

        let container = NSView(frame: rect)
        let sidebarBackground = NSVisualEffectView()
        sidebarBackground.material = .sidebar
        sidebarBackground.blendingMode = .behindWindow
        sidebarBackground.state = .active
        let sidebarScroll = NSScrollView()
        sidebarScroll.drawsBackground = false
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.borderType = .noBorder
        let sidebar = NSTableView()
        sidebar.headerView = nil
        sidebar.rowHeight = 34
        sidebar.selectionHighlightStyle = .regular
        sidebar.backgroundColor = .clear
        sidebar.focusRingType = .none
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
        column.resizingMask = .autoresizingMask
        sidebar.addTableColumn(column)
        sidebar.delegate = self
        sidebar.dataSource = self
        sidebarScroll.documentView = sidebar
        self.sidebar = sidebar

        let footer = NSVisualEffectView()
        footer.material = .windowBackground
        footer.blendingMode = .withinWindow
        footer.state = .active
        let divider = NSBox()
        divider.boxType = .separator
        let reload = NSButton(title: "再読み込み", target: self, action: #selector(reloadSettings))
        reloadButton = reload
        let save = NSButton(title: "保存", target: self, action: #selector(saveChanges))
        save.bezelStyle = .rounded
        save.keyEquivalent = "s"
        save.keyEquivalentModifierMask = [.command]
        saveButton = save
        for view in [sidebarBackground, sidebarScroll, scroll, footer, divider, reload, save] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        container.addSubview(sidebarBackground)
        sidebarBackground.addSubview(sidebarScroll)
        container.addSubview(scroll)
        container.addSubview(footer)
        footer.addSubview(divider)
        footer.addSubview(reload)
        footer.addSubview(save)
        NSLayoutConstraint.activate([
            sidebarBackground.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sidebarBackground.topAnchor.constraint(equalTo: container.topAnchor),
            sidebarBackground.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sidebarBackground.widthAnchor.constraint(equalToConstant: 190),
            sidebarScroll.leadingAnchor.constraint(equalTo: sidebarBackground.leadingAnchor),
            sidebarScroll.trailingAnchor.constraint(equalTo: sidebarBackground.trailingAnchor),
            sidebarScroll.topAnchor.constraint(equalTo: sidebarBackground.topAnchor, constant: 16),
            sidebarScroll.bottomAnchor.constraint(equalTo: sidebarBackground.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: sidebarBackground.trailingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: sidebarBackground.trailingAnchor),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 62),
            divider.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            divider.topAnchor.constraint(equalTo: footer.topAnchor),
            reload.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            reload.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 24),
            save.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            save.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -28)
        ])
        window.contentView = container

        let menu = NSMenu()
        let appMenu = NSMenuItem()
        appMenu.submenu = NSMenu()
        appMenu.submenu?.addItem(withTitle: "mlh 設定を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(appMenu)
        NSApplication.shared.mainMenu = menu

        do {
            backend = try SettingsBackendClient()
            try show(backend!.snapshot())
        } catch {
            showLoadError(error)
            showError(error)
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func show(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        canApply = true
        saveButton.isEnabled = true
        applyButtons = [saveButton]
        editors.removeAll()
        pendingReset.removeAll()
        actions = Dictionary(snapshot.actions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        modelStatus = nil
        modelDownloadButton = nil
        modelProgress = nil
        modelPathControls.removeAll()
        flexibleWidths.removeAll()
        let priority = ["kanji", "dictionary", "zenzai", "execute", "openai", "compat", "system"]
        sections = snapshot.sections.sorted {
            let left = priority.firstIndex(of: $0.id) ?? priority.count
            let right = priority.firstIndex(of: $1.id) ?? priority.count
            return left == right ? $0.label < $1.label : left < right
        }
        sectionViews = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, makeSectionView($0, snapshot: snapshot)) })
        sidebar.reloadData()
        let index = sections.firstIndex(where: { $0.id == selectedSectionID }) ?? 0
        if sections.indices.contains(index) {
            sidebar.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            selectSection(at: index)
        }
        updateDownloadControls()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { sections.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("SectionCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        if cell.textField == nil {
            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            cell.textField = label
            cell.identifier = identifier
        }
        cell.textField?.stringValue = sections[row].label
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectSection(at: sidebar.selectedRow)
    }

    private func selectSection(at index: Int) {
        guard sections.indices.contains(index), let view = sectionViews[sections[index].id] else { return }
        selectedSectionID = sections[index].id
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        content.addArrangedSubview(view)
        resizeDocument()
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func windowDidResize(_ notification: Notification) {
        resizeDocument()
    }

    private func resizeDocument() {
        guard let scroll, let content else { return }
        let fieldWidth = max(260, min(390, scroll.contentSize.width - 56 - 130 - 14))
        for (constraint, deduction) in flexibleWidths {
            constraint.constant = max(120, fieldWidth - deduction)
        }
        let size = content.fittingSize
        content.setFrameSize(NSSize(width: max(size.width, scroll.contentSize.width), height: size.height))
    }

    private func setFlexibleWidth(_ view: NSView, deduction: CGFloat = 0) {
        let constraint = view.widthAnchor.constraint(equalToConstant: 390 - deduction)
        constraint.isActive = true
        flexibleWidths.append((constraint, deduction))
    }

    private func makeSectionView(_ section: Section, snapshot: Snapshot) -> NSView {
        let page = NSStackView()
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 16

        let heading = NSTextField(labelWithString: section.label)
        heading.font = .boldSystemFont(ofSize: 22)
        page.addArrangedSubview(heading)
        let explanations = [
            "kanji": "日本語の候補を作る方式を選びます。",
            "dictionary": "漢字変換に使う単語を 1 行ずつ登録します。",
            "zenzai": "azooKey の候補を文脈に合わせる追加モデルです。",
            "execute": "x/ による行の書き換え方法と、番号・アプリ別の上書きを設定します。",
            "openai": "行の書き換えで OpenAI を使う場合の接続情報です。",
            "compat": "アプリごとの文字置換方法を調整します。"
        ]
        if let explanation = explanations[section.id] {
            let subtitle = NSTextField(wrappingLabelWithString: explanation)
            subtitle.textColor = .secondaryLabelColor
            setFlexibleWidth(subtitle, deduction: -130)
            page.addArrangedSubview(subtitle)
        }

        let fields = snapshot.fields.filter { $0.section == section.id }
        let sectionActions = snapshot.actions.filter { $0.section == section.id }
        if section.id == "execute" {
            for field in fields where !field.id.hasPrefix("execute.entry.") {
                page.addArrangedSubview(makeRow(field))
            }
            if let add = sectionActions.first(where: { $0.id == "execute.entry.add" }) {
                let button = makeActionButton(add, title: "番号・アプリ別の設定を追加…")
                button.bezelStyle = .rounded
                page.addArrangedSubview(button)
            }
            var grouped: [(String, [Field])] = []
            for field in fields where field.id.hasPrefix("execute.entry.") {
                let key = String(field.id.dropLast(field.id.split(separator: ".").last?.count ?? 0))
                if let last = grouped.indices.last, grouped[last].0 == key {
                    grouped[last].1.append(field)
                } else {
                    grouped.append((key, [field]))
                }
            }
            for (key, entryFields) in grouped {
                let name = entryFields.first?.label.components(separatedBy: ": ").first ?? key
                let header = NSStackView()
                header.orientation = .horizontal
                header.spacing = 12
                let title = NSTextField(labelWithString: name)
                title.font = .boldSystemFont(ofSize: 15)
                header.addArrangedSubview(title)
                if let remove = sectionActions.first(where: { $0.id == "execute.entry.remove:\(key.dropLast())" }) {
                    let button = makeActionButton(remove, title: "この設定を削除…")
                    button.controlSize = .small
                    header.addArrangedSubview(button)
                }
                page.addArrangedSubview(header)
                for field in entryFields {
                    let label = field.label.hasPrefix("\(name): ") ? String(field.label.dropFirst(name.count + 2)) : field.label
                    page.addArrangedSubview(makeRow(field, label: label))
                }
            }
        } else {
            for field in fields { page.addArrangedSubview(makeRow(field)) }
            for action in sectionActions { page.addArrangedSubview(makeActionButton(action)) }
        }
        if fields.isEmpty && sectionActions.isEmpty {
            let empty = NSTextField(labelWithString: "設定項目はありません。")
            empty.textColor = .secondaryLabelColor
            page.addArrangedSubview(empty)
        }
        return page
    }

    private func makeActionButton(_ action: SettingsAction, title: String? = nil) -> NSButton {
        let button = NSButton(title: title ?? action.label, target: self, action: #selector(performAction(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(action.id)
        applyButtons.append(button)
        return button
    }

    private func makeRow(_ field: Field, label labelText: String? = nil) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 14
        let label = NSTextField(wrappingLabelWithString: labelText ?? field.label)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 130).isActive = true
        row.addArrangedSubview(label)

        let details = NSStackView()
        details.orientation = .vertical
        details.alignment = .leading
        details.spacing = 6
        row.addArrangedSubview(details)

        if field.kind == "select" {
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            if field.value == nil {
                popup.addItem(withTitle: field.id.hasPrefix("execute.entry.") ? "未設定（継承）" : "未設定")
                popup.select(popup.lastItem)
            }
            if let current = field.value, !field.options.contains(where: { $0.value == current }) {
                popup.addItem(withTitle: "現在値: \(current)")
                popup.lastItem?.representedObject = current
            }
            for option in field.options {
                popup.addItem(withTitle: optionLabel(option, field: field))
                popup.lastItem?.representedObject = option.value
                if option.value == field.value { popup.select(popup.lastItem) }
            }
            popup.isEnabled = field.editable
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
            editors[field.id] = .select(popup)
            details.addArrangedSubview(popup)
            if field.id == "execute.backend" {
                let link = NSButton(title: "OpenAI の接続設定を開く…", target: self,
                                    action: #selector(showOpenAISettings))
                link.bezelStyle = .rounded
                link.controlSize = .small
                details.addArrangedSubview(link)
            }
        } else if field.kind == "multiline" || field.kind == "list" {
            let height: CGFloat = field.id == "dictionary.entries" ? 220 : 116
            let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 390, height: height))
            text.string = field.value ?? ""
            text.isEditable = field.editable
            text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            text.isRichText = false
            text.isVerticallyResizable = true
            text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true
            text.textContainerInset = NSSize(width: 5, height: 6)
            let editorScroll = NSScrollView(frame: text.frame)
            editorScroll.hasVerticalScroller = true
            editorScroll.borderType = .bezelBorder
            editorScroll.documentView = text
            setFlexibleWidth(editorScroll)
            editorScroll.heightAnchor.constraint(equalToConstant: height).isActive = true
            editors[field.id] = .multiline(text)
            details.addArrangedSubview(editorScroll)
        } else {
            let text: NSTextField = field.kind == "secret" ? NSSecureTextField() : NSTextField()
            text.stringValue = field.kind == "secret" ? "" : field.value ?? ""
            text.placeholderString = field.kind == "secret" && field.has_value ? "保存済み（変更時だけ入力）" : ""
            text.isEditable = field.editable
            if field.kind == "integer" {
                text.widthAnchor.constraint(equalToConstant: 100).isActive = true
            } else {
                setFlexibleWidth(text, deduction: field.id == "zenzai.model" ? 85 : 0)
            }
            editors[field.id] = .text(text)
            if field.id == "zenzai.model" { modelPathControls.append((text, text.isEnabled)) }
            if field.kind == "integer" || field.id == "zenzai.model" {
                let controls = NSStackView()
                controls.orientation = .horizontal
                controls.spacing = 8
                controls.addArrangedSubview(text)
                if field.kind == "integer" {
                    let stepper = NSStepper()
                    stepper.minValue = -1_000_000
                    stepper.maxValue = 1_000_000
                    stepper.integerValue = Int(field.value ?? "") ?? 0
                    stepper.isEnabled = field.editable
                    stepper.identifier = NSUserInterfaceItemIdentifier(field.id)
                    stepper.target = self
                    stepper.action = #selector(stepInteger(_:))
                    controls.addArrangedSubview(stepper)
                } else {
                    let choose = NSButton(title: "選択…", target: self, action: #selector(chooseModel(_:)))
                    choose.identifier = NSUserInterfaceItemIdentifier(field.id)
                    choose.isEnabled = field.editable
                    modelPathControls.append((choose, choose.isEnabled))
                    controls.addArrangedSubview(choose)
                }
                details.addArrangedSubview(controls)
            } else {
                details.addArrangedSubview(text)
            }
        }
        let source = NSStackView()
        source.orientation = .horizontal
        source.spacing = 8
        let origin = NSTextField(labelWithString: "取得元: \(originLabel(field.origin))")
        origin.textColor = .secondaryLabelColor
        origin.font = .systemFont(ofSize: 11)
        source.addArrangedSubview(origin)
        if field.editable {
            let reset = NSButton(title: "リセット…", target: self, action: #selector(resetField(_:)))
            reset.controlSize = .small
            reset.bezelStyle = .inline
            reset.toolTip = "保存時にこの設定を削除し、標準値または継承値に戻します"
            reset.identifier = NSUserInterfaceItemIdentifier(field.id)
            if field.id == "zenzai.model" { modelPathControls.append((reset, reset.isEnabled)) }
            source.addArrangedSubview(reset)
        }
        details.addArrangedSubview(source)
        if !field.description.isEmpty {
            let hint = NSTextField(wrappingLabelWithString: field.description)
            hint.textColor = .secondaryLabelColor
            hint.font = .systemFont(ofSize: 11)
            setFlexibleWidth(hint)
            details.addArrangedSubview(hint)
        }
        if field.id == "zenzai.model" { addModelControls(for: field, to: details) }
        return row
    }

    private func originLabel(_ origin: String) -> String {
        ["default": "標準", "userDefaults": "保存済み", "file": "ファイル", "keychain": "キーチェーン",
         "environment": "環境変数", "secretService": "Secret Service"][origin] ?? origin
    }

    private func optionLabel(_ option: Option, field: Field) -> String {
        if field.id == "execute.backend" || field.id.hasSuffix(".backend") && field.id.hasPrefix("execute.entry.") {
            return ["auto": "自動", "command": "外部コマンド", "openai": "OpenAI"][option.value] ?? option.label
        }
        if field.id == "kanji.backend" {
            return ["azookey": "azooKey", "google": "Google"][option.value] ?? option.label
        }
        return option.label
    }

    @objc private func showOpenAISettings() {
        guard let index = sections.firstIndex(where: { $0.id == "openai" }) else { return }
        sidebar.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        selectSection(at: index)
    }

    @objc private func stepInteger(_ sender: NSStepper) {
        guard let id = sender.identifier?.rawValue,
              case .text(let text)? = editors[id] else { return }
        text.stringValue = String(sender.integerValue)
    }

    @objc private func chooseModel(_ sender: NSButton) {
        guard downloadTask == nil else { return }
        guard let id = sender.identifier?.rawValue,
              case .text(let text)? = editors[id] else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Zenzai の GGUF モデルを選択してください"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        text.stringValue = url.path
        modelStatus?.stringValue = "パスの変更は「保存」で反映されます。"
    }

    private func addModelControls(for field: Field, to details: NSStackView) {
        let path = field.value ?? ""
        let exists = !path.isEmpty && FileManager.default.fileExists(atPath: path)
        let status = NSTextField(wrappingLabelWithString: exists
                                 ? "モデルファイルを使用できます。"
                                 : "モデルファイルが見つかりません。取得するか、手元の GGUF ファイルを選択してください。")
        status.font = .systemFont(ofSize: 11)
        status.textColor = exists ? .secondaryLabelColor : .systemOrange
        setFlexibleWidth(status)
        details.addArrangedSubview(status)
        modelStatus = status
        guard !exists, !path.isEmpty else { return }
        let button = NSButton(title: "モデルをダウンロード…", target: self, action: #selector(downloadModel(_:)))
        let progress = NSProgressIndicator()
        progress.style = .bar
        progress.minValue = 0
        progress.maxValue = 100
        progress.isHidden = true
        progress.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let controls = NSStackView(views: [button, progress])
        controls.orientation = .horizontal
        controls.spacing = 12
        details.addArrangedSubview(controls)
        modelDownloadButton = button
        modelProgress = progress
        updateDownloadControls()
    }

    private func updateDownloadControls() {
        let busy = downloadTask != nil
        applyButtons.forEach { $0.isEnabled = canApply && !busy }
        reloadButton?.isEnabled = !busy
        for (control, normallyEnabled) in modelPathControls {
            control.isEnabled = normallyEnabled && !busy
        }
        modelDownloadButton?.title = busy ? "中止" : "モデルをダウンロード…"
        modelProgress?.isHidden = !busy
        if busy {
            modelStatus?.stringValue = downloadCancelled ? "ダウンロードを中止しています…" : "モデルをダウンロードしています…"
            if let downloadProgress {
                modelProgress?.isIndeterminate = false
                modelProgress?.doubleValue = downloadProgress
                modelProgress?.setAccessibilityLabel("モデルをダウンロード中")
            } else {
                modelProgress?.isIndeterminate = true
                modelProgress?.setAccessibilityLabel("モデルをダウンロード中（サイズ不明）")
            }
            modelProgress?.startAnimation(nil)
        } else {
            modelProgress?.stopAnimation(nil)
        }
    }

    @objc private func downloadModel(_ sender: NSButton) {
        if let downloadTask {
            downloadCancelled = true
            modelStatus?.stringValue = "ダウンロードを中止しています…"
            downloadTask.cancel()
            return
        }
        guard let field = snapshot?.fields.first(where: { $0.id == "zenzai.model" }),
              let path = field.value, !path.isEmpty,
              editors[field.id]?.value() == path, !pendingReset.contains(field.id) else {
            modelStatus?.stringValue = "モデルのパスに未保存の変更があります。先に保存してください。"
            return
        }
        let destination = URL(fileURLWithPath: path)
        guard !FileManager.default.fileExists(atPath: path) else {
            modelStatus?.stringValue = "モデルファイルは既にあります。上書きしません。"
            sender.isHidden = true
            return
        }
        let defaultURL = "https://huggingface.co/Miwa-Keita/zenz-v3.1-small-gguf/resolve/main/ggml-model-Q5_K_M.gguf"
        guard let url = URL(string: ProcessInfo.processInfo.environment["MLH_SETTINGS_MODEL_URL"] ?? defaultURL),
              url.scheme == "https" || url.host == "127.0.0.1" || url.host == "localhost" else {
            modelStatus?.stringValue = "モデルの取得先が正しくありません。"
            return
        }
        downloadCancelled = false
        downloadProgress = nil
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        task.taskDescription = destination.path
        downloadTask = task
        updateDownloadControls()
        task.resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        DispatchQueue.main.async {
            guard self.downloadTask === downloadTask else { return }
            self.downloadProgress = totalBytesExpectedToWrite > 0
                ? Double(totalBytesWritten) * 100 / Double(totalBytesExpectedToWrite)
                : nil
            self.updateDownloadControls()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200,
                  let path = downloadTask.taskDescription else {
                throw NSError(domain: "mlh-settings", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "モデルの取得先が正常な応答を返しませんでした。"])
            }
            let destination = URL(fileURLWithPath: path)
            let files = FileManager.default
            try files.createDirectory(at: destination.deletingLastPathComponent(),
                                      withIntermediateDirectories: true)
            let staging = destination.deletingLastPathComponent()
                .appendingPathComponent(".zenz-download-\(UUID().uuidString)")
            do {
                try files.copyItem(at: location, to: staging)
            } catch {
                try? files.removeItem(at: staging)
                throw error
            }
            do {
                let handle = try FileHandle(forReadingFrom: staging)
                let signature = try handle.read(upToCount: 4)
                try handle.close()
                guard signature == Data("GGUF".utf8) else {
                    throw NSError(domain: "mlh-settings", code: 4,
                                  userInfo: [NSLocalizedDescriptionKey: "取得したファイルは GGUF モデルではありません。"])
                }
            } catch {
                try? files.removeItem(at: staging)
                throw error
            }
            #if MLH_TESTING
            if let gate = ProcessInfo.processInfo.environment["MLH_MODEL_COMMIT_GATE"], !gate.isEmpty {
                files.createFile(atPath: gate + ".ready", contents: Data())
                let deadline = Date().addingTimeInterval(10)
                while !files.fileExists(atPath: gate + ".release") && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }
            #endif
            DispatchQueue.main.async {
                defer { try? files.removeItem(at: staging) }
                guard self.downloadTask === downloadTask else { return }
                if self.downloadCancelled {
                    self.finishDownload(session: session, task: downloadTask, message: "ダウンロードを中止しました。", saved: false)
                    return
                }
                do {
                    // A hard link fails if a file or symlink already occupies this path.
                    try files.linkItem(at: staging, to: destination)
                    self.finishDownload(session: session, task: downloadTask,
                                        message: "モデルを保存しました。mlh を再起動すると使用できます。", saved: true)
                } catch {
                    self.finishDownload(session: session, task: downloadTask,
                                        message: error.localizedDescription, saved: false)
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.finishDownload(session: session, task: downloadTask,
                                    message: self.downloadCancelled ? "ダウンロードを中止しました。" : error.localizedDescription,
                                    saved: false)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let downloadTask = task as? URLSessionDownloadTask else { return }
        DispatchQueue.main.async {
            self.finishDownload(session: session, task: downloadTask,
                                message: self.downloadCancelled ? "ダウンロードを中止しました。" : error.localizedDescription,
                                saved: false)
        }
    }

    private func finishDownload(session: URLSession, task: URLSessionDownloadTask,
                                message: String, saved: Bool) {
        guard downloadTask === task else { return }
        downloadTask = nil
        downloadCancelled = false
        downloadProgress = nil
        modelStatus?.stringValue = message
        if saved { modelDownloadButton?.isHidden = true }
        updateDownloadControls()
        session.finishTasksAndInvalidate()
    }

    @objc private func resetField(_ sender: NSButton) {
        guard downloadTask == nil else { return }
        guard let id = sender.identifier?.rawValue else { return }
        pendingReset.insert(id)
        sender.title = "保存待ち"
    }

    @objc private func reloadSettings() {
        guard downloadTask == nil else { return }
        do {
            let client = try backend ?? SettingsBackendClient()
            backend = client
            try show(client.snapshot())
        } catch { showError(error) }
    }

    private func showLoadError(_ error: Error) {
        canApply = false
        saveButton.isEnabled = false
        sections = []
        sidebar.reloadData()
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let title = NSTextField(labelWithString: "設定を読み込めませんでした")
        title.font = .boldSystemFont(ofSize: 20)
        let detail = NSTextField(wrappingLabelWithString: error.localizedDescription)
        detail.widthAnchor.constraint(equalToConstant: 500).isActive = true
        content.addArrangedSubview(title)
        content.addArrangedSubview(detail)
        resizeDocument()
    }

    @objc private func saveChanges() {
        guard canApply, downloadTask == nil, let backend else { return }
        let changes = collectChanges()
        guard !changes.isEmpty else { return }
        do { try show(backend.apply(changes)) } catch { recoverAfterApplyFailure(error, backend: backend) }
    }

    private func collectChanges() -> [Change] {
        guard let snapshot else { return [] }
        var changes: [Change] = []
        for field in snapshot.fields where field.editable {
            if pendingReset.contains(field.id) {
                changes.append(Change(id: field.id, op: "reset", value: nil))
            } else if let value = editors[field.id]?.value(),
                      value != (field.value ?? ""), !(field.kind == "secret" && value.isEmpty) {
                changes.append(Change(id: field.id, op: "set", value: value))
            }
        }
        return changes
    }

    @objc private func performAction(_ sender: NSButton) {
        guard canApply, downloadTask == nil,
              let id = sender.identifier?.rawValue, let action = actions[id], let backend else { return }
        let dialog = NSAlert()
        dialog.messageText = action.label
        dialog.addButton(withTitle: "実行")
        dialog.addButton(withTitle: "キャンセル")
        var inputs: [String: NSTextField] = [:]
        if !action.inputs.isEmpty {
            let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 340, height: CGFloat(action.inputs.count * 52)))
            stack.orientation = .vertical
            stack.spacing = 4
            for input in action.inputs {
                let label = NSTextField(labelWithString: input.label)
                let text: NSTextField = input.kind == "secret" ? NSSecureTextField() : NSTextField()
                text.placeholderString = input.label
                text.widthAnchor.constraint(equalToConstant: 330).isActive = true
                inputs[input.id] = text
                stack.addArrangedSubview(label)
                stack.addArrangedSubview(text)
            }
            dialog.accessoryView = stack
        }
        guard dialog.runModal() == .alertFirstButtonReturn else { return }
        let values = inputs.mapValues(\.stringValue)
        do {
            try show(backend.apply(collectChanges(), actions: [ActionRequest(id: id, values: values)]))
        } catch {
            recoverAfterApplyFailure(error, backend: backend)
        }
    }

    private func recoverAfterApplyFailure(_ applyError: Error, backend: SettingsBackendClient) {
        let alert = NSAlert()
        alert.messageText = "設定の保存を完了できませんでした"
        do {
            show(try backend.snapshot())
            alert.informativeText = "一部の設定は保存されている可能性があります。現在の設定を再読み込みし、画面内の未保存入力は破棄しました。\n\n\(applyError.localizedDescription)"
        } catch let reloadError {
            canApply = false
            applyButtons.forEach { $0.isEnabled = false }
            alert.informativeText = "一部の設定は保存されている可能性があります。再読み込みにも失敗したため、画面の値は現在の設定と異なる場合があります。再読み込みが成功するまで保存と追加はできません。\n\n保存: \(applyError.localizedDescription)\n再読み込み: \(reloadError.localizedDescription)"
        }
        alert.runModal()
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

private let application = NSApplication.shared
private let controller = SettingsWindowController()
application.delegate = controller
application.setActivationPolicy(.regular)
application.run()
