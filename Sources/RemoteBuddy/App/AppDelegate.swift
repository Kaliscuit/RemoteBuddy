import AppKit
import Foundation
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "local.codex.RemoteMic", category: "status")
    private let audio = AudioOutput()
    private let buttons = RemoteButtonController()
    private var bluetooth: BLEController?
    private var coreHIDProbe: AnyObject?
    private let hciSource = HCIReportSource()
    private let hciService = HCISocketSource()
    private var mappingWindow: MappingSettingsWindow?
    private var remoteWindow: RemoteSettingsWindow?
    private var mappingSettingsVisible = false
    private var remoteSettingsVisible = false
    private var renderingPreview = false
    private var statusItem: NSStatusItem!
    private lazy var statusIcon: NSImage? = {
        let image = (NSImage(named: "StatusBarTemplate")?.copy() as? NSImage)
            ?? NSImage(systemSymbolName: "mic", accessibilityDescription: "RemoteBuddy")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        return image
    }()
    private let stateItem = NSMenuItem(title: L10n.tr("正在启动…"), action: nil, keyEquivalent: "")
    private let buttonStateItem = NSMenuItem(
        title: L10n.tr("按键：正在连接遥控器…"),
        action: nil,
        keyEquivalent: ""
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--render-remote-settings"),
           CommandLine.arguments.indices.contains(index + 1) {
            renderingPreview = true
            let sample = DiscoveredRemote(name: "Chromecast Remote", address: "AA:BB:CC:DD:EE:FF",
                peripheralID: UUID(uuidString: "11111111-2222-3333-4444-555555555555"),
                manufacturer: "zhuhai_jieli", model: "hid_mouse", firmware: "0.0.1", vendorID: 0x18d1, productID: 0x9450)
            let preview = RemoteSettingsWindow(discover: { [sample] }, load: {
                if CommandLine.arguments.contains("--preview-remote-manual") {
                    return try? RemoteConfiguration(address: sample.address, attribute: 0x2b,
                        reportFormat: .consumer16, peripheralID: sample.peripheralID)
                }
                return try? sample.automaticConfiguration()
            })
            remoteWindow = preview
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                do { try preview.renderPreview(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
                catch { print(error.localizedDescription) }
                NSApplication.shared.terminate(nil)
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-settings"),
           CommandLine.arguments.indices.contains(index + 1) {
            renderingPreview = true
            let preview = MappingSettingsWindow()
            mappingWindow = preview
            preview.showWindow(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                do {
                    try preview.renderPreview(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]),
                                              voice: CommandLine.arguments.contains("--preview-voice"))
                }
                catch { print(error.localizedDescription) }
                NSApplication.shared.terminate(nil)
            }
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
        let menu = NSMenu()
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        buttonStateItem.isEnabled = false
        menu.addItem(buttonStateItem)
        let mapping = NSMenuItem(title: L10n.tr("按键设置…"), action: #selector(openMappingSettings), keyEquivalent: ",")
        mapping.target = self
        menu.addItem(mapping)
        let remote = NSMenuItem(title: L10n.tr("遥控器设置…"), action: #selector(openRemoteSettings), keyEquivalent: "")
        remote.target = self
        menu.addItem(remote)
        menu.addItem(.separator())
        let sound = NSMenuItem(title: L10n.tr("打开声音设置…"), action: #selector(openSoundSettings), keyEquivalent: "")
        sound.target = self
        menu.addItem(sound)
        let accessibility = NSMenuItem(
            title: L10n.tr("打开辅助功能权限…"),
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibility.target = self
        menu.addItem(accessibility)
        let quit = NSMenuItem(title: L10n.tr("退出 RemoteBuddy"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu

        do {
            try audio.start()
            setStatus(L10n.format("音频：%@ · 正在连接遥控器…", audio.deviceName))
            startVoiceController()
            MappingStore.shared.willChange = { [weak self] in
                self?.buttons.mappingWillChange()
                self?.bluetooth?.prepareForMappingChange()
            }
            buttons.onButtonActivity = { [weak self] button, pressed in
                self?.mappingWindow?.noteActivity(button: button, pressed: pressed)
            }
            buttons.onStatus = { [weak self] in self?.setButtonStatus($0) }
            if CommandLine.arguments.contains("--diagnose-corehid"), #available(macOS 15, *) {
                let probe = CoreHIDProbe()
                probe.onStatus = { [weak self] in self?.setButtonStatus($0) }
                coreHIDProbe = probe
                probe.start()
            } else {
                buttons.start()
                if let index = CommandLine.arguments.firstIndex(of: "--hci-report-file"),
                   CommandLine.arguments.indices.contains(index + 1) {
                    buttons.setHCIBridge(true)
                    hciSource.onReport = { [weak self] in self?.buttons.handleHCIReport($0) }
                    hciSource.onStopped = { [weak self] in self?.buttons.setHCIBridge(false) }
                    let sourcePath = CommandLine.arguments[index + 1]
                    if hciSource.start(path: sourcePath) {
                        let trusted = KeyboardShortcutSender().isTrusted
                        logger.notice("HCI test accessibility trusted=\(trusted)")
                        try? Data("ready trusted=\(trusted)\n".utf8).write(to: URL(fileURLWithPath: sourcePath + ".ready"), options: .atomic)
                    }
                } else {
                    hciService.onReport = { [weak self] in self?.buttons.handleHCIReport($0) }
                    hciService.onActive = { [weak self] in self?.buttons.setHCIBridge($0) }
                    hciService.onReset = { [weak self] in self?.buttons.resetHCIButtons() }
                    hciService.onStatus = { [weak self] in self?.setButtonStatus($0) }
                    hciService.start()
                }
            }
            let keyboard = KeyboardShortcutSender()
            if !keyboard.requestAccessibilityIfNeeded() {
                logger.notice("Allow RemoteBuddy to control this computer in System Settings")
            }
        } catch {
            setStatus(error.localizedDescription)
            updateStatusIcon(failed: true)
        }
    }

    private func setStatus(_ text: String) {
        logger.notice("\(text, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            self?.stateItem.title = text
            self?.statusItem.button?.toolTip = "RemoteBuddy · \(text)"
        }
    }

    private func updateStatusIcon(streaming: Bool = false, failed: Bool = false) {
        guard let button = statusItem?.button else { return }
        button.title = ""
        button.image = statusIcon
        button.imagePosition = .imageOnly
        button.contentTintColor = failed ? .systemOrange : (streaming ? .systemRed : nil)
        button.setAccessibilityLabel(streaming ? L10n.tr("RemoteBuddy，正在收音") : "RemoteBuddy")
    }

    private func setButtonStatus(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.buttonStateItem.title = text
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if renderingPreview { return .terminateNow }
        bluetooth?.stop()
        // Fn+Space consists of events scheduled over 70 ms. Let its release
        // finish before exiting so WeChat input is not left recording/holding Fn.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        bluetooth?.stop()
        audio.stop()
        buttons.stop()
        hciSource.stop()
        hciService.stop()
        if #available(macOS 15, *) { (coreHIDProbe as? CoreHIDProbe)?.stop() }
    }

    @objc private func openSoundSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    @objc private func openMappingSettings() {
        if mappingWindow == nil {
            let window = MappingSettingsWindow()
            window.onVisibilityChange = { [weak self] visible in
                self?.mappingSettingsVisible = visible
                self?.updateSettingsActivity()
            }
            window.onRemoteSettings = { [weak self] in self?.openRemoteSettings() }
            mappingWindow = window
        }
        mappingWindow?.present()
    }

    private func startVoiceController() {
        let controller = BLEController(audio: audio)
        controller.onStatus = { [weak self] in self?.setStatus($0) }
        controller.onStreaming = { [weak self] in self?.updateStatusIcon(streaming: $0) }
        controller.onVoiceButtonActivity = { [weak self] in self?.mappingWindow?.noteActivity(button: nil, pressed: $0) }
        controller.shortcutsSuspended = mappingSettingsVisible || remoteSettingsVisible
        bluetooth = controller
    }

    private func updateSettingsActivity() {
        let visible = mappingSettingsVisible || remoteSettingsVisible
        buttons.setConfiguring(visible)
        bluetooth?.setConfiguring(visible)
    }

    @objc private func openRemoteSettings() {
        if remoteWindow == nil {
            let window = RemoteSettingsWindow()
            window.onVisibilityChange = { [weak self] visible in
                self?.remoteSettingsVisible = visible
                self?.updateSettingsActivity()
            }
            window.onApply = { [weak self] value, completion in
                self?.applyRemoteConfiguration(value, completion: completion)
            }
            remoteWindow = window
        }
        remoteWindow?.present()
    }

    private func applyRemoteConfiguration(_ value: RemoteConfiguration,
                                         completion: @escaping (Result<RemoteConfiguration, Error>) -> Void) {
        hciService.configure(value) { [weak self] response in
            guard let self else { return }
            // Read back the root-owned file. This also handles a lost socket
            // acknowledgement after the atomic write succeeded.
            guard RemoteIdentity.configuration == value else {
                if case .failure(let error) = response { completion(.failure(error)) }
                else { completion(.failure(RemoteSettingsError.saveFailed)) }
                return
            }
            self.bluetooth?.stop()
            self.bluetooth = nil
            self.hciService.stop()
            self.buttons.start()
            self.buttons.setConfiguring(self.mappingSettingsVisible || self.remoteSettingsVisible)
            self.startVoiceController()
            self.hciService.start()
            completion(.success(value))
        }
    }

}
