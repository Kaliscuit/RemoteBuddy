import Foundation
import XCTest
@testable import RemoteBuddy

final class RemoteCompatibilityTests: XCTestCase {
    private func information(manufacturer: String?, model: String?, firmware: String?) -> RemoteDeviceInformation {
        var result = RemoteDeviceInformation()
        for (uuid, value) in [("2A29", manufacturer), ("2A24", model), ("2A26", firmware)] {
            if let value { result.update(uuid: uuid, value: Data(value.utf8)) }
        }
        return result
    }

    func testKnownFirmwareOptsIntoDelayedReleaseWorkaround() {
        let device = information(manufacturer: "zhuhai_jieli", model: "hid_mouse", firmware: "0.0.1")
        XCTAssertEqual(device.compatibilityProfile, .jieliHIDMouse001)
        XCTAssertTrue(device.compatibilityProfile.usesAudioDurationForHold)
    }

    func testDifferentOrMissingIdentityKeepsStandardTiming() {
        let devices = [
            information(manufacturer: "another_vendor", model: "hid_mouse", firmware: "0.0.1"),
            information(manufacturer: "zhuhai_jieli", model: "another_model", firmware: "0.0.1"),
            information(manufacturer: "zhuhai_jieli", model: "hid_mouse", firmware: "0.0.2"),
            information(manufacturer: "zhuhai_jieli", model: "hid_mouse", firmware: "0.0.10"),
            information(manufacturer: "zhuhai_jieli", model: "hid_mouse_plus", firmware: "0.0.1"),
            information(manufacturer: nil, model: "hid_mouse", firmware: "0.0.1"),
            information(manufacturer: "zhuhai_jieli", model: nil, firmware: "0.0.1"),
            information(manufacturer: "zhuhai_jieli", model: "hid_mouse", firmware: nil),
            information(manufacturer: "", model: "hid_mouse", firmware: "0.0.1"),
            information(manufacturer: "Google", model: "ABBEY", firmware: "22.2"),
            RemoteDeviceInformation(),
        ]
        for device in devices {
            XCTAssertEqual(device.compatibilityProfile, .standard)
            XCTAssertFalse(device.compatibilityProfile.usesAudioDurationForHold)
        }
    }

    func testIdentityNormalizesCaseAndStringPadding() {
        let device = information(manufacturer: " ZHUHAI_JIELI\0", model: "HID_MOUSE\n", firmware: "0.0.1\0")
        XCTAssertEqual(device.compatibilityProfile, .jieliHIDMouse001)
    }

    func testAllThreeFieldsMustArriveInAnyOrder() {
        let fields = [("2A29", "zhuhai_jieli"), ("2A24", "hid_mouse"), ("2A26", "0.0.1")]
        for order in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
            var device = RemoteDeviceInformation()
            for (index, field) in order.enumerated() {
                device.update(uuid: fields[field].0, value: Data(fields[field].1.utf8))
                XCTAssertEqual(device.compatibilityProfile, index == 2 ? .jieliHIDMouse001 : .standard)
            }
        }
    }

    func testUnrelatedFieldsDoNotSubstituteForFirmwareAndInvalidIdentityDisablesWorkaround() {
        var device = information(manufacturer: "zhuhai_jieli", model: "hid_mouse", firmware: nil)
        device.update(uuid: "2A28", value: Data("0.0.1".utf8))
        XCTAssertEqual(device.compatibilityProfile, .standard)
        device.update(uuid: "2a26", value: Data("0.0.1".utf8))
        XCTAssertEqual(device.compatibilityProfile, .jieliHIDMouse001)
        device.update(uuid: "2A29", value: Data([0xff]))
        XCTAssertEqual(device.compatibilityProfile, .standard)
        device = RemoteDeviceInformation()
        device.update(uuid: "2A26", value: Data("0.0.1".utf8))
        XCTAssertEqual(device.compatibilityProfile, .standard)
    }
}
