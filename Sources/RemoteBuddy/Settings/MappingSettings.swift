import Carbon.HIToolbox
import CoreGraphics
import Foundation

struct KeyboardMapping: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64 = 0
    static let allowedModifiers = CGEventFlags([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]).rawValue
    static let voiceToggle = KeyboardMapping(keyCode: 0x31, modifiers: CGEventFlags.maskSecondaryFn.rawValue)
    static let voiceHold = KeyboardMapping(keyCode: 0x3f)
    var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }
    static func recorded(keyCode: UInt16, eventModifiers: UInt64) -> Self {
        var flags = eventModifiers & allowedModifiers
        // AppKit marks navigation/function key events as "function" even
        // without a physical Fn chord. Fn can still be chosen explicitly.
        if MacKey.functionCodes.contains(keyCode) { flags &= ~CGEventFlags.maskSecondaryFn.rawValue }
        return .init(keyCode: keyCode, modifiers: flags)
    }
    var isModifier: Bool { Self.modifierFlag(for: keyCode) != nil }
    var isChord: Bool { modifiers != 0 && !isModifier }
    var displayName: String {
        var prefix = ""
        for (flag, label) in [(CGEventFlags.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘"), (.maskSecondaryFn, "Fn+")] {
            if flags.contains(flag) { prefix += label }
        }
        return prefix + (MacKey.names[keyCode] ?? "Key \(keyCode)")
    }
    static func modifierFlag(for code: UInt16) -> CGEventFlags? {
        switch code {
        case 0x3f: return .maskSecondaryFn
        case 0x37, 0x36: return .maskCommand
        case 0x38, 0x3c: return .maskShift
        case 0x3a, 0x3d: return .maskAlternate
        case 0x3b, 0x3e: return .maskControl
        default: return nil
        }
    }
    func validate() throws {
        guard keyCode <= 127, modifiers & ~Self.allowedModifiers == 0 else {
            throw MappingError.invalid(L10n.tr("快捷键包含不支持的按键或修饰键。"))
        }
    }
}

enum MacKey {
    static let choices: [(String, UInt16)] = [
        ("↑", 0x7e), ("↓", 0x7d), ("←", 0x7b), ("→", 0x7c),
        ("Return", 0x24), ("Esc", 0x35), ("Delete", 0x33), ("Forward Delete", 0x75),
        ("Space", 0x31), ("Tab", 0x30), ("Page Up", 0x74), ("Page Down", 0x79),
        ("Home", 0x73), ("End", 0x77),
        ("A",0x00),("B",0x0b),("C",0x08),("D",0x02),("E",0x0e),("F",0x03),
        ("G",0x05),("H",0x04),("I",0x22),("J",0x26),("K",0x28),("L",0x25),
        ("M",0x2e),("N",0x2d),("O",0x1f),("P",0x23),("Q",0x0c),("R",0x0f),
        ("S",0x01),("T",0x11),("U",0x20),("V",0x09),("W",0x0d),("X",0x07),
        ("Y",0x10),("Z",0x06),
        ("0",0x1d),("1",0x12),("2",0x13),("3",0x14),("4",0x15),
        ("5",0x17),("6",0x16),("7",0x1a),("8",0x1c),("9",0x19),
        ("-",0x1b),("=",0x18),("[",0x21),("]",0x1e),(";",0x29),("'",0x27),
        (",",0x2b),(".",0x2f),("/",0x2c),("\\",0x2a),("`",0x32),
        ("F1",0x7a),("F2",0x78),("F3",0x63),("F4",0x76),("F5",0x60),
        ("F6",0x61),("F7",0x62),("F8",0x64),("F9",0x65),("F10",0x6d),
        ("F11",0x67),("F12",0x6f),("F13",0x69),("F14",0x6b),("F15",0x71),
        ("F16",0x6a),("F17",0x40),("F18",0x4f),("F19",0x50),("F20",0x5a),
        ("Fn",0x3f),("⌘",0x37),("⌃",0x3b),("⌥",0x3a),("⇧",0x38)
    ]
    static let names = Dictionary(uniqueKeysWithValues: choices.map { ($0.1, $0.0) })
    static let functionCodes: Set<UInt16> = [0x7e,0x7d,0x7b,0x7c,0x74,0x79,0x73,0x77,0x75,
        0x7a,0x78,0x63,0x76,0x60,0x61,0x62,0x64,0x65,0x6d,0x67,0x6f,0x69,0x6b,0x71,0x6a,0x40,0x4f,0x50,0x5a]
}

