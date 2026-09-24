import Foundation

/// Only opt in to firmware workarounds for an identified, tested device.
/// The name advertised over Bluetooth and the shared VID/PID are insufficient.
enum RemoteCompatibilityProfile: String {
    case standard
    case jieliHIDMouse001

    var usesAudioDurationForHold: Bool { self == .jieliHIDMouse001 }
}

struct RemoteDeviceInformation {
    private(set) var manufacturer: String?
    private(set) var model: String?
    private(set) var firmware: String?

    var compatibilityProfile: RemoteCompatibilityProfile {
        if manufacturer == "zhuhai_jieli", model == "hid_mouse", firmware == "0.0.1" {
            return .jieliHIDMouse001
        }
        return .standard
    }

    mutating func update(uuid: String, value: Data) {
        let text = String(data: value, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).lowercased()
        switch uuid.uppercased() {
        case "2A29": manufacturer = text
        case "2A24": model = text
        case "2A26": firmware = text
        default: break
        }
    }
}
