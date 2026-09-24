import Foundation
import IOKit

enum RemoteButtonProfile: String {
    case abbey22, jieliHIDMouse001

    var attribute: Int { self == .abbey22 ? 0x46 : 0x2b }
    var reportFormat: RemoteReportFormat { self == .abbey22 ? .indexed : .consumer16 }
    var title: String { self == .abbey22 ? "ABBEY / 22.2" : "Jieli hid_mouse / 0.0.1" }
}

struct DiscoveredRemote: Equatable {
    let name: String
    let address: String
    let peripheralID: UUID?
    let manufacturer: String
    let model: String
    let firmware: String
    let vendorID: Int
    let productID: Int

    var buttonProfile: RemoteButtonProfile? {
        guard vendorID == 0x18d1, productID == 0x9450 else { return nil }
        var info = RemoteDeviceInformation()
        info.update(uuid: "2A29", value: Data(manufacturer.utf8))
        info.update(uuid: "2A24", value: Data(model.utf8))
        info.update(uuid: "2A26", value: Data(firmware.utf8))
        if info.compatibilityProfile == .jieliHIDMouse001 { return .jieliHIDMouse001 }
        // Google's assigned VID/PID identify the original manufacturer. The
        // model and firmware must also match the verified report layout.
        if info.model == "abbey", info.firmware == "22.2" { return .abbey22 }
        return nil
    }

    func automaticConfiguration() throws -> RemoteConfiguration {
        guard let profile = buttonProfile else { throw RemoteSettingsError.unknownDevice }
        return try RemoteConfiguration(address: address, attribute: profile.attribute,
            reportFormat: profile.reportFormat, peripheralID: peripheralID, automatic: true)
    }

    static func fromRegistry(_ properties: [String: Any]) -> DiscoveredRemote? {
        let name = properties["Product"] as? String ?? ""
        let vendor = properties["VendorID"] as? Int ?? 0
        let product = properties["ProductID"] as? Int ?? 0
        guard (properties["Transport"] as? String)?.hasPrefix("Bluetooth") == true,
              (vendor == 0x18d1 && product == 0x9450) || name.localizedCaseInsensitiveContains("Chromecast Remote"),
              let rawAddress = properties["DeviceAddress"] as? String,
              let address = RemoteConfiguration.enteredAddress(rawAddress) else { return nil }
        return DiscoveredRemote(name: name, address: address,
            peripheralID: (properties["PhysicalDeviceUniqueID"] as? String).flatMap(UUID.init(uuidString:)),
            manufacturer: properties["Manufacturer"] as? String ?? "",
            model: properties["ModelNumber"] as? String ?? "",
            firmware: properties["kBTFirmwareRevisionKey"] as? String ?? "",
            vendorID: vendor, productID: product)
    }
}

enum RemoteDeviceDiscovery {
    /// Read metadata without opening/seizing HID devices or requesting Input
    /// Monitoring. PhysicalDeviceUniqueID links the MAC to CoreBluetooth's UUID.
    static func connectedRemotes() -> [DiscoveredRemote] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var found: [String: DiscoveredRemote] = [:]
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = properties?.takeRetainedValue() as? [String: Any],
                  let remote = DiscoveredRemote.fromRegistry(properties) else { continue }
            if found[remote.address] == nil || remote.peripheralID != nil { found[remote.address] = remote }
        }
        return found.values.sorted { $0.address < $1.address }
    }

    static func selectedPeripheral(for configuration: RemoteConfiguration?,
                                   devices: [DiscoveredRemote]) -> UUID? {
        guard let configuration else { return nil }
        return devices.first { $0.address == configuration.address }?.peripheralID ?? configuration.peripheralID
    }
}
