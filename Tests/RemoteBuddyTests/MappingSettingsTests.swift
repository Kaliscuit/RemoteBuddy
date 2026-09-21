import CoreGraphics
import XCTest
@testable import RemoteBuddy

final class MappingSettingsTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("mappings.json")
    }
    func testSavePersistsAcrossReloadAndKeepsVoiceDefaults() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = MappingStore(url: url)
        var edited = store.configuration
        edited.buttons["14"] = .key(0x0d, .maskCommand)
        var observedOldMapping: MappedAction?
        store.willChange = { observedOldMapping = store.configuration.action(for: 14) }
        try store.save(edited)
        XCTAssertEqual(observedOldMapping, MappingConfiguration.defaults.action(for: 14))
        let reloaded = MappingStore(url: url)
        XCTAssertNil(reloaded.loadError)
        XCTAssertEqual(reloaded.configuration, edited)
        XCTAssertEqual(reloaded.configuration.voiceToggle, .voiceToggle)
        XCTAssertEqual(reloaded.configuration.voiceHold, .voiceHold)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }
    func testInvalidEditDoesNotOverwriteSavedConfiguration() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = MappingStore(url: url)
        try store.save(.defaults)
        let before = try Data(contentsOf: url)
        var invalid = store.configuration
        invalid.buttons["17"] = .init(kind: .website, value: "javascript:alert(1)")
        var callbackCount = 0
        store.willChange = { callbackCount += 1 }
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(callbackCount, 0)
        XCTAssertEqual(store.configuration, .defaults)
    }
    func testCorruptFileFallsBackWithoutOverwritingIt() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = Data("broken JSON".utf8)
        try bytes.write(to: url)
        let store = MappingStore(url: url)
        XCTAssertNotNil(store.loadError)
        XCTAssertEqual(store.configuration, .defaults)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testIncompleteButtonDictionaryUsesCurrentPreset() throws {
        var config = MappingConfiguration.defaults
        config.buttons.removeValue(forKey: "11")
        try config.validate()
        XCTAssertEqual(config.action(for: 11), .key(0x33))
        XCTAssertEqual(config.action(for: 2), .disabled)
    }
    func testRemappedCommandsAndLaunchActionsDoNotRepeat() {
        XCTAssertFalse(MappedAction.key(0x0d, .maskCommand).supportsRepeat)
        XCTAssertFalse(MappedAction(kind: .application, value: "/Applications/Safari.app").supportsRepeat)
        XCTAssertFalse(MappedAction(kind: .mute).supportsRepeat)
        var state = RemoteButtonState()
        _ = state.update([3], now: 0, repeatableButtons: [])
        XCTAssertEqual(state.tick(now: 0.7), [])
        XCTAssertEqual(state.update([], now: 0.8), [RemoteButtonChange(button: 3, isDown: false)])
    }
    func testVoiceShortcutsRoundTripAndUnsupportedFlagsFailValidation() throws {
        var config = MappingConfiguration.defaults
        config.voiceToggle = KeyboardMapping(keyCode: 0x31, modifiers: CGEventFlags.maskControl.rawValue)
        config.voiceHold = KeyboardMapping(keyCode: 0x3f)
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(MappingConfiguration.self, from: data), config)
        config.voiceHold.modifiers = UInt64.max
        XCTAssertThrowsError(try config.validate())
    }
    func testRecordingNavigationDoesNotAccidentallyAddFn() {
        let flags = CGEventFlags([.maskSecondaryFn, .maskCommand]).rawValue
        XCTAssertEqual(KeyboardMapping.recorded(keyCode: 0x7e, eventModifiers: flags),
                       KeyboardMapping(keyCode: 0x7e, modifiers: CGEventFlags.maskCommand.rawValue))
        XCTAssertEqual(KeyboardMapping.recorded(keyCode: 0x31, eventModifiers: CGEventFlags.maskSecondaryFn.rawValue),
                       .voiceToggle)
    }
}
