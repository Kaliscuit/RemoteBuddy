import Foundation
import OSLog

/// Opt-in local HCI experiment. Only accepts fresh, addressed remote reports.
final class HCIReportSource {
    var onReport: (([UInt8]) -> Void)?
    var onStopped: (() -> Void)?
    private var timer: Timer?
    private var file: FileHandle?
    private var pending = Data()
    private let logger = Logger(subsystem: "local.codex.RemoteMic", category: "hci-bridge")

    private struct Message: Decodable {
        let type: String
        let received_at: Double
        let address: String
        let bytes: [UInt8]?
    }

    @discardableResult
    func start(path: String) -> Bool {
        stop()
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              let file = FileHandle(forReadingAtPath: path) else {
            logger.error("HCI source missing or not private to this user")
            onStopped?()
            return false
        }
        self.file = file
        // Start at the live end; never replay earlier keyboard actions.
        _ = try? file.seekToEnd()
        let timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] _ in self?.drain() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        logger.notice("HCI live source ready; accessibility permission is checked separately")
        return true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        try? file?.close()
        file = nil
        pending.removeAll()
    }

    private func drain() {
        guard let file else { return }
        do {
            if let data = try file.read(upToCount: 4096) { pending.append(data) }
            guard pending.count <= 65536 else { throw CocoaError(.fileReadCorruptFile) }
            while let end = pending.firstIndex(of: 10) {
                let line = pending[..<end]
                let message = try JSONDecoder().decode(Message.self, from: line)
                pending.removeSubrange(...end)
                guard message.address.uppercased() == RemoteIdentity.configuredAddress else { continue }
                let age = Date().timeIntervalSince1970 - message.received_at
                guard age >= -0.1, age < 0.25 else { continue }
                if message.type == "stop" {
                    stop()
                    onStopped?()
                    return
                }
                if message.type == "report", let bytes = message.bytes,
                   RemoteButtonReport.decode(bytes, includesReportID: false) != nil {
                    logger.notice("HCI report delivery_ms=\(age * 1000) bytes=\(bytes.map { String(format: "%02X", $0) }.joined(separator: " "), privacy: .public)")
                    onReport?(bytes)
                }
            }
        } catch {
            logger.error("HCI source stopped: \(error.localizedDescription, privacy: .public)")
            stop()
            onStopped?()
        }
    }
}
