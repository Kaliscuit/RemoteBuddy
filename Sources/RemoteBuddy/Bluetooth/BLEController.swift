import CoreBluetooth
import Foundation
import OSLog

final class BLEController: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onStatus: ((String) -> Void)?
    var onStreaming: ((Bool) -> Void)?
    var onVoiceButtonActivity: ((Bool) -> Void)?
    var shortcutsSuspended = false
    private let diagnostics = Logger(subsystem: "local.codex.RemoteMic", category: "device-info")
    private let deviceInformation = CBUUID(string: "180A")

    private let audio: AudioOutput
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var subscribed = Set<CBUUID>()
    private var session = ATVVSession()
    private var streaming = false
    private var keepAliveTimer: Timer?
    private var streamFrameCount = 0
    private var streamPeak = 0
    private var receivedAudioPackets = 0
    private let audioDiagnostics = Logger(subsystem: "local.codex.RemoteMic", category: "audio")
    private var voiceGesture = VoiceGestureStateMachine()
    private let keyboard = KeyboardShortcutSender()
    private var heldVoiceShortcut: KeyboardMapping?
    private var holdWorkItem: DispatchWorkItem?
    private static let holdThreshold: TimeInterval = 0.55

    private let service = CBUUID(string: ATVVSession.serviceUUID)
    private let command = CBUUID(string: ATVVSession.commandUUID)
    private let audioUUID = CBUUID(string: ATVVSession.audioUUID)
    private let control = CBUUID(string: ATVVSession.controlUUID)

    init(audio: AudioOutput) {
        self.audio = audio
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            onStatus?(L10n.tr("蓝牙未就绪"))
            return
        }
        reconnect()
    }

    private func reconnect() {
        onStatus?(L10n.tr("正在查找 Chromecast Remote…"))
        if let found = central.retrieveConnectedPeripherals(withServices: [service])
            .first(where: { $0.name?.localizedCaseInsensitiveContains("Chromecast Remote") == true }) {
            connect(found)
        } else {
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard peripheral.name?.localizedCaseInsensitiveContains("Chromecast Remote") == true else { return }
        connect(peripheral)
    }

    private func connect(_ device: CBPeripheral) {
        central.stopScan()
        peripheral = device
        device.delegate = self
        onStatus?(L10n.tr("正在连接遥控器…"))
        central.connect(device)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onStatus?(L10n.tr("正在初始化语音服务…"))
        commandCharacteristic = nil
        subscribed.removeAll()
        peripheral.discoverServices([service, deviceInformation])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onStatus?(L10n.tr("连接失败，正在重试…"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.reconnect() }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        timestamp: CFAbsoluteTime, isReconnecting: Bool, error: Error?) {
        holdWorkItem?.cancel()
        perform(voiceGesture.reset())
        finishStream()
        onStatus?(L10n.tr("遥控器已断开，正在重连…"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.reconnect() }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            onStatus?(L10n.tr("语音服务发现失败"))
            return
        }
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else { return }
        if service.uuid == deviceInformation {
            for item in characteristics where ["2A26", "2A27", "2A28", "2A24"].contains(item.uuid.uuidString) {
                peripheral.readValue(for: item)
            }
            return
        }
        for characteristic in characteristics {
            switch characteristic.uuid {
            case command:
                commandCharacteristic = characteristic
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            case audioUUID, control:
                peripheral.setNotifyValue(true, for: characteristic)
                subscribed.insert(characteristic.uuid)
            default:
                break
            }
        }
        if commandCharacteristic != nil, subscribed.contains(audioUUID), subscribed.contains(control) {
            write(session.capabilitiesRequest)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        if characteristic.service?.uuid == deviceInformation {
            diagnostics.notice("Live device info uuid=\(characteristic.uuid.uuidString, privacy: .public) value=\(String(data: data, encoding: .utf8) ?? data.description, privacy: .public)")
            return
        }
        if characteristic.uuid == audioUUID {
            receivedAudioPackets += 1
            if streaming, !shortcutsSuspended, let samples = session.decodeAudio(data), let codec = session.codec {
                streamFrameCount += 1
                streamPeak = max(streamPeak, samples.reduce(into: 0) { peak, sample in
                    peak = max(peak, abs(Int(sample)))
                })
                audio.feed(samples, sampleRate: codec.sampleRate)
            }
        } else if characteristic.uuid == control || characteristic.uuid == command {
            handle(session.parseControl(data))
        }
    }


    private func handle(_ event: ATVVEvent) {
        switch event {
        case .capabilities(let capabilities):
            guard session.accept(capabilities) else {
                onStatus?(L10n.tr("遥控器音频编码不受支持"))
                return
            }
            onStatus?(L10n.tr("已就绪 · 按住语音键说话"))
        case .startSearch:
            if !streaming {
                session.prepareOpen()
                if let value = session.openCommand() { write(value) }
            }
        case .audioSync(let codec, let sequence, let predictor, let stepIndex):
            session.applySync(codec: codec, sequence: sequence, predictor: predictor, stepIndex: stepIndex)
        case .audioStart(let reason, let codec, let streamID):
            if reason == 0x03 {
                onVoiceButtonActivity?(true)
                if !shortcutsSuspended {
                    perform(voiceGesture.pressDown())
                    scheduleHoldThreshold()
                }
            }
            session.begin(codec: codec, streamID: streamID)
            streaming = true
            streamFrameCount = 0
            streamPeak = 0
            receivedAudioPackets = 0
            audio.clear()
            audioDiagnostics.notice("Voice start suspended=\(self.shortcutsSuspended) \(self.audio.diagnosticSummary, privacy: .public)")
            startKeepAlive()
            onStreaming?(true)
            onStatus?(shortcutsSuspended ? L10n.tr("按键设置：正在识别语音键") : L10n.tr("正在传输遥控器麦克风"))
        case .audioStop(let reason):
            let frames = streamFrameCount
            let peak = streamPeak
            audioDiagnostics.notice("Voice stop reason=\(reason) packets=\(self.receivedAudioPackets) decodedFrames=\(frames) peak=\(peak) suspended=\(self.shortcutsSuspended) \(self.audio.diagnosticSummary, privacy: .public)")
            finishStream()
            if reason == 0x02 {
                onVoiceButtonActivity?(false)
                holdWorkItem?.cancel()
                holdWorkItem = nil
                perform(voiceGesture.pressUp())
            } else if frames > 0, peak > 0 {
                onStatus?(L10n.format("语音正常 · %@ 帧 · 峰值 %@", String(frames), String(peak)))
            } else {
                onStatus?(L10n.tr("语音流为空 · 请重试"))
            }
        case .error(let code):
            finishStream()
            onStatus?(L10n.format("遥控器拒绝打开麦克风 (0x%04X)", code))
        case .unknown:
            break
        }
    }

    private func write(_ data: Data) {
        guard let peripheral, let characteristic = commandCharacteristic else { return }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: type)
    }

    private func scheduleHoldThreshold() {
        holdWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.holdWorkItem = nil
            self.perform(self.voiceGesture.holdThresholdReached())
        }
        holdWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdThreshold, execute: work)
    }

    private func perform(_ actions: [VoiceGestureAction]) {
        for action in actions {
            switch action {
            case .fnDown:
                let shortcut = MappingStore.shared.configuration.voiceHold
                heldVoiceShortcut = shortcut
                keyboard.postShortcut(shortcut, isDown: true)
                onStatus?(L10n.format("长按说话中 · %@ 已按下", shortcut.displayName))
            case .fnUp:
                if let shortcut = heldVoiceShortcut { keyboard.postShortcut(shortcut, isDown: false) }
                heldVoiceShortcut = nil
                onStatus?(L10n.tr("长按结束 · 快捷键已松开"))
            case .fnSpace:
                keyboard.tapShortcut(MappingStore.shared.configuration.voiceToggle)
                onStatus?(voiceGesture.toggleActive ? L10n.tr("短按已开始 · 持续收音") : L10n.tr("短按已结束"))
            case .reopenMicrophone:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                    guard let self, self.voiceGesture.toggleActive, !self.shortcutsSuspended else { return }
                    self.session.prepareOpen()
                    if let command = self.session.openCommand() { self.write(command) }
                }
            case .closeMicrophone:
                if let command = session.closeCommand() { write(command) }
                audio.clear()
            }
        }
    }

    func prepareForMappingChange() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
        let wasActive = streaming || voiceGesture.toggleActive || heldVoiceShortcut != nil
        if voiceGesture.toggleActive {
            keyboard.tapShortcut(MappingStore.shared.configuration.voiceToggle)
        }
        let actions = voiceGesture.reset()
        if wasActive { perform(actions); finishStream() }
    }

    func setConfiguring(_ enabled: Bool) {
        prepareForMappingChange()
        shortcutsSuspended = enabled
        if enabled { onStatus?(L10n.tr("按键设置中 · 语音快捷键暂停")) }
        else { onStatus?(peripheral?.state == .connected ? L10n.tr("已就绪 · 按住语音键说话") : L10n.tr("正在等待遥控器连接…")) }
    }

    private func startKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            guard let self, let value = self.session.keepAliveCommand() else { return }
            self.write(value)
        }
    }

    private func finishStream() {
        streaming = false
        streamFrameCount = 0
        streamPeak = 0
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        audio.clear()
        onStreaming?(false)
    }
}
