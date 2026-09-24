import AppKit
import UniformTypeIdentifiers

private func settingsLabel(_ text: String, frame: NSRect, size: CGFloat = 13) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.frame = frame
    label.font = .systemFont(ofSize: size)
    return label
}

final class ShortcutEditor: NSView {
    var onChange: ((KeyboardMapping) -> Void)?
    private(set) var value = KeyboardMapping(keyCode: 0x24)
    private let keyPicker = NSPopUpButton(frame: NSRect(x: 0, y: 58, width: 192, height: 28))
    private let recordButton = NSButton(frame: NSRect(x: 208, y: 58, width: 174, height: 28))
    private let summary = settingsLabel("", frame: NSRect(x: 396, y: 61, width: 188, height: 22), size: 14)
    private var modifiers: [(CGEventFlags, NSButton)] = []
    private var monitor: Any?
    private var modifierCandidate: KeyboardMapping?

    override init(frame: NSRect) {
        super.init(frame: frame)
        for (name, code) in MacKey.choices {
            keyPicker.addItem(withTitle: name)
            keyPicker.lastItem?.tag = Int(code)
        }
        keyPicker.target = self
        keyPicker.action = #selector(changed)
        keyPicker.setAccessibilityLabel(L10n.tr("目标按键"))
        addSubview(keyPicker)
        recordButton.title = L10n.tr("录制快捷键…")
        recordButton.bezelStyle = .rounded
        recordButton.target = self
        recordButton.action = #selector(toggleRecording)
        addSubview(recordButton)
        summary.alignment = .right
        addSubview(summary)
        let definitions: [(CGEventFlags, String, CGFloat)] = [
            (.maskCommand,"⌘ Command",116),(.maskControl,"⌃ Control",110),
            (.maskAlternate,"⌥ Option",108),(.maskShift,"⇧ Shift",100),(.maskSecondaryFn,"Fn",64)
        ]
        var x: CGFloat = 0
        for (flag, title, width) in definitions {
            let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(changed))
            button.frame = NSRect(x: x, y: 21, width: width, height: 24)
            addSubview(button)
            modifiers.append((flag, button))
            x += width
        }
        setValue(value)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setValue(_ mapping: KeyboardMapping) {
        finishRecording()
        value = mapping
        if keyPicker.indexOfItem(withTag: Int(mapping.keyCode)) < 0 {
            keyPicker.addItem(withTitle: "Key \(mapping.keyCode)")
            keyPicker.lastItem?.tag = Int(mapping.keyCode)
        }
        keyPicker.selectItem(withTag: Int(mapping.keyCode))
        for (flag, button) in modifiers {
            button.state = mapping.flags.contains(flag) ? .on : .off
        }
        updateDisplay()
    }
    private func updateDisplay() {
        for (flag, button) in modifiers {
            button.isEnabled = KeyboardMapping.modifierFlag(for: value.keyCode) != flag
            if !button.isEnabled { button.state = .off }
        }
        summary.stringValue = value.displayName
    }
    @objc private func changed() {
        finishRecording()
        let code = UInt16(keyPicker.selectedTag())
        var flags: CGEventFlags = []
        for (flag, button) in modifiers where button.state == .on { flags.insert(flag) }
        if let own = KeyboardMapping.modifierFlag(for: code) { flags.remove(own) }
        value = KeyboardMapping(keyCode: code, modifiers: flags.rawValue)
        updateDisplay()
        onChange?(value)
    }
    @objc private func toggleRecording() {
        if monitor != nil { finishRecording(); return }
        modifierCandidate = nil
        recordButton.title = L10n.tr("录制中…点此取消")
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            let flags = UInt64(event.modifierFlags.rawValue) & KeyboardMapping.allowedModifiers
            if event.type == .keyDown {
                let mapping = KeyboardMapping.recorded(keyCode: event.keyCode, eventModifiers: flags)
                self.setValue(mapping)
                self.onChange?(mapping)
            } else if let own = KeyboardMapping.modifierFlag(for: event.keyCode) {
                if flags == 0, let candidate = self.modifierCandidate {
                    self.setValue(candidate)
                    self.onChange?(candidate)
                } else if CGEventFlags(rawValue: flags).contains(own) {
                    self.modifierCandidate = KeyboardMapping(keyCode: event.keyCode, modifiers: flags & ~own.rawValue)
                }
            }
            return nil
        }
    }
    func finishRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        modifierCandidate = nil
        recordButton.title = L10n.tr("录制快捷键…")
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}

