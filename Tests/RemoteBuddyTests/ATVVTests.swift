import XCTest
@testable import RemoteBuddy

final class ATVVTests: XCTestCase {
    func testParsesVersion10Capabilities() {
        let caps = ATVVSession.parseCapabilities([0x0b, 0x01, 0x00, 0x03, 0x01, 0x00, 0x86])
        XCTAssertNotNil(caps)
        XCTAssertEqual(caps?.frameSize, 134)
        XCTAssertEqual(caps?.preferredCodec, .adpcm16k)
    }

    func testADPCMClampsState() {
        var decoder = ADPCMDecoder()
        decoder.reset(predictor: 32_000, stepIndex: 88)
        let values = decoder.decode([0x77, 0xff, 0x00])
        XCTAssertTrue(values.allSatisfy { Int($0) >= -32768 && Int($0) <= 32767 })
        XCTAssertTrue((0...88).contains(decoder.stepIndex))
    }

    func testATVVDecodesHighNibbleFirst() {
        var decoder = ADPCMDecoder()
        // Starting at step 7: nibble 7 produces 11 and advances the step to
        // 16; nibble 1 then adds 6. Low-nibble-first would produce [1, 12].
        XCTAssertEqual(decoder.decode([0x71]), [11, 17])
        XCTAssertEqual(decoder.predictor, 17)
        XCTAssertEqual(decoder.stepIndex, 7)
    }

    func testADPCMMatchesIndependentReferenceVectorAcrossPackets() {
        // Independently checked with CPython audioop.adpcm2lin (IMA/DVI).
        let bytes: [UInt8] = [0x12, 0x34, 0x56, 0x78, 0x90, 0xab, 0xcd, 0xef]
        let expected: [Int16] = [1, 4, 8, 15, 27, 47, 88, 82, 66, 71, 49, 20, -14, -64, -152, -333]
        var continuous = ADPCMDecoder()
        var split = ADPCMDecoder()
        XCTAssertEqual(continuous.decode(bytes), expected)
        XCTAssertEqual(split.decode(bytes.prefix(3)) + split.decode(bytes.dropFirst(3)), expected)
    }

    func testShortPressStartsAndSecondShortPressStopsToggle() {
        var gesture = VoiceGestureStateMachine()
        XCTAssertEqual(gesture.pressDown(), [])
        XCTAssertEqual(gesture.pressUp(), [.fnSpace, .reopenMicrophone])
        XCTAssertTrue(gesture.toggleActive)
        XCTAssertEqual(gesture.pressDown(), [.fnSpace])
        XCTAssertFalse(gesture.toggleActive)
        XCTAssertEqual(gesture.pressUp(), [.closeMicrophone])
    }

    func testLongPressHoldsFnUntilRelease() {
        var gesture = VoiceGestureStateMachine()
        XCTAssertEqual(gesture.pressDown(), [])
        XCTAssertEqual(gesture.holdThresholdReached(), [.fnDown])
        XCTAssertEqual(gesture.pressUp(), [.fnUp, .closeMicrophone])
        XCTAssertFalse(gesture.toggleActive)
    }
}
