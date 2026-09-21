import AppKit
import Foundation

final class MappedActionSender {
    var onError: ((String) -> Void)?
    private let keyboard = KeyboardShortcutSender()
    func send(_ action: MappedAction, isDown: Bool, repeated: Bool = false) {
        if repeated && !action.supportsRepeat { return }
        switch action.kind {
        case .keyboard:
            guard let shortcut = action.shortcut else { return }
            if shortcut.isChord {
                if isDown && !repeated { keyboard.tapShortcut(shortcut) }
            } else { keyboard.postShortcut(shortcut, isDown: isDown, autoRepeat: repeated) }
        case .volumeUp where isDown: mediaKey(0)
        case .volumeDown where isDown: mediaKey(1)
        case .mute where isDown: mediaKey(7)
        case .playPause where isDown: mediaKey(16)
        case .application where isDown && !repeated:
            if let path = action.value, !NSWorkspace.shared.open(URL(fileURLWithPath: path)) { onError?(L10n.tr("无法打开所选应用")) }
        case .website where isDown && !repeated:
            if let value = action.value, let url = URL(string: value), !NSWorkspace.shared.open(url) { onError?(L10n.tr("无法打开网址")) }
        default: break
        }
    }
    private func mediaKey(_ key: Int32) {
        for state: Int32 in [0x0a, 0x0b] {
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 8, data1: Int((key << 16) | (state << 8)), data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
