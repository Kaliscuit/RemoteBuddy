import Foundation

/// Report 1 is a two-slot Consumer array, not a sequence of key presses.
enum RemoteButtonReport {
    static func decode(_ bytes: [UInt8], includesReportID: Bool) -> Set<UInt8>? {
        var payload = bytes
        if includesReportID {
            guard payload.first == 1 else { return nil }
            payload.removeFirst()
        }
        guard (1...2).contains(payload.count), payload.allSatisfy({ $0 <= 17 }) else { return nil }
        return Set(payload.filter { $0 != 0 })
    }
}

struct RemoteButtonChange: Equatable {
    let button: UInt8
    let isDown: Bool
    var isRepeat = false
}

struct RemoteButtonState {
    // Never keep a synthetic key held indefinitely after a lost release.
    static let maximumHold: TimeInterval = 2
    private(set) var pressed = Set<UInt8>()
    private var suppressed = Set<UInt8>()
    private var began: [UInt8: TimeInterval] = [:]
    private var nextRepeat: [UInt8: TimeInterval] = [:]

    mutating func update(_ buttons: Set<UInt8>, now: TimeInterval,
                         repeatableButtons: Set<UInt8> = [3, 4, 5, 6, 12, 13]) -> [RemoteButtonChange] {
        suppressed.formIntersection(buttons)
        let accepted = buttons.subtracting(suppressed)
        let released = pressed.subtracting(accepted).sorted()
        let added = accepted.subtracting(pressed).sorted()
        for button in released { began[button] = nil; nextRepeat[button] = nil }
        for button in added {
            began[button] = now
            if repeatableButtons.contains(button) { nextRepeat[button] = now + 0.34 }
        }
        pressed = accepted
        return released.map { RemoteButtonChange(button: $0, isDown: false) }
            + added.map { RemoteButtonChange(button: $0, isDown: true) }
    }

    mutating func tick(now: TimeInterval) -> [RemoteButtonChange] {
        var changes: [RemoteButtonChange] = []
        for button in pressed.sorted() {
            if now - (began[button] ?? now) >= Self.maximumHold {
                pressed.remove(button)
                suppressed.insert(button)
                began[button] = nil
                nextRepeat[button] = nil
                changes.append(RemoteButtonChange(button: button, isDown: false))
            } else if let next = nextRepeat[button], now >= next {
                // Do not replay a backlog when the run loop was delayed.
                nextRepeat[button] = now + 0.065
                changes.append(RemoteButtonChange(button: button, isDown: true, isRepeat: true))
            }
        }
        return changes
    }

    mutating func reset() -> [RemoteButtonChange] {
        let changes = pressed.sorted().map { RemoteButtonChange(button: $0, isDown: false) }
        self = Self()
        return changes
    }
}
