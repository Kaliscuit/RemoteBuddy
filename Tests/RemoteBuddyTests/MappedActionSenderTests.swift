import Foundation
import XCTest
@testable import RemoteBuddy

private enum RecordedOutput: Equatable {
    case key(KeyboardMapping, down: Bool, repeatEvent: Bool)
    case shortcut(KeyboardMapping)
    case media(Int32)
    case open(URL)
}

private final class RecordingOutput: MappedActionOutput {
    var events: [RecordedOutput] = []
    func postShortcut(_ shortcut: KeyboardMapping, isDown: Bool, autoRepeat: Bool) {
        events.append(.key(shortcut, down: isDown, repeatEvent: autoRepeat))
    }
    func tapShortcut(_ shortcut: KeyboardMapping) { events.append(.shortcut(shortcut)) }
    func mediaKey(_ key: Int32) { events.append(.media(key)) }
    func open(_ url: URL) -> Bool { events.append(.open(url)); return true }
}

final class MappedActionSenderTests: XCTestCase {
    private func playHold(_ action: MappedAction) -> [RecordedOutput] {
        let output = RecordingOutput()
        let sender = MappedActionSender(output: output)
        var state = RemoteButtonState()
        func deliver(_ changes: [RemoteButtonChange]) {
            for change in changes { sender.send(action, isDown: change.isDown, repeated: change.isRepeat) }
        }
        deliver(state.update(RemoteButtonReport.decode([11], includesReportID: false)!, now: 0))
        deliver(state.tick(now: 0.35))
        deliver(state.tick(now: 0.43))
        deliver(state.update(RemoteButtonReport.decode([0], includesReportID: false)!, now: 0.45))
        deliver(state.tick(now: 0.8))
        return output.events
    }

    func testBackDeletesContinuouslyAndReleasesExactlyOnce() {
        let delete = KeyboardMapping(keyCode: 0x33)
        XCTAssertEqual(playHold(MappingConfiguration.defaults.action(for: 11)), [
            .key(delete, down: true, repeatEvent: false),
            .key(delete, down: true, repeatEvent: true),
            .key(delete, down: true, repeatEvent: true),
            .key(delete, down: false, repeatEvent: false)
        ])
    }

    func testRepeatsAreNotFilteredByActionKind() {
        let controlC = MappedAction.key(0x08, .maskControl)
        let app = URL(fileURLWithPath: "/Applications/Safari.app")
        let site = URL(string: "https://example.com")!
        let cases: [(MappedAction, RecordedOutput)] = [
            (controlC, .shortcut(controlC.shortcut!)),
            (.init(kind: .volumeUp), .media(0)),
            (.init(kind: .volumeDown), .media(1)),
            (.init(kind: .mute), .media(7)),
            (.init(kind: .playPause), .media(16)),
            (.init(kind: .application, value: app.path), .open(app)),
            (.init(kind: .website, value: site.absoluteString), .open(site))
        ]
        for (action, expected) in cases {
            XCTAssertEqual(playHold(action), [expected, expected, expected], action.kind.rawValue)
        }
    }

    func testModifierBindingsAlsoReceiveRepeatsWhileDisabledRemainsNoOp() {
        let modifier = KeyboardMapping(keyCode: 0x37)
        XCTAssertEqual(playHold(.init(kind: .keyboard, shortcut: modifier)), [
            .key(modifier, down: true, repeatEvent: false),
            .key(modifier, down: true, repeatEvent: true),
            .key(modifier, down: true, repeatEvent: true),
            .key(modifier, down: false, repeatEvent: false)
        ])
        XCTAssertEqual(playHold(.disabled), [])
    }
}
