import Foundation

/// Tracks transport liveness, not signal loudness: quiet speech must not time out.
struct VoiceSessionWatchdog {
    private(set) var generation: UInt64 = 0
    private var waitingSince: TimeInterval?
    private var lastAudioAt: TimeInterval?
    private var stoppingSince: TimeInterval?
    var awaitingStop: Bool { stoppingSince != nil }

    mutating func invalidate() {
        generation &+= 1
        waitingSince = nil
        lastAudioAt = nil
        stoppingSince = nil
    }

    mutating func awaitingStream(at now: TimeInterval) {
        waitingSince = now
        lastAudioAt = nil
    }

    mutating func receivedAudio(at now: TimeInterval) {
        waitingSince = nil
        lastAudioAt = now
    }

    mutating func requestedStop(at now: TimeInterval) {
        stoppingSince = now
    }

    func hasTimedOut(at now: TimeInterval) -> Bool {
        if let stoppingSince { return now - stoppingSince >= 2 }
        if let waitingSince { return now - waitingSince >= 3 }
        if let lastAudioAt { return now - lastAudioAt >= 3 }
        return false
    }
}
