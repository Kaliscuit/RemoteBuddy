import Foundation

/// Shared with the installer. Keeping these identifiers preserves existing
/// Accessibility permission, launch jobs and saved mappings across upgrades.
enum RemoteIdentity {
    static let configurationURL = URL(fileURLWithPath: "/Library/Application Support/RemoteMic/hci-config.json")

    static func canonicalAddress(_ value: String) -> String? {
        guard value.range(of: #"^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$"#, options: .regularExpression) != nil else { return nil }
        return value.uppercased()
    }

    static var configuration: RemoteConfiguration? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: configurationURL.path),
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == 0,
              let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o022 == 0,
              let data = try? Data(contentsOf: configurationURL) else { return nil }
        return try? JSONDecoder().decode(RemoteConfiguration.self, from: data)
    }

    static var configuredAddress: String? { configuration?.address }
}
