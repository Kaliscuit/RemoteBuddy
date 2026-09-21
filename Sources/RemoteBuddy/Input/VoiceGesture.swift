import ApplicationServices
import CoreGraphics
import Foundation

enum VoiceGestureAction: Equatable {
    case fnDown
    case fnUp
    case fnSpace
    case reopenMicrophone
    case closeMicrophone
}

struct VoiceGestureStateMachine {
    private enum PressState: Equatable {
        case idle
        case pending(stoppedExistingToggle: Bool)
        case holding
    }

    private(set) var toggleActive = false
    private var pressState: PressState = .idle
    var isPressed: Bool { pressState != .idle }

    mutating func pressDown() -> [VoiceGestureAction] {
        guard pressState == .idle else { return [] }
        if toggleActive {
            toggleActive = false
            pressState = .pending(stoppedExistingToggle: true)
            return [.fnSpace]
        }
        pressState = .pending(stoppedExistingToggle: false)
        return []
    }

    mutating func holdThresholdReached() -> [VoiceGestureAction] {
        // A press that ends toggle recording must never turn into a new hold.
        guard case .pending(stoppedExistingToggle: false) = pressState else { return [] }
        pressState = .holding
        return [.fnDown]
    }

    mutating func pressUp() -> [VoiceGestureAction] {
        switch pressState {
        case .idle:
            return []
        case .pending(let stoppedExistingToggle):
            pressState = .idle
            if stoppedExistingToggle {
                return [.closeMicrophone]
            }
            toggleActive = true
            return [.fnSpace, .reopenMicrophone]
        case .holding:
            pressState = .idle
            toggleActive = false
            return [.fnUp, .closeMicrophone]
        }
    }

    mutating func reset() -> [VoiceGestureAction] {
        let needsFnUp = pressState == .holding
        let needsToggleOff = toggleActive
        pressState = .idle
        toggleActive = false
        return (needsFnUp ? [.fnUp] : []) + (needsToggleOff ? [.fnSpace] : []) + [.closeMicrophone]
    }
}

protocol VoiceKeyboard {
    func postShortcut(_ shortcut: KeyboardMapping, isDown: Bool, autoRepeat: Bool)
    func tapShortcut(_ shortcut: KeyboardMapping)
}

final class KeyboardShortcutSender: VoiceKeyboard {
    static let fnKeyCode: CGKeyCode = 0x3f
    static let spaceKeyCode: CGKeyCode = 0x31

    var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    func requestAccessibilityIfNeeded() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    func fnDown() {
        post(keyCode: Self.fnKeyCode, keyDown: true, flags: .maskSecondaryFn)
    }

    func fnUp() {
        post(keyCode: Self.fnKeyCode, keyDown: false, flags: [])
    }

    func tapFnSpace() {
        post(keyCode: Self.fnKeyCode, keyDown: true, flags: .maskSecondaryFn)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.post(keyCode: Self.spaceKeyCode, keyDown: true, flags: .maskSecondaryFn)
            self?.post(keyCode: Self.spaceKeyCode, keyDown: false, flags: .maskSecondaryFn)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { [weak self] in
            self?.post(keyCode: Self.fnKeyCode, keyDown: false, flags: [])
        }
    }

    func postKey(
        _ keyCode: CGKeyCode,
        isDown: Bool,
        flags: CGEventFlags = [],
        autoRepeat: Bool = false
    ) {
        post(keyCode: keyCode, keyDown: isDown, flags: flags, autoRepeat: autoRepeat)
    }

    func tapKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        post(keyCode: keyCode, keyDown: true, flags: flags)
        post(keyCode: keyCode, keyDown: false, flags: flags)
    }

    func postShortcut(_ shortcut: KeyboardMapping, isDown: Bool, autoRepeat: Bool = false) {
        var flags = shortcut.flags
        if let ownModifier = KeyboardMapping.modifierFlag(for: shortcut.keyCode) {
            if isDown { flags.insert(ownModifier) } else { flags = [] }
        }
        postKey(shortcut.keyCode, isDown: isDown, flags: flags, autoRepeat: autoRepeat)
    }

    func tapShortcut(_ shortcut: KeyboardMapping) {
        if shortcut == .voiceToggle { tapFnSpace(); return }
        postShortcut(shortcut, isDown: true)
        postShortcut(shortcut, isDown: false)
    }

    private func post(
        keyCode: CGKeyCode,
        keyDown: Bool,
        flags: CGEventFlags,
        autoRepeat: Bool = false
    ) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
        else { return }
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: autoRepeat ? 1 : 0)
        event.setIntegerValueField(.eventSourceUserData, value: 0x52_4d_49_43)
        event.post(tap: .cghidEventTap)
    }
}