final class ActionEditor: NSView, NSTextFieldDelegate {
    var onChange: ((MappedAction) -> Void)?
    private let kinds = MappedAction.Kind.allCases
    private let kindPicker = NSPopUpButton(frame: NSRect(x: 80, y: 154, width: 242, height: 28))
    let shortcut = ShortcutEditor(frame: NSRect(x: 0, y: 35, width: 588, height: 104))
    private let valueField = NSTextField(frame: NSRect(x: 0, y: 87, width: 438, height: 26))
    private let chooseButton = NSButton(frame: NSRect(x: 450, y: 84, width: 138, height: 32))
    private let note = settingsLabel("", frame: NSRect(x: 0, y: 0, width: 588, height: 40), size: 12)

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(settingsLabel(L10n.tr("执行动作"), frame: NSRect(x: 0, y: 158, width: 76, height: 22)))
        for kind in kinds { kindPicker.addItem(withTitle: kind.title) }
        kindPicker.target = self
        kindPicker.action = #selector(kindChanged)
        kindPicker.setAccessibilityLabel(L10n.tr("执行动作"))
        addSubview(kindPicker)
        shortcut.onChange = { [weak self] _ in self?.emitChange() }
        addSubview(shortcut)
        valueField.delegate = self
        valueField.setAccessibilityLabel(L10n.tr("应用路径或网址"))
        addSubview(valueField)
        chooseButton.title = L10n.tr("选择应用…")
        chooseButton.bezelStyle = .rounded
        chooseButton.target = self
        chooseButton.action = #selector(chooseApplication)
        addSubview(chooseButton)
        note.textColor = .secondaryLabelColor
        addSubview(note)
        setValue(.disabled)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    var value: MappedAction {
        let kind = kinds[kindPicker.indexOfSelectedItem]
        return MappedAction(kind: kind, shortcut: kind == .keyboard ? shortcut.value : nil,
            value: [.application, .website].contains(kind) ? valueField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
    }
    func setValue(_ action: MappedAction) {
        kindPicker.selectItem(at: kinds.firstIndex(of: action.kind) ?? 0)
        shortcut.setValue(action.shortcut ?? KeyboardMapping(keyCode: 0x24))
        valueField.stringValue = action.value ?? ""
        refresh()
    }
    @objc private func kindChanged() { shortcut.finishRecording(); refresh(); emitChange() }
    private func refresh() {
        let kind = kinds[kindPicker.indexOfSelectedItem]
        shortcut.isHidden = kind != .keyboard
        valueField.isHidden = kind != .application && kind != .website
        chooseButton.isHidden = kind != .application
        valueField.frame.size.width = kind == .application ? 438 : 588
        valueField.placeholderString = kind == .website ? "https://example.com" : L10n.tr("选择要打开的 .app 应用")
        switch kind {
        case .keyboard: note.stringValue = L10n.tr("点击录制后按组合键，或直接选择目标按键与修饰键。Fn 组合也可手动勾选。")
        case .application: note.stringValue = L10n.tr("按下遥控器时，打开或切换到这个应用。")
        case .website: note.stringValue = L10n.tr("使用默认浏览器打开网址。支持 http:// 和 https://。")
        default: note.stringValue = L10n.tr("每次按下执行这一项动作。")
        }
    }
    func controlTextDidChange(_ obj: Notification) { emitChange() }
    private func emitChange() { onChange?(value) }
    @objc private func chooseApplication() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.valueField.stringValue = url.path
            self?.emitChange()
        }
    }
}

