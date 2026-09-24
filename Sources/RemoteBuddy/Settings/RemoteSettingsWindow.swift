import AppKit

final class RemoteSettingsWindow: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    var onVisibilityChange: ((Bool) -> Void)?
    var onApply: ((RemoteConfiguration, @escaping (Result<RemoteConfiguration, Error>) -> Void) -> Void)?
    private let discover: () -> [DiscoveredRemote]
    private let load: () -> RemoteConfiguration?
    private var devices: [DiscoveredRemote] = []
    private var showing = false
    private var saving = false
    private let picker = NSPopUpButton(frame: NSRect(x: 130, y: 462, width: 470, height: 30))
    private let address = NSTextField(frame: NSRect(x: 130, y: 410, width: 470, height: 28))
    private let automatic = NSButton(checkboxWithTitle: L10n.tr("自动识别兼容参数"), target: nil, action: nil)
    private let format = NSPopUpButton(frame: NSRect(x: 130, y: 210, width: 220, height: 28))
    private let attribute = NSTextField(frame: NSRect(x: 484, y: 210, width: 116, height: 26))
    private let details = NSTextField(wrappingLabelWithString: "")
    private let result = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let refreshButton = NSButton(title: L10n.tr("刷新设备"), target: nil, action: nil)
    private let saveButton = NSButton(title: L10n.tr("保存并连接"), target: nil, action: nil)
    private let protocolLabel = NSTextField(labelWithString: L10n.tr("报告格式"))
    private let handleLabel = NSTextField(labelWithString: L10n.tr("按键句柄"))

    init(discover: @escaping () -> [DiscoveredRemote] = RemoteDeviceDiscovery.connectedRemotes,
         load: @escaping () -> RemoteConfiguration? = { RemoteIdentity.configuration }) {
        self.discover = discover
        self.load = load
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 610),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = L10n.tr("RemoteBuddy · 遥控器设置")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        window.center()
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func label(_ text: String, _ frame: NSRect, size: CGFloat = 13, secondary: Bool = false) {
        let view = NSTextField(wrappingLabelWithString: text)
        view.frame = frame
        view.font = .systemFont(ofSize: size)
        if secondary { view.textColor = .secondaryLabelColor }
        window?.contentView?.addSubview(view)
    }

    private func build() {
        guard let content = window?.contentView else { return }
        label(L10n.tr("选择遥控器"), NSRect(x: 24, y: 550, width: 710, height: 34), size: 24)
        label(L10n.tr("先在系统蓝牙设置中配对并连接遥控器，然后刷新列表。也可手动填写蓝牙地址。"),
              NSRect(x: 24, y: 506, width: 710, height: 38), secondary: true)
        label(L10n.tr("已连接设备"), NSRect(x: 24, y: 456, width: 100, height: 36))
        picker.target = self
        picker.action = #selector(selectedDevice)
        picker.setAccessibilityLabel(L10n.tr("已连接设备"))
        content.addSubview(picker)
        refreshButton.frame = NSRect(x: 620, y: 462, width: 116, height: 30)
        refreshButton.bezelStyle = .rounded
        refreshButton.target = self
        refreshButton.action = #selector(refresh)
        content.addSubview(refreshButton)
        label(L10n.tr("蓝牙地址"), NSRect(x: 24, y: 402, width: 100, height: 36))
        address.placeholderString = "AA:BB:CC:DD:EE:FF"
        address.setAccessibilityLabel(L10n.tr("蓝牙地址"))
        address.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        address.delegate = self
        content.addSubview(address)
        details.frame = NSRect(x: 130, y: 314, width: 600, height: 74)
        details.font = .systemFont(ofSize: 13)
        details.textColor = .secondaryLabelColor
        content.addSubview(details)
        automatic.frame = NSRect(x: 24, y: 278, width: 700, height: 26)
        automatic.target = self
        automatic.action = #selector(modeChanged)
        content.addSubview(automatic)
        result.frame = NSRect(x: 130, y: 246, width: 590, height: 28)
        result.font = .systemFont(ofSize: 13)
        content.addSubview(result)
        // Protocol details are editable only when automatic recognition is off.
        protocolLabel.frame = NSRect(x: 24, y: 214, width: 100, height: 22)
        handleLabel.frame = NSRect(x: 380, y: 214, width: 100, height: 22)
        for view in [protocolLabel, handleLabel, format, attribute] { content.addSubview(view) }
        format.addItems(withTitles: RemoteReportFormat.allCases.map(\.rawValue))
        format.setAccessibilityLabel(L10n.tr("报告格式"))
        attribute.setAccessibilityLabel(L10n.tr("按键句柄"))
        attribute.placeholderString = "0x46"
        status.frame = NSRect(x: 24, y: 100, width: 710, height: 82)
        status.font = .systemFont(ofSize: 13)
        content.addSubview(status)
        label(L10n.tr("保存后按键和语音一起切换，原有按键映射会保留。关闭设置窗口后恢复使用。"),
              NSRect(x: 24, y: 57, width: 710, height: 34), size: 12, secondary: true)
        let bluetooth = NSButton(title: L10n.tr("打开蓝牙设置…"), target: self, action: #selector(openBluetooth))
        bluetooth.frame = NSRect(x: 24, y: 16, width: 220, height: 32)
        bluetooth.bezelStyle = .rounded
        content.addSubview(bluetooth)
        let close = NSButton(title: L10n.tr("关闭"), target: self, action: #selector(closeSettings))
        close.frame = NSRect(x: 502, y: 16, width: 90, height: 32)
        close.bezelStyle = .rounded
        close.keyEquivalent = "\u{1b}"
        content.addSubview(close)
        saveButton.frame = NSRect(x: 602, y: 16, width: 134, height: 32)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(save)
        content.addSubview(saveButton)
    }

    func present() {
        if !showing {
            showing = true
            let current = load()
            address.stringValue = current?.address ?? ""
            attribute.stringValue = String(format: "0x%02X", current?.attribute ?? 0x46)
            format.selectItem(at: RemoteReportFormat.allCases.firstIndex(of: current?.reportFormat ?? .indexed) ?? 0)
            automatic.state = current.map { $0.automatic ? .on : .off } ?? .on
            onVisibilityChange?(true)
            refresh()
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func refresh() {
        guard !saving else { return }
        devices = discover()
        picker.removeAllItems()
        picker.addItem(withTitle: L10n.tr("选择设备，或在下方填写地址"))
        for device in devices { picker.addItem(withTitle: "\(device.name) · \(device.address)") }
        showIdentity()
    }

    @objc private func selectedDevice() {
        let index = picker.indexOfSelectedItem - 1
        guard devices.indices.contains(index) else { return }
        address.stringValue = devices[index].address
        automatic.state = .on
        showIdentity()
    }

    func controlTextDidChange(_ obj: Notification) { showIdentity() }
    @objc private func modeChanged() { showIdentity() }

    private var selectedRemote: DiscoveredRemote? {
        devices.first { $0.address == RemoteConfiguration.enteredAddress(address.stringValue) }
    }

    private func showIdentity() {
        let remote = selectedRemote
        if let remote, let index = devices.firstIndex(of: remote) { picker.selectItem(at: index + 1) }
        else { picker.selectItem(at: 0) }
        let unknown = L10n.tr("未知")
        if let remote {
            details.stringValue = L10n.format("厂商：%@", remote.manufacturer.isEmpty ? unknown : remote.manufacturer) + "\n" +
                L10n.format("型号：%@", remote.model.isEmpty ? unknown : remote.model) + "\n" +
                L10n.format("固件：%@", remote.firmware.isEmpty ? unknown : remote.firmware)
        } else { details.stringValue = L10n.tr("设备未连接。连接后刷新即可读取厂商、型号和固件。") }
        let isAuto = automatic.state == .on
        format.isHidden = isAuto
        attribute.isHidden = isAuto
        protocolLabel.isHidden = isAuto
        handleLabel.isHidden = isAuto
        if isAuto, let profile = remote?.buttonProfile {
            attribute.stringValue = String(format: "0x%02X", profile.attribute)
            format.selectItem(at: RemoteReportFormat.allCases.firstIndex(of: profile.reportFormat) ?? 0)
            result.stringValue = L10n.format("已自动匹配：%@", profile.title)
            setStatus(L10n.tr("兼容参数已识别，可以保存并连接。"))
        } else if isAuto {
            result.stringValue = L10n.tr("尚未匹配兼容参数")
            setStatus(RemoteSettingsError.unknownDevice.localizedDescription, error: true)
        } else {
            result.stringValue = L10n.tr("手动配置 · 仅填写已确认的参数")
            setStatus(L10n.tr("手动模式可用于更换同型号遥控器的地址。不同型号建议先尝试自动识别。"))
        }
        saveButton.isEnabled = !saving && RemoteConfiguration.enteredAddress(address.stringValue) != nil && (!isAuto || remote?.buttonProfile != nil)
    }

    @objc private func save() {
        guard !saving else { return }
        window?.makeFirstResponder(nil)
        do {
            guard let normalized = RemoteConfiguration.enteredAddress(address.stringValue) else { throw RemoteSettingsError.invalidAddress }
            let value: RemoteConfiguration
            if automatic.state == .on {
                guard let selectedRemote else { throw RemoteSettingsError.unknownDevice }
                value = try selectedRemote.automaticConfiguration()
            } else {
                guard let handle = RemoteConfiguration.enteredAttribute(attribute.stringValue) else { throw RemoteSettingsError.invalidAttribute }
                let current = load()
                let identifier = selectedRemote?.peripheralID ?? (current?.address == normalized ? current?.peripheralID : nil)
                value = try RemoteConfiguration(address: normalized, attribute: handle,
                    reportFormat: RemoteReportFormat.allCases[format.indexOfSelectedItem], peripheralID: identifier)
            }
            guard let onApply else { throw RemoteSettingsError.unavailableService }
            setSaving(true)
            setStatus(L10n.tr("正在保存并切换遥控器…"))
            onApply(value) { [weak self] response in
                guard let self else { return }
                self.setSaving(false)
                switch response {
                case .success: self.setStatus(L10n.tr("已保存并开始连接。关闭设置窗口后即可使用。"))
                case .failure(let error): self.setStatus(error.localizedDescription, error: true)
                }
            }
        } catch { setStatus(error.localizedDescription, error: true) }
    }

    private func setSaving(_ value: Bool) {
        saving = value
        let controls: [NSControl] = [picker, address, automatic, format, attribute, refreshButton, saveButton]
        for control in controls { control.isEnabled = !value }
        window?.standardWindowButton(.closeButton)?.isEnabled = !value
    }

    private func setStatus(_ text: String, error: Bool = false) {
        status.stringValue = text
        status.textColor = error ? .systemRed : .secondaryLabelColor
    }

    @objc private func openBluetooth() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
    }
    @objc private func closeSettings() { if !saving { window?.close() } }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !saving }
    func windowWillClose(_ notification: Notification) { showing = false; onVisibilityChange?(false) }

    func renderPreview(to url: URL) throws {
        present()
        window?.makeFirstResponder(nil)
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.displayIfNeeded()
        guard let content = window?.contentView,
              let image = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: image)
        try image.representation(using: .png, properties: [:])?.write(to: url)
        window?.close()
    }
}
