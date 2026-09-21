import CoreHID
import Foundation
import OSLog

/// Opt-in, capture-only experiment. Never injects keys or polls the device.
@available(macOS 15, *)
@MainActor
final class CoreHIDProbe {
    var onStatus: ((String) -> Void)?
    private let logger = Logger(subsystem: "local.codex.RemoteMic", category: "corehid-probe")
    private var managerTask: Task<Void, Never>?
    private var deviceTasks: [UInt64: Task<Void, Never>] = [:]
    private let dateFormatter = ISO8601DateFormatter()
    private var output: FileHandle?
    private var reportCount = 0

    init() {
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let path = "/tmp/local.codex.RemoteMic.corehid.log"
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        output = FileHandle(forWritingAtPath: path)
        _ = try? output?.seekToEnd()
    }

    func start() {
        stop()
        record("SESSION start: CoreHID only; no legacy IOHID reader, no get-report polling, no key injection")
        let manager = HIDDeviceManager()
        managerTask = Task { [weak self] in
            let criteria = HIDDeviceManager.DeviceMatchingCriteria(vendorID: 0x18d1, productID: 0x9450)
            do {
                for try await notification in await manager.monitorNotifications(matchingCriteria: [criteria]) {
                    guard let self, !Task.isCancelled else { break }
                    switch notification {
                    case .deviceMatched(let reference):
                        self.monitor(reference)
                    case .deviceRemoved(let reference):
                        self.deviceTasks.removeValue(forKey: reference.deviceID)?.cancel()
                        self.record("REMOVED device=\(reference.deviceID)")
                    @unknown default: break
                    }
                }
            } catch {
                self?.record("ERROR discovery: \(error)")
            }
        }
    }

    func stop() {
        managerTask?.cancel()
        managerTask = nil
        for task in deviceTasks.values { task.cancel() }
        deviceTasks.removeAll()
    }

    private func monitor(_ reference: HIDDeviceClient.DeviceReference) {
        guard deviceTasks[reference.deviceID] == nil else { return }
        deviceTasks[reference.deviceID] = Task { [weak self] in
            guard let client = HIDDeviceClient(deviceReference: reference), let self else { return }
            let descriptor = await client.descriptor
            self.record("MATCH device=\(reference.deviceID) descriptor=\(Self.hex(descriptor))")
            do {
                try await client.seizeDevice()
                self.record("SEIZED device=\(reference.deviceID)")
                let stream = await client.monitorNotifications(
                    reportIDsToMonitor: [HIDReportID.allReports], elementsToMonitor: await client.elements
                )
                self.record("READY: listening for raw reports and element updates")
                self.onStatus?(L10n.tr("按键：CoreHID 诊断中（仅记录）"))
                for try await notification in stream {
                    guard !Task.isCancelled else { break }
                    switch notification {
                    case .inputReport(let id, let data, let timestamp):
                        self.reportCount += 1
                        let age = timestamp.duration(to: SuspendingClock.now).components
                        let milliseconds = Double(age.seconds) * 1000 + Double(age.attoseconds) / 1e15
                        self.record("REPORT n=\(self.reportCount) id=\(id?.rawValue ?? 0) len=\(data.count) age_ms=\(String(format: "%.3f", milliseconds)) bytes=\(Self.hex(data))")
                    case .elementUpdates(let values):
                        for value in values {
                            self.record("ELEMENT usage=\(value.element.usage) bytes=\(Self.hex(value.bytes))")
                        }
                    case .deviceSeized: self.record("OTHER CLIENT SEIZED")
                    case .deviceUnseized: self.record("OTHER CLIENT UNSEIZED")
                    case .deviceRemoved: self.record("STREAM DEVICE REMOVED")
                    @unknown default: break
                    }
                }
            } catch {
                self.record("ERROR device=\(reference.deviceID): \(error)")
                self.onStatus?(L10n.tr("按键：CoreHID 诊断失败"))
            }
        }
    }

    private func record(_ text: String) {
        logger.notice("\(text, privacy: .public)")
        let line = dateFormatter.string(from: Date()) + " " + text + "\n"
        try? output?.write(contentsOf: Data(line.utf8))
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