private final class MappingRowCell: NSTableCellView {
    let detail = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        let title = NSTextField(labelWithString: "")
        title.frame = NSRect(x: 8, y: 5, width: 102, height: 20)
        title.font = .systemFont(ofSize: 13)
        textField = title
        addSubview(title)
        detail.frame = NSRect(x: 108, y: 5, width: 82, height: 20)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .right
        detail.lineBreakMode = .byTruncatingMiddle
        addSubview(detail)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class MappingSettingsWindow: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onVisibilityChange: ((Bool) -> Void)?
    var onRemoteSettings: (() -> Void)?
    private let store: MappingStore
    private var draft: MappingConfiguration
    private let table = NSTableView()
    private let editorTitle = settingsLabel("", frame: NSRect(x: 260, y: 522, width: 590, height: 30), size: 22)
    private let editorNote = settingsLabel("", frame: NSRect(x: 260, y: 470, width: 590, height: 42))
    private let actionEditor = ActionEditor(frame: NSRect(x: 260, y: 262, width: 590, height: 190))
    private let voiceView = NSView(frame: NSRect(x: 260, y: 194, width: 590, height: 265))
    private let voiceToggle = ShortcutEditor(frame: NSRect(x: 0, y: 134, width: 590, height: 100))
    private let voiceHold = ShortcutEditor(frame: NSRect(x: 0, y: 0, width: 590, height: 100))
    private let errorLabel = settingsLabel("", frame: NSRect(x: 260, y: 108, width: 590, height: 70))
    private let recentLabel = settingsLabel(L10n.tr("按一下遥控器上的键，可定位对应设置。"), frame: NSRect(x: 24, y: 73, width: 832, height: 24))
    private var pressTimes: [String: TimeInterval] = [:]
    private var showing = false

