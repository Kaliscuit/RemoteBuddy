import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import OSLog

struct AudioRingSnapshot {
    let queued: Int
    let renderCalls: Int
    let rendered: Int
    let requested: Int
    let gated: Int
    let dropped: Int
    let playbackDue: Bool
}

final class SampleRing {
    private let lock = NSLock()
    private var storage = [Float](repeating: 0, count: 65_536)
    private var readIndex = 0
    private var writeIndex = 0
    private var count = 0
    private var renderCalls = 0
    private var renderedSamples = 0
    private var requestedSamples = 0
    private var gatedSamples = 0
    private var droppedSamples = 0
    private var accepting = false
    private var playbackAfter: TimeInterval?

    func beginCapture() {
        lock.lock()
        defer { lock.unlock() }
        reset()
        accepting = true
    }

    func startPlayback(at time: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        // Preserve the gate and prefix across HTT -> on-request stream changes.
        if playbackAfter == nil { playbackAfter = time }
    }

    func endCapture() {
        lock.lock()
        accepting = false
        lock.unlock()
    }

    func append(_ samples: [Int16], sampleRate: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard accepting else { return }
        let duplicate = sampleRate == 8_000 ? 2 : 1
        for sample in samples {
            let value = max(-1, min(1, Float(sample) / 8192.0))
            for _ in 0..<duplicate {
                storage[writeIndex] = value
                writeIndex = (writeIndex + 1) % storage.count
                if count == storage.count {
                    readIndex = (readIndex + 1) % storage.count
                    droppedSamples += 1
                } else {
                    count += 1
                }
            }
        }
    }

    func read(into pointer: UnsafeMutablePointer<Float>, count requested: Int,
              now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lock.lock()
        defer { lock.unlock() }
        renderCalls += 1
        requestedSamples += requested
        guard let playbackAfter, now >= playbackAfter else {
            pointer.update(repeating: 0, count: requested)
            gatedSamples += requested
            return
        }
        renderedSamples += min(count, requested)
        for index in 0..<requested {
            if count > 0 {
                pointer[index] = storage[readIndex]
                readIndex = (readIndex + 1) % storage.count
                count -= 1
            } else {
                pointer[index] = 0
            }
        }
    }

    func clear() {
        lock.lock()
        reset()
        lock.unlock()
    }

    private func reset() {
        readIndex = 0
        writeIndex = 0
        count = 0
        renderCalls = 0
        renderedSamples = 0
        requestedSamples = 0
        gatedSamples = 0
        droppedSamples = 0
        accepting = false
        playbackAfter = nil
    }

    func snapshot(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> AudioRingSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return AudioRingSnapshot(queued: count, renderCalls: renderCalls, rendered: renderedSamples,
                                 requested: requestedSamples, gated: gatedSamples, dropped: droppedSamples,
                                 playbackDue: playbackAfter.map { now >= $0 } ?? false)
    }

    var diagnosticSummary: String {
        let s = snapshot()
        return "queued=\(s.queued) renderCalls=\(s.renderCalls) renderedSamples=\(s.rendered) requestedSamples=\(s.requested) zeroFilledSamples=\(s.requested - s.rendered - s.gated) startupSilenceSamples=\(s.gated) overflowSamples=\(s.dropped)"
    }
}

struct AudioRecoveryMonitor {
    private var previousRenderCalls = -1
    private var lastProgress: TimeInterval = 0
    private var nextAttempt: TimeInterval = 0

    mutating func needsRecovery(running: Bool, correctDevice: Bool, renderCalls: Int,
                                audioPending: Bool, now: TimeInterval) -> Bool {
        if renderCalls != previousRenderCalls || !audioPending {
            previousRenderCalls = renderCalls
            lastProgress = now
        }
        let stalled = audioPending && now - lastProgress >= 1.5
        guard (!running || !correctDevice || stalled), now >= nextAttempt else { return false }
        nextAttempt = now + 2
        lastProgress = now
        return true
    }
}

final class AudioOutput {
    // CoreAudio reconfiguration may block. Never do it on the BLE/UI queue or
    // synchronously inside AVAudioEngineConfigurationChange's internal queue.
    private let controlQueue = DispatchQueue(label: "local.codex.RemoteMic.audio-control")
    private var engine: AVAudioEngine?
    private let ring = SampleRing()
    private var configurationObserver: NSObjectProtocol?
    private var recoveryWork: DispatchWorkItem?
    private var healthTimer: DispatchSourceTimer?
    private var monitor = AudioRecoveryMonitor()
    private var preferredDeviceName = "BlackHole 2ch"
    private var configuredDevice: AudioDeviceID = 0
    private var recoveryCount = 0
    private var enabled = false
    private let summaryLock = NSLock()
    private var engineSummary = "engineRunning=false"
    private let logger = Logger(subsystem: "local.codex.RemoteMic", category: "audio")
    private(set) var deviceName = ""