struct MappedAction: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case keyboard, volumeUp, volumeDown, mute, playPause, application, website, disabled
        var title: String {
            switch self {
            case .keyboard: return L10n.tr("按键 / 快捷键")
            case .volumeUp: return L10n.tr("调高音量")
            case .volumeDown: return L10n.tr("调低音量")
            case .mute: return L10n.tr("静音 / 取消静音")
            case .playPause: return L10n.tr("播放 / 暂停")
            case .application: return L10n.tr("打开应用")
            case .website: return L10n.tr("打开网址")
            case .disabled: return L10n.tr("不执行动作")
            }
        }
    }
    var kind: Kind
    var shortcut: KeyboardMapping?
    var value: String?
    static let disabled = MappedAction(kind: .disabled)
    static func key(_ code: UInt16, _ flags: CGEventFlags = []) -> Self {
        .init(kind: .keyboard, shortcut: .init(keyCode: code, modifiers: flags.rawValue))
    }
    var supportsRepeat: Bool {
        switch kind {
        case .keyboard: return shortcut.map { !$0.isChord && !$0.isModifier } ?? false
        case .volumeUp, .volumeDown: return true
        default: return false
        }
    }
    var title: String {
        switch kind {
        case .keyboard: return shortcut?.displayName ?? L10n.tr("未设置快捷键")
        case .application: return value.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? L10n.tr("未选择应用")
        case .website: return value ?? L10n.tr("未填写网址")
        default: return kind.title
        }
    }
    func validate() throws {
        switch kind {
        case .keyboard:
            guard let shortcut else { throw MappingError.invalid(L10n.tr("请设置快捷键。")) }
            try shortcut.validate()
        case .application:
            guard let value, value.hasPrefix("/"), value.lowercased().hasSuffix(".app") else {
                throw MappingError.invalid(L10n.tr("请选择一个 .app 应用。"))
            }
        case .website:
            guard let value, let url = URL(string: value),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else {
                throw MappingError.invalid(L10n.tr("请填写完整的 http:// 或 https:// 网址。"))
            }
        default: break
        }
    }
}

struct RemoteKeyDefinition {
    let id: UInt8
    let title: String
    static let all: [Self] = [
        .init(id:3,title:L10n.tr("方向上")),.init(id:4,title:L10n.tr("方向下")),.init(id:5,title:L10n.tr("方向左")),.init(id:6,title:L10n.tr("方向右")),
        .init(id:7,title:L10n.tr("确定")),.init(id:11,title:L10n.tr("返回")),.init(id:10,title:"Home"),
        .init(id:14,title:"YouTube"),.init(id:15,title:"Netflix"),.init(id:1,title:L10n.tr("电源")),
        .init(id:17,title:L10n.tr("信号源")),.init(id:12,title:L10n.tr("音量 ＋")),.init(id:13,title:L10n.tr("音量 －")),.init(id:8,title:L10n.tr("静音"))
    ]
}

struct MappingConfiguration: Codable, Equatable {
    var version = 1
    var buttons: [String: MappedAction]
    var voiceToggle: KeyboardMapping = .voiceToggle
    var voiceHold: KeyboardMapping = .voiceHold
    static var defaults: Self {
        .init(buttons: ["3":.key(0x7e),"4":.key(0x7d),"5":.key(0x7b),"6":.key(0x7c),
            "7":.key(0x24),"11":.key(0x33),"10":.key(0x31,.maskCommand),
            "14":.key(0x74),"15":.key(0x79),"1":.key(0x35),"17":.key(0x08,.maskControl),
            "12":.init(kind:.volumeUp),"13":.init(kind:.volumeDown),"8":.init(kind:.mute)])
    }
    func action(for button: UInt8) -> MappedAction { buttons[String(button)] ?? Self.defaults.buttons[String(button)] ?? .disabled }
    func validate() throws {
        guard version == 1 else { throw MappingError.invalid(L10n.tr("配置版本不受支持。")) }
        for definition in RemoteKeyDefinition.all {
            do { try action(for: definition.id).validate() }
            catch { throw MappingError.invalid(L10n.format("%@：%@", definition.title, error.localizedDescription)) }
        }
        try voiceToggle.validate()
        try voiceHold.validate()
    }
}

enum MappingError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

final class MappingStore {
    static let shared = MappingStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("RemoteMic/button-mappings.json"))
    let url: URL
    private(set) var configuration: MappingConfiguration = .defaults
    private(set) var loadError: String?
    var willChange: (() -> Void)?
    init(url: URL) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let config = try JSONDecoder().decode(MappingConfiguration.self, from: Data(contentsOf: url))
            try config.validate()
            configuration = config
        } catch { loadError = error.localizedDescription }
    }
    func save(_ configuration: MappingConfiguration) throws {
        try configuration.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        willChange?() // Release old bindings before switching to the new ones.
        self.configuration = configuration
        loadError = nil
    }
}
