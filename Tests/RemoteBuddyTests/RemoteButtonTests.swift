import XCTest
@testable import RemoteBuddy

final class RemoteButtonTests: XCTestCase {
    func testEveryOrdinaryButtonRepeatsUntilItsRelease() {
        for definition in RemoteKeyDefinition.all {
            var state = RemoteButtonState()
            let button = definition.id
            XCTAssertEqual(state.update([button], now: 0), [RemoteButtonChange(button: button, isDown: true)])
            XCTAssertEqual(state.tick(now: 0.33), [])
            XCTAssertEqual(state.tick(now: 0.35), [RemoteButtonChange(button: button, isDown: true, isRepeat: true)])
            XCTAssertEqual(state.tick(now: 0.43), [RemoteButtonChange(button: button, isDown: true, isRepeat: true)])
            XCTAssertEqual(state.update([], now: 0.45), [RemoteButtonChange(button: button, isDown: false)])
            XCTAssertEqual(state.tick(now: 0.8), [])
        }
    }

    func testReleasingBackDoesNotStopAnotherHeldButton() {
        var state = RemoteButtonState()
        _ = state.update([11], now: 0)
        _ = state.update([11, 14], now: 0.2)
        XCTAssertEqual(state.tick(now: 0.35), [RemoteButtonChange(button: 11, isDown: true, isRepeat: true)])
        XCTAssertEqual(state.tick(now: 0.55), [RemoteButtonChange(button: 11, isDown: true, isRepeat: true),
                                             RemoteButtonChange(button: 14, isDown: true, isRepeat: true)])
        XCTAssertEqual(state.update([14], now: 0.56), [RemoteButtonChange(button: 11, isDown: false)])
        XCTAssertEqual(state.tick(now: 0.65), [RemoteButtonChange(button: 14, isDown: true, isRepeat: true)])
    }

    func testBackWatchdogDoesNotReleaseAnotherButtonEarly() {
        var state = RemoteButtonState()
        _ = state.update([11], now: 0)
        _ = state.update([11, 14], now: 1.5)
        XCTAssertEqual(state.tick(now: 2), [RemoteButtonChange(button: 11, isDown: false),
                                          RemoteButtonChange(button: 14, isDown: true, isRepeat: true)])
        XCTAssertEqual(state.update([11, 14], now: 2.05), [])
        XCTAssertEqual(state.tick(now: 2.1), [RemoteButtonChange(button: 14, isDown: true, isRepeat: true)])
        XCTAssertEqual(state.tick(now: 3.5), [RemoteButtonChange(button: 14, isDown: false)])
        XCTAssertEqual(state.tick(now: 4), [])
    }

    func testNativeReportAndRawReadPayloadHaveExplicitFraming() {
        XCTAssertEqual(RemoteButtonReport.decode([1, 5, 7], includesReportID: true), [5, 7])
        XCTAssertEqual(RemoteButtonReport.decode([1, 0], includesReportID: false), [1])
        XCTAssertEqual(RemoteButtonReport.decode([3], includesReportID: false), [3])
        XCTAssertEqual(RemoteButtonReport.decode([0], includesReportID: false), [])
        XCTAssertNil(RemoteButtonReport.decode([2, 3, 0], includesReportID: true))
        XCTAssertNil(RemoteButtonReport.decode([99], includesReportID: false))
        // Empty read responses are not key-up notifications.
        XCTAssertNil(RemoteButtonReport.decode([], includesReportID: false))
    }

    func testTwoSlotsDoNotOscillateOrDuplicate() {
        var state = RemoteButtonState()
        XCTAssertEqual(state.update([5, 7], now: 0), [
            RemoteButtonChange(button: 5, isDown: true), RemoteButtonChange(button: 7, isDown: true)
        ])
        XCTAssertEqual(state.update([7, 5], now: 0.1), [])
        XCTAssertEqual(state.update([7], now: 0.2), [RemoteButtonChange(button: 5, isDown: false)])
        XCTAssertEqual(state.update([], now: 0.3), [RemoteButtonChange(button: 7, isDown: false)])
    }

    func testSeparateTapsAreNotDebouncedAway() {
        var state = RemoteButtonState()
        for index in 0..<5 {
            let now = Double(index)
            XCTAssertEqual(state.update([3], now: now), [RemoteButtonChange(button: 3, isDown: true)])
            XCTAssertEqual(state.update([], now: now + 0.1), [RemoteButtonChange(button: 3, isDown: false)])
            XCTAssertEqual(state.tick(now: now + 0.5), [])
        }
    }

    func testLostReleaseStopsAndCannotRestartUntilReleased() {
        var state = RemoteButtonState()
        _ = state.update([3], now: 0)
        XCTAssertEqual(state.tick(now: 0.35), [RemoteButtonChange(button: 3, isDown: true, isRepeat: true)])
        XCTAssertEqual(state.tick(now: 2), [RemoteButtonChange(button: 3, isDown: false)])
        XCTAssertEqual(state.tick(now: 20), [])
        XCTAssertEqual(state.update([3], now: 21), [])
        _ = state.update([], now: 22)
        XCTAssertEqual(state.update([3], now: 23), [RemoteButtonChange(button: 3, isDown: true)])
    }

    func testDelayedTimerDoesNotReplayRepeatBacklog() {
        var state = RemoteButtonState()
        _ = state.update([4], now: 0)
        XCTAssertEqual(state.tick(now: 1.5).count, 1)
        XCTAssertEqual(state.tick(now: 1.51), [])
        XCTAssertEqual(state.reset(), [RemoteButtonChange(button: 4, isDown: false)])
        XCTAssertEqual(state.tick(now: 30), [])
    }
}
