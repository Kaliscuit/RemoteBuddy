import AppKit
import Foundation

/// OS output boundary, injectable so repeat tests never type, toggle audio or open URLs.
protocol MappedActionOutput {
    func postShortcut(_ shortcut: KeyboardMapping, isDown: Bool, autoRepeat: Bool)
    func tapShortcut(_ shortcut: KeyboardMapping)
    func mediaKey(_ key: Int32)
    func open(_ url: URL) -> Bool
}

private final class SystemMappedActionOutput: MappedActionOutput {
    private let keyboard = KeyboardShortcutSender()
    func postShortcut(_ shortcut: KeyboardMapping, isDown: Bool, autoRepeat: Bool) {
        keyboard.postShortcut(shortcut, isDown: isDown, autoRepeat: autoRepeat)
    }
    func tapShortcut(_ shortcut: KeyboardMapping) { keyboard.tapShortcut(shortcut) }
    func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
    func mediaKey(_ key: Int32) {
        for state: Int32 in [0x0a, 0x0b] {
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 8, data1: Int((key << 16) | (state << 8)), data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

final class MappedActionSender {
    var onError: ((String) -> Void)?
    private let output: MappedActionOutput
    init(output: MappedActionOutput? = nil) { self.output = output ?? SystemMappedActionOutput() }

    func send(_ action: MappedAction, isDown: Bool, repeated: Bool = false) {
        switch action.kind {
        case .keyboard:
            guard let shortcut = action.shortcut else { return }
            if shortcut.isChord {
                if isDown { output.tapShortcut(shortcut) }
            } else { output.postShortcut(shortcut, isDown: isDown, autoRepeat: repeated) }
        case .volumeUp where isDown: output.mediaKey(0)
        case .volumeDown where isDown: output.mediaKey(1)
        case .mute where isDown: output.mediaKey(7)
        case .playPause where isDown: output.mediaKey(16)
        case .application where isDown:
            if let path = action.value, !output.open(URL(fileURLWithPath: path)) { onError?(L10n.tr("无法打开所选应用")) }
        case .website where isDown:
            if let value = action.value, let url = URL(string: value), !output.open(url) { onError?(L10n.tr("无法打开网址")) }
        default: break
        }
    }
}
