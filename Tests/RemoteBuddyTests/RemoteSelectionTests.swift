import Foundation
import XCTest
@testable import RemoteBuddy

final class RemoteSelectionTests: XCTestCase {
    private func device(_ changes: [String: Any] = [:]) -> DiscoveredRemote? {
        let defaults: [String: Any] = ["Product": "Chromecast Remote", "Transport": "Bluetooth Low Energy",
            "DeviceAddress": "aa-bb-cc-dd-ee-ff", "PhysicalDeviceUniqueID": "11111111-2222-3333-4444-555555555555",
            "Manufacturer": "zhuhai_jieli", "ModelNumber": "hid_mouse", "kBTFirmwareRevisionKey": "0.0.1",
            "VendorID": 0x18d1, "ProductID": 0x9450]
        return DiscoveredRemote.fromRegistry(defaults.merging(changes) { _, new in new })
    }

    func testKnownDevicesChooseTheirOwnReportFormatAndHandle() throws {
        let jieli = try XCTUnwrap(device())
        let configuration = try jieli.automaticConfiguration()
        XCTAssertEqual(configuration.address, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(configuration.attribute, 0x2b)
        XCTAssertEqual(configuration.reportFormat, .consumer16)
        XCTAssertTrue(configuration.automatic)
        XCTAssertEqual(configuration.peripheralID, jieli.peripheralID)
        let abbey = try XCTUnwrap(device(["Manufacturer": "Google", "ModelNumber": "ABBEY", "kBTFirmwareRevisionKey": "22.2"]))
        XCTAssertEqual(try abbey.automaticConfiguration().attribute, 0x46)
        XCTAssertEqual(try abbey.automaticConfiguration().reportFormat, .indexed)
    }

    func testUnknownDevicesNeverGuessAReportLayout() throws {
        for changes: [String: Any] in [["Manufacturer": "other"], ["ModelNumber": "unknown"],
                ["kBTFirmwareRevisionKey": "0.0.2"], ["kBTFirmwareRevisionKey": ""],
                ["VendorID": 1], ["ProductID": 1]] {
            let remote = try XCTUnwrap(device(changes))
            XCTAssertNil(remote.buttonProfile)
            XCTAssertThrowsError(try remote.automaticConfiguration())
        }
        XCTAssertNil(device(["Transport": "USB"]))
        XCTAssertNil(device(["DeviceAddress": "bad address"]))
    }

    func testSameNameDevicesAreSelectedByAddressNotEnumerationOrder() throws {
        let first = try XCTUnwrap(device())
        let second = try XCTUnwrap(device(["DeviceAddress": "11:22:33:44:55:66",
            "PhysicalDeviceUniqueID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"]))
        let old = try RemoteConfiguration(address: second.address, attribute: 0x46, reportFormat: .indexed)
        XCTAssertEqual(RemoteDeviceDiscovery.selectedPeripheral(for: old, devices: [first, second]), second.peripheralID)
        XCTAssertNil(RemoteDeviceDiscovery.selectedPeripheral(for: old, devices: [first]))
        XCTAssertNil(RemoteDeviceDiscovery.selectedPeripheral(for: nil, devices: [first]))
        let saved = try second.automaticConfiguration()
        XCTAssertEqual(RemoteDeviceDiscovery.selectedPeripheral(for: saved, devices: []), second.peripheralID)
        let rePaired = try XCTUnwrap(device(["DeviceAddress": second.address,
            "PhysicalDeviceUniqueID": "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"]))
        XCTAssertEqual(RemoteDeviceDiscovery.selectedPeripheral(for: saved, devices: [rePaired]), rePaired.peripheralID)
    }

    func testLegacyAndNewConfigurationsRoundTrip() throws {
        let old = Data(#"{"address":"AA:BB:CC:DD:EE:FF","attribute":70,"uid":501,"packetlogger":"/fixed/tool"}"#.utf8)
        let decoded = try JSONDecoder().decode(RemoteConfiguration.self, from: old)
        XCTAssertEqual(decoded.reportFormat, .indexed)
        XCTAssertFalse(decoded.automatic)
        XCTAssertNil(decoded.peripheralID)
        let current = try XCTUnwrap(device()).automaticConfiguration()
        XCTAssertEqual(try JSONDecoder().decode(RemoteConfiguration.self, from: JSONEncoder().encode(current)), current)
        for invalid in [#"{"address":"invalid","attribute":70}"#,
                        #"{"address":"AA:BB:CC:DD:EE:FF","attribute":0}"#,
                        #"{"address":"AA:BB:CC:DD:EE:FF","attribute":70,"report_format":"other"}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(RemoteConfiguration.self, from: Data(invalid.utf8)))
        }
    }

    func testManualEntryValidation() {
        XCTAssertEqual(RemoteConfiguration.enteredAddress(" aa-bb-cc-dd-ee-ff \n"), "AA:BB:CC:DD:EE:FF")
        XCTAssertNil(RemoteConfiguration.enteredAddress("AA:BB:CC:DD:EE:FF; command"))
        XCTAssertEqual(RemoteConfiguration.enteredAttribute("0x2b"), 43)
        XCTAssertEqual(RemoteConfiguration.enteredAttribute("70"), 70)
        for value in ["", "0", "65536", "0x", "-1", "0xFFFFF"] {
            XCTAssertNil(RemoteConfiguration.enteredAttribute(value))
        }
    }
}
