import Foundation
import XCTest
@testable import RemoteBuddy

final class VoiceRecoveryTests: XCTestCase {
    private final class Keyboard: VoiceKeyboard {
        var taps = 0
        var holds: [Bool] = []
        func postShortcut(_ shortcut: KeyboardMapping, isDown: Bool, autoRepeat: Bool) { holds.append(isDown) }
        func tapShortcut(_ shortcut: KeyboardMapping) { taps += 1 }
    }

    private func controller(_ audio: AudioOutput, _ keyboard: Keyboard,
                            commands: @escaping (Data) -> Void = { _ in }) -> BLEController {
        let result = BLEController(audio: audio, keyboard: keyboard, connectImmediately: false, commandSink: commands)
        result.handle(.capabilities(ATVVCapabilities(version: .v10, codecs: 3, frameSize: 240)))
        return result
    }

    func testPrefixIsNotConsumedBeforeInputMethodStartup() {
        let ring = SampleRing()
        ring.beginCapture()
        ring.append([1024, 2048], sampleRate: 16000)
        var out = [Float](repeating: -1, count: 2)
        out.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, count: 2, now: 1) }
        XCTAssertEqual(out, [0, 0])
        XCTAssertEqual(ring.snapshot().queued, 2)
        ring.startPlayback(at: 2)
        out.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, count: 2, now: 1.9) }
        XCTAssertEqual(out, [0, 0])
        ring.endCapture()
        out.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, count: 2, now: 2) }
        XCTAssertEqual(out, [0.125, 0.25])
        XCTAssertEqual(ring.snapshot().queued, 0)
        XCTAssertEqual(ring.snapshot().gated, 4)
    }

    func testPlaybackGateAndBufferedHeadSurviveSecondTransportStream() {
        let audio = AudioOutput()
        let keyboard = Keyboard()
        let ble = controller(audio, keyboard)
        ble.handle(.audioStart(reason: 3, codec: .adpcm16k, streamID: 1))
        audio.feed([100, 200], sampleRate: 16000)
        ble.handle(.audioStop(reason: 2))
        XCTAssertEqual(keyboard.taps, 1)
        ble.handle(.audioStart(reason: 0, codec: .adpcm16k, streamID: 0))
        audio.feed([300], sampleRate: 16000)
        XCTAssertEqual(audio.queuedSamples, 3)
        ble.stop()
        XCTAssertEqual(keyboard.taps, 2)
    }

    func testRepeatedShortPressesAlwaysReturnToIdle() {
        let audio = AudioOutput()
        let keyboard = Keyboard()
        let ble = controller(audio, keyboard)
        var active = false
        ble.onStreaming = { active = $0 }
        for i in 0..<20 {
            ble.handle(.audioStart(reason: 3, codec: .adpcm16k, streamID: UInt8(i * 2 + 1)))
            ble.handle(.audioStop(reason: 2))
            ble.handle(.audioStart(reason: 0, codec: .adpcm16k, streamID: 0))
            ble.handle(.audioStart(reason: 3, codec: .adpcm16k, streamID: UInt8(i * 2 + 2)))
            ble.handle(.audioStop(reason: 2))
            ble.checkVoiceHealth()
            XCTAssertFalse(active)
            XCTAssertEqual(keyboard.taps, (i + 1) * 2)
        }
        ble.stop()
        XCTAssertEqual(keyboard.taps, 40)
    }

    func testStoppingToggleCannotBecomeAHoldIfReleaseIsLate() {
        var gesture = VoiceGestureStateMachine()
        _ = gesture.pressDown()
        _ = gesture.pressUp()
        XCTAssertEqual(gesture.pressDown(), [.fnSpace])
        XCTAssertEqual(gesture.holdThresholdReached(), [])
        XCTAssertEqual(gesture.pressUp(), [.closeMicrophone])
        XCTAssertFalse(gesture.isPressed)
    }

    func testResetStopsActiveToggleExactlyOnceAndAllowsNextPress() {
        var gesture = VoiceGestureStateMachine()
        _ = gesture.pressDown()
        _ = gesture.pressUp()
        XCTAssertEqual(gesture.reset(), [.fnSpace, .closeMicrophone])
        XCTAssertEqual(gesture.reset(), [.closeMicrophone])
        XCTAssertEqual(gesture.pressDown(), [])
        XCTAssertEqual(gesture.holdThresholdReached(), [.fnDown])
        XCTAssertEqual(gesture.reset(), [.fnUp, .closeMicrophone])
    }

    func testMissingAudioTimesOutAndBalancesToggleShortcut() {
        let audio = AudioOutput()
        let keyboard = Keyboard()
        var commands: [Data] = []
        let ble = controller(audio, keyboard) { commands.append($0) }
        ble.handle(.audioStart(reason: 3, codec: .adpcm16k, streamID: 1))
        ble.handle(.audioStop(reason: 2))
        XCTAssertEqual(keyboard.taps, 1)
        ble.checkVoiceHealth(now: ProcessInfo.processInfo.systemUptime + 4)
        XCTAssertEqual(keyboard.taps, 2)
        XCTAssertEqual(commands.last, Data([0x0d, 0xff]))
        ble.checkVoiceHealth(now: ProcessInfo.processInfo.systemUptime + 8)
        XCTAssertEqual(keyboard.taps, 2)
        ble.handle(.audioStart(reason: 3, codec: .adpcm16k, streamID: 2))
        ble.handle(.audioStop(reason: 2))
        XCTAssertEqual(keyboard.taps, 3)
        ble.stop()
    }

    func testCancelledReopenCannotReopenAfterReset() {
        let audio = AudioOutput()
        let keyboard = Keyboard()
        var commands: [Data] = []
        let ble = controller(audio, keyboard) { commands.append($0) }
        ble.handle(.audioStart(reason: 3, codec: .adpcm16k, streamID: 1))
        ble.handle(.audioStop(reason: 2))
        ble.prepareForMappingChange()
        let waited = expectation(description: "past delayed MIC_OPEN")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { waited.fulfill() }
        wait(for: [waited], timeout: 1)
        XCTAssertFalse(commands.contains { $0.first == 0x0c })
        XCTAssertEqual(keyboard.taps, 2)
    }

    func testStopShortcutWaitsForBufferedTailOrBoundedTimeout() {
        let audio = AudioOutput()
        let keyboard = Keyboard()
        let ble = controller(audio, keyboard)
        ble.handle(.audioStart(reason: 3, codec: .adpcm16k, streamID: 1))
        audio.feed([123], sampleRate: 16000)
        ble.handle(.audioStop(reason: 2))
        ble.handle(.audioStart(reason: 0, codec: .adpcm16k, streamID: 0))
        ble.handle(.audioStart(reason: 3, codec: .adpcm16k, streamID: 2))
        ble.handle(.audioStop(reason: 2))
        ble.checkVoiceHealth()
        XCTAssertEqual(keyboard.taps, 1)
        XCTAssertEqual(audio.queuedSamples, 1)
        ble.checkVoiceHealth(now: ProcessInfo.processInfo.systemUptime + 2.1)
        XCTAssertEqual(keyboard.taps, 2)
        XCTAssertEqual(audio.queuedSamples, 0)
    }

    func testOnRequestAndPTTButtonsCanStopAnExistingToggle() {
        for ptt in [false, true] {
            let audio = AudioOutput()
            let keyboard = Keyboard()
            let ble = controller(audio, keyboard)
            if ptt { ble.handle(.audioStart(reason: 1, codec: .adpcm16k, streamID: 1)) }
            else { ble.handle(.startSearch); ble.handle(.audioStart(reason: 0, codec: .adpcm16k, streamID: 0)) }
            XCTAssertEqual(keyboard.taps, 1)
            if ptt { ble.handle(.audioStart(reason: 1, codec: .adpcm16k, streamID: 2)) }
            else { ble.handle(.startSearch) }
            ble.checkVoiceHealth()
            XCTAssertEqual(keyboard.taps, 2)
            ble.stop()
            XCTAssertEqual(keyboard.taps, 2)
        }
    }

    func testToggleStopClosesRemoteWithoutWaitingForRelease() {
        let audio = AudioOutput()
        let keyboard = Keyboard()
        var commands: [Data] = []
        let ble = controller(audio, keyboard) { commands.append($0) }
        ble.handle(.audioStart(reason: 3, codec: .adpcm16k, streamID: 1))
        ble.handle(.audioStop(reason: 2))
        ble.handle(.audioStart(reason: 0, codec: .adpcm16k, streamID: 0))
        ble.handle(.audioStart(reason: 3, codec: .adpcm16k, streamID: 2))
        XCTAssertEqual(commands.last, Data([0x0d, 0xff]))
        // Even continuing audio cannot indefinitely postpone a failed close.
        let now = ProcessInfo.processInfo.systemUptime
        ble.receiveAudio(Data([0x00]), at: now + 2.1)
        ble.checkVoiceHealth(now: now + 2.2)
        XCTAssertEqual(keyboard.taps, 2)
        XCTAssertEqual(commands.last, Data([0x0d, 0xff]))
        ble.handle(.audioStart(reason: 3, codec: .adpcm16k, streamID: 3))
        ble.handle(.audioStop(reason: 2))
        XCTAssertEqual(keyboard.taps, 3)
        ble.stop()
    }

    func testLateMicOpenErrorDoesNotDestroyCurrentHTTGesture() {
        let audio = AudioOutput()
        let keyboard = Keyboard()
        let ble = controller(audio, keyboard)
        ble.handle(.audioStart(reason: 3, codec: .adpcm16k, streamID: 1))
        ble.handle(.error(0x0f80))
        ble.handle(.audioStop(reason: 2))
        XCTAssertEqual(keyboard.taps, 1)
        ble.stop()
    }

    func testTransportWatchdogUsesArrivalNotVolumeAndInvalidatesTasks() {
        var watchdog = VoiceSessionWatchdog()
        let generation = watchdog.generation
        watchdog.awaitingStream(at: 10)
        XCTAssertFalse(watchdog.hasTimedOut(at: 12.9))
        XCTAssertTrue(watchdog.hasTimedOut(at: 13))
        watchdog.receivedAudio(at: 12)
        XCTAssertFalse(watchdog.hasTimedOut(at: 14.9))
        XCTAssertTrue(watchdog.hasTimedOut(at: 15))
        watchdog.invalidate()
        XCTAssertNotEqual(watchdog.generation, generation)
        XCTAssertFalse(watchdog.hasTimedOut(at: 1000))
    }

    func testQuietPacketsKeepToggleAliveAndRemoteTimeoutStopsIt() {
        let audio = AudioOutput()
        let keyboard = Keyboard()
        let ble = controller(audio, keyboard)
        ble.handle(.audioStart(reason: 3, codec: .adpcm16k, streamID: 1))
        ble.handle(.audioStop(reason: 2))
        ble.handle(.audioStart(reason: 0, codec: .adpcm16k, streamID: 0))
        let now = ProcessInfo.processInfo.systemUptime
        for i in 0..<10 {
            ble.receiveAudio(Data([0x00]), at: now + Double(i))
            ble.checkVoiceHealth(now: now + Double(i) + 0.9)
        }
        XCTAssertEqual(keyboard.taps, 1)
        ble.handle(.audioStop(reason: 8))
        XCTAssertEqual(keyboard.taps, 2)
        ble.stop()
        XCTAssertEqual(keyboard.taps, 2)
    }

    func testFreshPressRecoversFromMissingPreviousRelease() {
        let audio = AudioOutput()
        let keyboard = Keyboard()
        let ble = controller(audio, keyboard)
        ble.handle(.audioStart(reason: 3, codec: .adpcm16k, streamID: 1))
        let threshold = expectation(description: "hold is active")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { threshold.fulfill() }
        wait(for: [threshold], timeout: 1.5)
        XCTAssertEqual(keyboard.holds, [true])
        // Missing STOP for stream 1 must not make stream 2's press a no-op.
        ble.handle(.audioStart(reason: 3, codec: .adpcm16k, streamID: 2))
        ble.handle(.audioStop(reason: 2))
        XCTAssertEqual(keyboard.holds, [true, false])
        XCTAssertEqual(keyboard.taps, 1)
        ble.stop()
    }

    func testAudioMonitorRecoversStoppedEngineAndStalledRenderWithBackoff() {
        var monitor = AudioRecoveryMonitor()
        XCTAssertTrue(monitor.needsRecovery(running: false, correctDevice: true, renderCalls: 1, audioPending: true, now: 0))
        XCTAssertFalse(monitor.needsRecovery(running: false, correctDevice: true, renderCalls: 1, audioPending: true, now: 1))
        XCTAssertTrue(monitor.needsRecovery(running: false, correctDevice: true, renderCalls: 1, audioPending: true, now: 2))
        XCTAssertFalse(monitor.needsRecovery(running: true, correctDevice: true, renderCalls: 2, audioPending: true, now: 4))
        XCTAssertTrue(monitor.needsRecovery(running: true, correctDevice: true, renderCalls: 2, audioPending: true, now: 5.5))
        XCTAssertFalse(monitor.needsRecovery(running: true, correctDevice: true, renderCalls: 2, audioPending: false, now: 10))
        XCTAssertTrue(monitor.needsRecovery(running: true, correctDevice: false, renderCalls: 3, audioPending: false, now: 11))
    }

    func testActiveSyncDoesNotLeakPredictorIntoNextStream() {
        var session = ATVVSession()
        XCTAssertTrue(session.accept(ATVVCapabilities(version: .v10, codecs: 2, frameSize: 240)))
        session.begin(codec: .adpcm16k, streamID: 1)
        session.applySync(codec: .adpcm16k, sequence: 10, predictor: 10000, stepIndex: 20)
        session.end()
        session.begin(codec: .adpcm16k, streamID: 2)
        XCTAssertEqual(session.decodeAudio(Data([0x71])), [11, 17])
        session.end()
        session.applySync(codec: .adpcm16k, sequence: 0, predictor: 1000, stepIndex: 0)
        session.begin(codec: .adpcm16k, streamID: 3)
        XCTAssertEqual(session.decodeAudio(Data([0x71])), [1011, 1017])
    }
}
