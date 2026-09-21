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
    private var requestedCapabilities = false
    private var session = ATVVSession()
    private var streaming = false
    private var serviceTimer: DispatchSourceTimer?
    private var nextKeepAlive: TimeInterval = 0
    private var watchdog = VoiceSessionWatchdog()
    private var streamFrameCount = 0
    private var streamPeak = 0
    private var receivedAudioPackets = 0
    private var streamStartedAt: TimeInterval = 0
    private var firstPacketDelay: TimeInterval?
    private var previousPacketTime: TimeInterval?
    private var maxPacketGap: TimeInterval = 0
    private var decodedAudioDuration: TimeInterval = 0
    private var gainClippedSamples = 0
    private let audioDiagnostics = Logger(subsystem: "local.codex.RemoteMic", category: "audio")
    private var voiceGesture = VoiceGestureStateMachine()
    private let keyboard: VoiceKeyboard
    private let commandSink: ((Data) -> Void)?
    private var heldVoiceShortcut: KeyboardMapping?
    private var activeToggleShortcut: KeyboardMapping?
    private var holdWorkItem: DispatchWorkItem?
    private var reopenWorkItem: DispatchWorkItem?
    private var pendingShortcutStop: (() -> Void)?
    private var drainDeadline: TimeInterval = 0
    private static let holdThreshold: TimeInterval = 0.55

    private let service = CBUUID(string: ATVVSession.serviceUUID)
    private let command = CBUUID(string: ATVVSession.commandUUID)
    private let audioUUID = CBUUID(string: ATVVSession.audioUUID)
    private let control = CBUUID(string: ATVVSession.controlUUID)

    init(audio: AudioOutput, keyboard: VoiceKeyboard = KeyboardShortcutSender(),
         connectImmediately: Bool = true, commandSink: ((Data) -> Void)? = nil) {
        self.audio = audio
        self.keyboard = keyboard
        self.commandSink = commandSink
        super.init()
        if connectImmediately {
            central = CBCentralManager(delegate: self, queue: .main)
            // Dispatch timers continue while menu tracking changes the run-loop mode.
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
            timer.setEventHandler { [weak self] in self?.checkVoiceHealth() }
            serviceTimer = timer
            timer.resume()
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            resetVoice(closeMicrophone: false)
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
        requestedCapabilities = false
        session = ATVVSession()
        peripheral.discoverServices([service, deviceInformation])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onStatus?(L10n.tr("连接失败，正在重试…"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.reconnect() }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        timestamp: CFAbsoluteTime, isReconnecting: Bool, error: Error?) {
        handleDisconnection()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        handleDisconnection()
    }

    private func handleDisconnection() {
        resetVoice(closeMicrophone: false)
        commandCharacteristic = nil
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
            default:
                break
            }
        }
        requestCapabilitiesIfReady()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == audioUUID || characteristic.uuid == control else { return }
        guard error == nil, characteristic.isNotifying else {
            subscribed.remove(characteristic.uuid)
            resetVoice()
            return
        }
        subscribed.insert(characteristic.uuid)
        requestCapabilitiesIfReady()
    }

    private func requestCapabilitiesIfReady() {
        if !requestedCapabilities, commandCharacteristic != nil,
           subscribed.contains(audioUUID), subscribed.contains(control) {
            requestedCapabilities = true
            write(session.capabilitiesRequest)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            if characteristic.service?.uuid != deviceInformation { resetVoice() }
            return
        }
        guard let data = characteristic.value else { return }
        if characteristic.service?.uuid == deviceInformation {
            diagnostics.notice("Live device info uuid=\(characteristic.uuid.uuidString, privacy: .public) value=\(String(data: data, encoding: .utf8) ?? data.description, privacy: .public)")
            return
        }
        if characteristic.uuid == audioUUID {
            receiveAudio(data)
        } else if characteristic.uuid == control || characteristic.uuid == command {
            handle(session.parseControl(data))
        }
    }

    func receiveAudio(_ data: Data, at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        receivedAudioPackets += 1
        guard streaming, !shortcutsSuspended, let samples = session.decodeAudio(data), let codec = session.codec else { return }
        watchdog.receivedAudio(at: now)
        if firstPacketDelay == nil { firstPacketDelay = now - streamStartedAt }
        if let previousPacketTime { maxPacketGap = max(maxPacketGap, now - previousPacketTime) }
        previousPacketTime = now
        decodedAudioDuration += Double(samples.count) / Double(codec.sampleRate)
        gainClippedSamples += samples.reduce(0) { $0 + (abs(Int($1)) > 8192 ? 1 : 0) }
        streamFrameCount += 1
        streamPeak = max(streamPeak, samples.reduce(into: 0) { peak, sample in
            peak = max(peak, abs(Int(sample)))
        })
        audio.feed(samples, sampleRate: codec.sampleRate)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let error else { return }
        audioDiagnostics.error("ATVV write failed: \(error.localizedDescription, privacy: .public)")
        resetVoice(closeMicrophone: false)
    }

    func handle(_ event: ATVVEvent) {
        switch event {
        case .capabilities(let capabilities):
            guard session.accept(capabilities) else {
                onStatus?(L10n.tr("遥控器音频编码不受支持"))
                return
            }
            onStatus?(L10n.tr("已就绪 · 按住语音键说话"))
        case .startSearch:
            guard !shortcutsSuspended else { return }
            handleTap()
        case .audioSync(let codec, let sequence, let predictor, let stepIndex):
            audioDiagnostics.notice("Voice sync codec=\(codec.rawValue) sourceRate=\(codec.sampleRate) sequence=\(sequence)")
            session.applySync(codec: codec, sequence: sequence, predictor: predictor, stepIndex: stepIndex)
        case .audioStart(let reason, let codec, let streamID):
            if streaming, reason == 0x03, session.streamID == streamID { return }
            if reason == 0x03 {
                onVoiceButtonActivity?(true)
                if !shortcutsSuspended {
                    // A fresh remote stream is an authoritative new press, even
                    // if the previous release notification never reached us.
                    if voiceGesture.isPressed { resetVoice(closeMicrophone: false) }
                    cancelPendingWork()
                    if !voiceGesture.toggleActive {
                        finishPendingStop()
                        audio.beginCapture()
                    }
                    perform(voiceGesture.pressDown())
                    scheduleHoldThreshold()
                }
            } else if reason == 0x01, !shortcutsSuspended {
                handleTap(alreadyOpen: true)
            }
            if !shortcutsSuspended, !voiceGesture.isPressed, !voiceGesture.toggleActive {
                if let command = session.closeAllCommand() { write(command) }
                return
            }
            session.begin(codec: codec, streamID: streamID)
            streaming = true
            streamFrameCount = 0
            streamPeak = 0
            receivedAudioPackets = 0
            streamStartedAt = ProcessInfo.processInfo.systemUptime
            firstPacketDelay = nil
            previousPacketTime = nil
            maxPacketGap = 0
            decodedAudioDuration = 0
            gainClippedSamples = 0
            audioDiagnostics.notice("Voice start decoder=ATVV-high-first codec=\(codec.rawValue) sourceRate=\(codec.sampleRate) suspended=\(self.shortcutsSuspended) \(self.audio.diagnosticSummary, privacy: .public)")
            watchdog.awaitingStream(at: streamStartedAt)
            nextKeepAlive = streamStartedAt + 4
            onStreaming?(true)
            onStatus?(shortcutsSuspended ? L10n.tr("按键设置：正在识别语音键") : L10n.tr("正在传输遥控器麦克风"))
        case .audioStop(let reason):
            let frames = streamFrameCount
            let peak = streamPeak
            audioDiagnostics.notice("Voice stop reason=\(reason) packets=\(self.receivedAudioPackets) decodedFrames=\(frames) peak=\(peak) suspended=\(self.shortcutsSuspended) \(self.audio.diagnosticSummary, privacy: .public)")
            let elapsed = ProcessInfo.processInfo.systemUptime - streamStartedAt
            audioDiagnostics.notice("Voice quality durationMs=\(elapsed * 1000) decodedAudioMs=\(self.decodedAudioDuration * 1000) firstPacketMs=\((self.firstPacketDelay ?? -1) * 1000) maxPacketGapMs=\(self.maxPacketGap * 1000) gainClippedSamples=\(self.gainClippedSamples)")
            streaming = false
            session.end()
            if reason == 0x02 {
                onVoiceButtonActivity?(false)
                holdWorkItem?.cancel()
                holdWorkItem = nil
                perform(voiceGesture.pressUp())
                if !voiceGesture.toggleActive { watchdog.invalidate() }
                onStreaming?(voiceGesture.toggleActive || pendingShortcutStop != nil)
            } else if reason == 0x04 {
                // A replacement AUDIO_START follows; preserve the utterance.
                watchdog.awaitingStream(at: ProcessInfo.processInfo.systemUptime)
            } else if frames > 0, peak > 0 {
                finishUnexpectedStop()
                onStatus?(L10n.format("语音正常 · %@ 帧 · 峰值 %@", String(frames), String(peak)))
            } else {
                finishUnexpectedStop()
                onStatus?(L10n.tr("语音流为空 · 请重试"))
            }
        case .error(let code):
            if code == 0x0f80, streaming, voiceGesture.isPressed {
                // A late MIC_OPEN raced a real HTT press. Keep that live stream.
                reopenWorkItem?.cancel()
                reopenWorkItem = nil
                return
            }
            resetVoice()
            onStatus?(L10n.format("遥控器拒绝打开麦克风 (0x%04X)", code))
        case .unknown:
            break
        }
    }

    private func write(_ data: Data) {
        if let commandSink { commandSink(data); return }
        guard let peripheral, let characteristic = commandCharacteristic else { return }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: type)
    }

    private func scheduleHoldThreshold() {
        holdWorkItem?.cancel()
        let generation = watchdog.generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.watchdog.generation == generation else { return }
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
                keyboard.postShortcut(shortcut, isDown: true, autoRepeat: false)
                audio.startPlayback()
                onStatus?(L10n.format("长按说话中 · %@ 已按下", shortcut.displayName))
            case .fnUp:
                if let shortcut = heldVoiceShortcut {
                    stopAfterDraining { [keyboard] in keyboard.postShortcut(shortcut, isDown: false, autoRepeat: false) }
                }
                heldVoiceShortcut = nil
                onStatus?(L10n.tr("长按结束 · 快捷键已松开"))
            case .fnSpace:
                if let shortcut = activeToggleShortcut {
                    activeToggleShortcut = nil
                    stopAfterDraining { [keyboard] in keyboard.tapShortcut(shortcut) }
                    // End toggle recording on the press itself. A lost button
                    // release must not leave the remote streaming indefinitely.
                    watchdog.requestedStop(at: ProcessInfo.processInfo.systemUptime)
                    if let command = session.closeAllCommand() { write(command) }
                } else {
                    finishPendingStop()
                    let shortcut = MappingStore.shared.configuration.voiceToggle
                    activeToggleShortcut = shortcut
                    keyboard.tapShortcut(shortcut)
                    audio.startPlayback()
                }
                onStatus?(voiceGesture.toggleActive ? L10n.tr("短按已开始 · 持续收音") : L10n.tr("短按已结束"))
            case .reopenMicrophone:
                reopenWorkItem?.cancel()
                let generation = watchdog.generation
                watchdog.awaitingStream(at: ProcessInfo.processInfo.systemUptime)
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.watchdog.generation == generation,
                          self.voiceGesture.toggleActive, !self.shortcutsSuspended, !self.streaming else { return }
                    self.reopenWorkItem = nil
                    self.session.prepareOpen()
                    if let command = self.session.openCommand() { self.write(command) }
                }
                reopenWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
            case .closeMicrophone:
                cancelPendingWork()
                if streaming { watchdog.requestedStop(at: ProcessInfo.processInfo.systemUptime) }
                if let command = session.closeCommand() { write(command) }
                audio.endCapture()
            }
        }
    }

    func prepareForMappingChange() {
        resetVoice()
    }

    func setConfiguring(_ enabled: Bool) {
        prepareForMappingChange()
        shortcutsSuspended = enabled
        if enabled { onStatus?(L10n.tr("按键设置中 · 语音快捷键暂停")) }
        else { onStatus?(peripheral?.state == .connected ? L10n.tr("已就绪 · 按住语音键说话") : L10n.tr("正在等待遥控器连接…")) }
    }

    private func handleTap(alreadyOpen: Bool = false) {
        if voiceGesture.isPressed { resetVoice(closeMicrophone: false) }
        cancelPendingWork()
        if !voiceGesture.toggleActive {
            finishPendingStop()
            audio.beginCapture()
        }
        let actions = voiceGesture.pressDown() + voiceGesture.pressUp()
        perform(alreadyOpen ? actions.filter { $0 != .reopenMicrophone } : actions)
    }

    private func cancelPendingWork() {
        watchdog.invalidate()
        holdWorkItem?.cancel()
        holdWorkItem = nil
        reopenWorkItem?.cancel()
        reopenWorkItem = nil
    }

    private func stopAfterDraining(_ stop: @escaping () -> Void) {
        finishPendingStop()
        audio.endCapture()
        pendingShortcutStop = stop
        drainDeadline = ProcessInfo.processInfo.systemUptime + 2
    }

    private func finishPendingStop() {
        guard let stop = pendingShortcutStop else { return }
        pendingShortcutStop = nil
        stop()
        audio.clear()
        onStreaming?(false)
    }

    private func finishUnexpectedStop() {
        if !voiceGesture.toggleActive, heldVoiceShortcut == nil, pendingShortcutStop != nil {
            // Acknowledgement for our own close; let the queued tail drain.
            cancelPendingWork()
            _ = voiceGesture.reset()
        } else {
            resetVoice()
        }
    }

    func checkVoiceHealth(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if pendingShortcutStop != nil, audio.queuedSamples == 0 || now >= drainDeadline {
            finishPendingStop()
        }
        guard !shortcutsSuspended else { return }
        if watchdog.hasTimedOut(at: now) {
            audioDiagnostics.error("Voice transport timed out; resetting shortcuts and pending work")
            resetVoice()
            onStatus?(L10n.tr("语音连接超时，已复位 · 请重试"))
        } else if streaming, !watchdog.awaitingStop, now >= nextKeepAlive {
            nextKeepAlive = now + 4
            if let value = session.keepAliveCommand() { write(value) }
        }
    }

    private func resetVoice(closeMicrophone: Bool = true) {
        cancelPendingWork()
        finishPendingStop()
        if let shortcut = heldVoiceShortcut { keyboard.postShortcut(shortcut, isDown: false, autoRepeat: false) }
        heldVoiceShortcut = nil
        if let shortcut = activeToggleShortcut { keyboard.tapShortcut(shortcut) }
        activeToggleShortcut = nil
        _ = voiceGesture.reset()
        if closeMicrophone, let command = session.closeAllCommand() { write(command) }
        streaming = false
        session.end()
        streamFrameCount = 0
        streamPeak = 0
        audio.clear()
        onStreaming?(false)
    }

    func stop() {
        resetVoice()
        serviceTimer?.cancel()
        serviceTimer = nil
    }

    deinit {
        serviceTimer?.cancel()
        holdWorkItem?.cancel()
        reopenWorkItem?.cancel()
    }
}
