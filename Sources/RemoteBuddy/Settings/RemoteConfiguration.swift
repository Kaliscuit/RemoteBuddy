import Foundation

enum RemoteReportFormat: String, Codable, CaseIterable {
    case indexed, consumer16
}

struct RemoteConfiguration: Codable, Equatable {
    let address: String
    let attribute: Int
    let reportFormat: RemoteReportFormat
    let peripheralID: UUID?
    let automatic: Bool

    enum CodingKeys: String, CodingKey {
        case address, attribute
        case reportFormat = "report_format"
        case peripheralID = "peripheral_id"
        case automatic = "auto_detect"
    }

    init(address: String, attribute: Int, reportFormat: RemoteReportFormat,
         peripheralID: UUID? = nil, automatic: Bool = false) throws {
        guard let address = RemoteIdentity.canonicalAddress(address) else {
            throw RemoteSettingsError.invalidAddress
        }
        guard (1...65535).contains(attribute) else { throw RemoteSettingsError.invalidAttribute }
        self.address = address
        self.attribute = attribute
        self.reportFormat = reportFormat
        self.peripheralID = peripheralID
        self.automatic = automatic
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(address: values.decode(String.self, forKey: .address),
                      attribute: values.decode(Int.self, forKey: .attribute),
                      reportFormat: values.decodeIfPresent(RemoteReportFormat.self, forKey: .reportFormat) ?? .indexed,
                      peripheralID: values.decodeIfPresent(UUID.self, forKey: .peripheralID),
                      automatic: values.decodeIfPresent(Bool.self, forKey: .automatic) ?? false)
    }

    static func enteredAddress(_ text: String) -> String? {
        RemoteIdentity.canonicalAddress(text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: ":"))
    }

    static func enteredAttribute(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let number = value.hasPrefix("0x") ? Int(value.dropFirst(2), radix: 16) : Int(value),
              (1...65535).contains(number) else { return nil }
        return number
    }
}

enum RemoteSettingsError: LocalizedError {
    case invalidAddress, invalidAttribute, unknownDevice, unavailableService, outdatedService, saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidAddress: return L10n.tr("请填写有效的蓝牙地址，例如 AA:BB:CC:DD:EE:FF。")
        case .invalidAttribute: return L10n.tr("按键句柄需为 1–65535，也可填写 0x 开头的十六进制值。")
        case .unknownDevice: return L10n.tr("无法自动识别此遥控器。请先连接后刷新，或关闭自动识别并填写已确认的参数。")
        case .unavailableService: return L10n.tr("辅助服务未连接，请稍后重试或重新运行安装器。")
        case .outdatedService: return L10n.tr("辅助服务需要更新，请运行新版安装器后再更换遥控器。")
        case .saveFailed: return L10n.tr("遥控器配置未能保存，请检查辅助服务后重试。")
        }
    }
}