    func start(preferredDeviceName: String = "BlackHole 2ch") throws {
        try controlQueue.sync {
            self.preferredDeviceName = preferredDeviceName
            enabled = true
            try rebuildEngine()
            let timer = DispatchSource.makeTimerSource(queue: controlQueue)
            timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
            timer.setEventHandler { [weak self] in self?.checkHealth() }
            healthTimer = timer
            timer.resume()
        }
    }

    private func rebuildEngine() throws {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine?.stop()
        engine = nil
        setSummary("engineRunning=false recovering=true")
        let device = try findOutputDevice(containing: preferredDeviceName)
        let engine = AVAudioEngine()
        guard let audioUnit = engine.outputNode.audioUnit else {
            throw NSError(domain: "RemoteMic", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.tr("无法访问音频输出单元")])
        }
        var deviceID = device.id
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else {
            throw NSError(domain: "RemoteMic", code: 3, userInfo: [NSLocalizedDescriptionKey: L10n.tr("无法创建 16 kHz 音频格式")])
        }
        let source = AVAudioSourceNode(format: format) { [ring] _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let data = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            ring.read(into: data, count: Int(frameCount))
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        engine.prepare()
        try engine.start()
        self.engine = engine
        configuredDevice = device.id
        deviceName = device.name
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self, weak engine] _ in
            self?.controlQueue.async { [weak self, weak engine] in
                guard let self, let engine, self.engine === engine else { return }
                self.scheduleRecovery()
            }
        }
        updateSummary()
    }

    private func scheduleRecovery() {
        guard enabled else { return }
        recoveryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.recover() }
        recoveryWork = work
        controlQueue.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func recover() {
        recoveryWork = nil
        guard enabled else { return }
        do {
            try rebuildEngine()
            recoveryCount += 1
            logger.notice("Audio engine recovered count=\(self.recoveryCount) device=\(self.configuredDevice)")
        } catch {
            logger.error("Audio engine recovery failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func currentDevice() -> AudioDeviceID {
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        if let unit = engine?.outputNode.audioUnit {
            _ = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                    kAudioUnitScope_Global, 0, &id, &size)
        }
        return id
    }

    private func checkHealth() {
        guard enabled, recoveryWork == nil else { return }
        let s = ring.snapshot()
        if monitor.needsRecovery(running: engine?.isRunning == true,
                                 correctDevice: currentDevice() == configuredDevice,
                                 renderCalls: s.renderCalls, audioPending: s.queued > 0 && s.playbackDue,
                                 now: ProcessInfo.processInfo.systemUptime) {
            recover()
        }
        updateSummary()
    }

    private func setSummary(_ value: String) {
        summaryLock.lock()
        engineSummary = value
        summaryLock.unlock()
    }

    private func updateSummary() {
        let format = engine?.outputNode.inputFormat(forBus: 0)
        setSummary("engineRunning=\(engine?.isRunning == true) outputDevice=\(currentDevice()) rate=\(format?.sampleRate ?? 0) channels=\(format?.channelCount ?? 0) recoveries=\(recoveryCount)")
    }

    func feed(_ samples: [Int16], sampleRate: Int) {
        ring.append(samples, sampleRate: sampleRate)
    }

    func clear() { ring.clear() }
    func beginCapture() { ring.beginCapture() }
    func startPlayback(after delay: TimeInterval = 0.4) {
        ring.startPlayback(at: ProcessInfo.processInfo.systemUptime + delay)
    }
    func endCapture() { ring.endCapture() }
    var queuedSamples: Int { ring.snapshot().queued }

    func stop() {
        ring.clear()
        controlQueue.async { [weak self] in
            guard let self else { return }
            self.enabled = false
            self.healthTimer?.cancel()
            self.healthTimer = nil
            self.recoveryWork?.cancel()
            self.recoveryWork = nil
            if let observer = self.configurationObserver { NotificationCenter.default.removeObserver(observer) }
            self.configurationObserver = nil
            self.engine?.stop()
            self.engine = nil
            self.setSummary("engineRunning=false stopped=true")
        }
    }

    var diagnosticSummary: String {
        summaryLock.lock()
        let summary = engineSummary
        summaryLock.unlock()
        return "\(summary) \(ring.diagnosticSummary)"
    }

    deinit {
        healthTimer?.cancel()
        recoveryWork?.cancel()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    }

    private func findOutputDevice(containing needle: String) throws -> (id: AudioDeviceID, name: String) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        )
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices
        )
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }

        for id in devices {
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameReference: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(
                id, &nameAddress, 0, nil, &nameSize, &nameReference
            ) == noErr, let nameReference {
                let name = nameReference.takeUnretainedValue() as String
                if name.localizedCaseInsensitiveContains(needle) {
                    return (id, name)
                }
            }
        }
        throw NSError(
            domain: "RemoteMic",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: L10n.format("未找到 %@，请先安装 BlackHole 2ch", needle)]
        )
    }
}
