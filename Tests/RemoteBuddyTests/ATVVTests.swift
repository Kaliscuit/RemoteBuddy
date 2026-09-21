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