    init(store: MappingStore = .shared) {
        self.store = store
        draft = store.configuration
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 660),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = L10n.tr("RemoteBuddy · 按键设置")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        window.center()
        build()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func build() {
        guard let content = window?.contentView else { return }
        content.addSubview(settingsLabel(L10n.tr("按键设置"), frame: NSRect(x: 24, y: 610, width: 832, height: 32), size: 24))
        let remote = NSButton(title: L10n.tr("遥控器设置…"), target: self, action: #selector(openRemoteSettings))
        remote.frame = NSRect(x: 706, y: 610, width: 150, height: 32)
        remote.bezelStyle = .rounded
        content.addSubview(remote)
        let intro = settingsLabel(L10n.tr("为每个按键选择动作。保存后立即生效，重启也会保留。"), frame: NSRect(x: 24, y: 579, width: 832, height: 24))
        intro.textColor = .secondaryLabelColor
        content.addSubview(intro)
        let scroll = NSScrollView(frame: NSRect(x: 24, y: 109, width: 210, height: 453))
        // Keep scrolling available without showing bars, including on Macs
        // whose system preference is "Always show scroll bars".
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .bezelBorder
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("key"))
        column.width = 198
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 28
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.dataSource = self
        table.delegate = self
        table.allowsEmptySelection = false
        table.setAccessibilityLabel(L10n.tr("遥控器按键"))
        scroll.documentView = table
        content.addSubview(scroll)
        content.addSubview(editorTitle)
        editorNote.textColor = .secondaryLabelColor
        content.addSubview(editorNote)
        content.addSubview(actionEditor)
        voiceView.addSubview(settingsLabel(L10n.tr("短按切换收音时的快捷键"), frame: NSRect(x: 0, y: 237, width: 588, height: 24)))
        voiceView.addSubview(voiceToggle)
        voiceView.addSubview(settingsLabel(L10n.tr("按住说话时保持的按键"), frame: NSRect(x: 0, y: 103, width: 588, height: 24)))
        voiceView.addSubview(voiceHold)
        content.addSubview(voiceView)
        errorLabel.textColor = .systemRed
        content.addSubview(errorLabel)
        content.addSubview(recentLabel)
        let hint = settingsLabel(L10n.tr("设置窗口打开时，遥控器只用于识别按键；关闭窗口后恢复执行。"), frame: NSRect(x: 24, y: 51, width: 832, height: 18), size: 11)
        hint.textColor = .secondaryLabelColor
        content.addSubview(hint)
        let restore = NSButton(title: L10n.tr("恢复初始映射"), target: self, action: #selector(restoreDefaults))
        restore.frame = NSRect(x: 24, y: 12, width: 140, height: 32)
        restore.bezelStyle = .rounded
        content.addSubview(restore)
        let cancel = NSButton(title: L10n.tr("取消"), target: self, action: #selector(cancel))
        cancel.frame = NSRect(x: 637, y: 12, width: 90, height: 32)
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        content.addSubview(cancel)
        let save = NSButton(title: L10n.tr("保存并应用"), target: self, action: #selector(save))
        save.frame = NSRect(x: 735, y: 12, width: 122, height: 32)
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        content.addSubview(save)
        actionEditor.onChange = { [weak self] action in
            guard let self, (0..<RemoteKeyDefinition.all.count).contains(self.table.selectedRow) else { return }
            self.draft.buttons[String(RemoteKeyDefinition.all[self.table.selectedRow].id)] = action
            self.table.reloadData()
            self.errorLabel.stringValue = ""
        }
        voiceToggle.onChange = { [weak self] in self?.draft.voiceToggle = $0 }
        voiceHold.onChange = { [weak self] in self?.draft.voiceHold = $0 }
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        showSelection()
    }
    func present() {
        if !showing {
            draft = store.configuration
            errorLabel.stringValue = store.loadError.map { L10n.format("配置读取失败，当前显示初始映射：%@", $0) } ?? ""
            table.reloadData()
            showSelection()
            showing = true
            onVisibilityChange?(true)
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { RemoteKeyDefinition.all.count + 1 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = MappingRowCell(frame: NSRect(x: 0, y: 0, width: 198, height: 28))
        if row == RemoteKeyDefinition.all.count {
            cell.textField?.stringValue = L10n.tr("语音键")
            cell.detail.stringValue = L10n.tr("收音快捷键")
        } else {
            let definition = RemoteKeyDefinition.all[row]
            cell.textField?.stringValue = definition.title
            cell.detail.stringValue = draft.action(for: definition.id).title
        }
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) { showSelection() }
    private func showSelection() {
        actionEditor.shortcut.finishRecording()
        voiceToggle.finishRecording()
        voiceHold.finishRecording()
        let isVoice = table.selectedRow == RemoteKeyDefinition.all.count
        actionEditor.isHidden = isVoice
        voiceView.isHidden = !isVoice
        if isVoice {
            editorTitle.stringValue = L10n.tr("语音键")
            editorNote.stringValue = L10n.tr("保留当前麦克风逻辑：短按开始 / 结束收音，按住说话。这里只修改触发的快捷键。")
            voiceToggle.setValue(draft.voiceToggle)
            voiceHold.setValue(draft.voiceHold)
        } else if (0..<RemoteKeyDefinition.all.count).contains(table.selectedRow) {
            let definition = RemoteKeyDefinition.all[table.selectedRow]
            editorTitle.stringValue = definition.title
            editorNote.stringValue = L10n.tr("按住会重复执行当前动作，约2秒后自动停止；松开再按可继续。")
            actionEditor.setValue(draft.action(for: definition.id))
        }
    }
    func noteActivity(button: UInt8?, pressed: Bool) {
        guard showing else { return }
        if let button, !RemoteKeyDefinition.all.contains(where: { $0.id == button }) { return }
        let id = button.map(String.init) ?? "voice"
        let row = button.flatMap { code in RemoteKeyDefinition.all.firstIndex(where: { $0.id == code }) } ?? RemoteKeyDefinition.all.count
        let name = button.flatMap { code in RemoteKeyDefinition.all.first(where: { $0.id == code })?.title } ?? L10n.tr("语音键")
        if pressed {
            pressTimes[id] = ProcessInfo.processInfo.systemUptime
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
            recentLabel.stringValue = L10n.format("已识别：%@ · 按下", name)
        } else {
            let elapsed = ProcessInfo.processInfo.systemUptime - (pressTimes.removeValue(forKey: id) ?? ProcessInfo.processInfo.systemUptime)
            recentLabel.stringValue = L10n.format("已识别：%@ · 已松开（%.2f 秒）", name, elapsed)
        }
    }
    @objc private func restoreDefaults() { draft = .defaults; table.reloadData(); showSelection(); errorLabel.stringValue = L10n.tr("已恢复初始映射，点击保存后应用。") }
    @objc private func openRemoteSettings() { onRemoteSettings?() }
    @objc private func cancel() { window?.close() }
    @objc private func save() {
        window?.makeFirstResponder(nil)
        do { try store.save(draft); window?.close() }
        catch { errorLabel.stringValue = error.localizedDescription }
    }
    func windowWillClose(_ notification: Notification) {
        actionEditor.shortcut.finishRecording()
        voiceToggle.finishRecording()
        voiceHold.finishRecording()
        showing = false
        pressTimes.removeAll()
        onVisibilityChange?(false)
    }
    func renderPreview(to url: URL, voice: Bool = false) throws {
        guard let window, let content = window.contentView else { return }
        if voice {
            table.selectRowIndexes(IndexSet(integer: RemoteKeyDefinition.all.count), byExtendingSelection: false)
            table.scrollRowToVisible(RemoteKeyDefinition.all.count)
            showSelection()
        }
        window.orderFront(nil)
        content.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let image = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: image)
        try image.representation(using: .png, properties: [:])?.write(to: url)
        window.close()
    }
}
