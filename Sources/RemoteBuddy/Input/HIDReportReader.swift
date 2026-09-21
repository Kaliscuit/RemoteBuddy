import Foundation
import IOKit.hid

/// Reads the unparsed GATT value through the system HID transport. Work stays
/// off the AppKit/voice queue; at most one device request can be outstanding.
final class HIDReportReader {
    var onReport: (([UInt8], TimeInterval, TimeInterval) -> Void)?
    var onError: ((IOReturn) -> Void)?
    private let worker = DispatchQueue(label: "local.codex.RemoteMic.report-read", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var generation = UUID()

    func start(device: IOHIDDevice) {
        stop()
        let generation = self.generation
        let timer = DispatchSource.makeTimerSource(queue: worker)
        // The remote's read responses are empty; a pending read also exposes
        // intervening short notifications, before the HID descriptor parser.
        // Keep a request outstanding. A 25 ms timer left gaps between the
        // 15-30 ms transactions and missed some presses. The serial worker
        // prevents overlapping requests or a catch-up request backlog.
        timer.schedule(deadline: .now(), repeating: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            let started = ProcessInfo.processInfo.systemUptime
            var bytes = [UInt8](repeating: 0, count: 32)
            var length = bytes.count
            let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeInput, 1, &bytes, &length)
            let completed = ProcessInfo.processInfo.systemUptime
            let elapsed = completed - started
            let data = Array(bytes.prefix(max(0, min(length, bytes.count))))
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation else { return }
                if result == kIOReturnSuccess {
                    self.onReport?(data, elapsed, completed)
                } else {
                    self.stop()
                    self.onError?(result)
                }
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        generation = UUID()
        timer?.cancel()
        timer = nil
    }

    deinit { timer?.cancel() }
}
