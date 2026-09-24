import AppKit
import CoreGraphics
import Foundation
import IOKit.hid
import OSLog

private func remoteButtonMatched(context: UnsafeMutableRawPointer?, result: IOReturn,
                                 sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context, result == kIOReturnSuccess else { return }
    Unmanaged<RemoteButtonController>.fromOpaque(context).takeUnretainedValue().deviceMatched(device)
}

private func remoteButtonRemoved(context: UnsafeMutableRawPointer?, result: IOReturn,
                                 sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context else { return }
    Unmanaged<RemoteButtonController>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
}

private func remoteButtonReportReceived(context: UnsafeMutableRawPointer?, result: IOReturn,
    sender: UnsafeMutableRawPointer?, type: IOHIDReportType, reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>, reportLength: CFIndex, timeStamp: UInt64) {
    guard let context, result == kIOReturnSuccess, type == kIOHIDReportTypeInput,
          reportID == 1, reportLength > 0 else { return }
    Unmanaged<RemoteButtonController>.fromOpaque(context).takeUnretainedValue()
        .handleNativeReport(Array(UnsafeBufferPointer(start: report, count: reportLength)), timestamp: timeStamp)
}

final class RemoteButtonController {
    static let vendorID = 0x18d1
    static let productID = 0x9450
    var onStatus: ((String) -> Void)?
    var onButtonActivity: ((UInt8, Bool) -> Void)?

    private let logger = Logger(subsystem: "local.codex.RemoteMic", category: "buttons")
    private let actionSender = MappedActionSender()
    private var activeActions: [UInt8: MappedAction] = [:]
    private var reportedButtons = Set<UInt8>()
    private var blockedUntilRelease = Set<UInt8>()
    private var configuring = false
    private var manager: IOHIDManager?
    private var state = RemoteButtonState()
    private var timer: Timer?
    private let reader = HIDReportReader()
    private var reading = false
    private var hciBridge = false
    private var connectedDevice: IOHIDDevice?
    private(set) var experimentalReading = false
    private var timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    func start() {
        stop()
        // The HCI bridge also needs repeat/release timers and error reporting,
        // even when macOS refuses access to the native HID device.
        actionSender.onError = { [weak self] in self?.onStatus?($0) }
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.apply(self.state.tick(now: ProcessInfo.processInfo.systemUptime))
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, remoteButtonMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, remoteButtonRemoved, context)
        IOHIDManagerRegisterInputReportWithTimeStampCallback(manager, remoteButtonReportReceived, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0)
            logger.error("HID open failed: \(result, privacy: .public)")
            onStatus?(L10n.tr("按键：HID 打开失败"))
            return
        }
        self.manager = manager
        onStatus?(L10n.tr("按键：等待遥控器…"))
    }

    func stop() {
        hciBridge = false
        reader.stop()
        connectedDevice = nil
        reportedButtons.removeAll()
        blockedUntilRelease.removeAll()
        timer?.invalidate()
        timer = nil
        apply(state.reset())
        reading = false
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0)
        }
        manager = nil
    }

    fileprivate func deviceMatched(_ device: IOHIDDevice) {
        logger.notice("Native HID report listener ready; single report source; hold watchdog 2s")
        connectedDevice = device
        apply(state.reset())
        reader.onReport = { [weak self] bytes, elapsed, completed in
            guard let self else { return }
            // An empty read response means no notification, NOT key-up.
            // Real key-up is a one-byte 00 notification.
            guard !bytes.isEmpty else { return }
            self.logger.notice("Read HID len=\(bytes.count) duration_ms=\(elapsed * 1000) bytes=\(bytes.map { String(format: "%02X", $0) }.joined(separator: " "), privacy: .public)")
            guard elapsed < 0.25, ProcessInfo.processInfo.systemUptime - completed < 0.25 else {
                self.apply(self.state.reset())
                return
            }
            self.handle(bytes, includesReportID: false, source: "read")
        }
        reader.onError = { [weak self] error in
            guard let self else { return }
            self.logger.error("Read HID failed code=\(error)")
            self.apply(self.state.reset())
            self.reading = false
            self.onStatus?(L10n.tr("按键：读取失败，请重新连接遥控器"))
        }
        setExperimentalReading(experimentalReading)
    }

    func setExperimentalReading(_ enabled: Bool) {
        experimentalReading = enabled
        reader.stop()
        apply(state.reset())
        reading = enabled && connectedDevice != nil
        if let connectedDevice, enabled {
            reader.start(device: connectedDevice)
        }
        let status = hciBridge ? L10n.tr("按键：兼容桥接已连接") :
            (reading ? L10n.tr("按键：实验读取开启 · 仍可能漏键") : L10n.tr("按键：单按兼容问题尚未解决"))
        logger.notice("\(status, privacy: .public)")
        onStatus?(status)
    }

    func setHCIBridge(_ enabled: Bool) {
        reader.stop()
        reading = false
        apply(state.reset())
        hciBridge = enabled
        onStatus?(enabled ? L10n.tr("按键：兼容桥接已连接") : L10n.tr("按键：等待兼容桥接"))
    }

    func handleHCIReport(_ bytes: [UInt8]) {
        guard hciBridge else { return }
        handle(bytes, includesReportID: false, source: "HCI")
    }

    func resetHCIButtons() {
        apply(state.reset())
        reportedButtons.removeAll()
        blockedUntilRelease.removeAll()
    }

    func mappingWillChange() {
        apply(state.reset())
        blockedUntilRelease.formUnion(reportedButtons)
    }

    func setConfiguring(_ enabled: Bool) {
        guard configuring != enabled else { return }
        mappingWillChange()
        configuring = enabled
    }

    fileprivate func deviceRemoved(_ device: IOHIDDevice) {
        guard let connectedDevice, CFEqual(connectedDevice, device) else { return }
        self.connectedDevice = nil
        reader.stop()
        reading = false
        apply(state.reset())
        onStatus?(L10n.tr("按键：遥控器已断开"))
    }

    fileprivate func handleNativeReport(_ bytes: [UInt8], timestamp: UInt64) {
        let now = mach_absolute_time()
        let age = timestamp <= now ? Double(now - timestamp) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000 : 0
        logger.notice("Native HID len=\(bytes.count) age_ms=\(age) bytes=\(bytes.map { String(format: "%02X", $0) }.joined(separator: " "), privacy: .public)")
        guard !reading && !hciBridge else { return }
        guard age < 250 else { apply(state.reset()); return }
        handle(bytes, includesReportID: true, source: "HID")
    }

    private func handle(_ bytes: [UInt8], includesReportID: Bool, source: String) {
        guard let pressed = RemoteButtonReport.decode(bytes, includesReportID: includesReportID) else {
            logger.error("Rejected malformed \(source, privacy: .public) report")
            return
        }
        for button in reportedButtons.subtracting(pressed).sorted() { onButtonActivity?(button, false) }
        for button in pressed.subtracting(reportedButtons).sorted() { onButtonActivity?(button, true) }
        reportedButtons = pressed
        blockedUntilRelease.formIntersection(pressed)
        guard !configuring else { return }
        apply(state.update(pressed.subtracting(blockedUntilRelease), now: ProcessInfo.processInfo.systemUptime))
    }

    private func apply(_ changes: [RemoteButtonChange]) {
        for change in changes {
            if !change.isRepeat {
                logger.notice("Button id=\(change.button) down=\(change.isDown) source=\(self.hciBridge ? "HCI" : (self.reading ? "read" : "HID"), privacy: .public)")
            }
            post(button: change.button, isDown: change.isDown, autoRepeat: change.isRepeat)
        }
    }

    private func post(button: UInt8, isDown: Bool, autoRepeat: Bool) {
        if isDown {
            let action = activeActions[button] ?? MappingStore.shared.configuration.action(for: button)
            if !autoRepeat { activeActions[button] = action }
            actionSender.send(action, isDown: true, repeated: autoRepeat)
        } else if let action = activeActions.removeValue(forKey: button) {
            actionSender.send(action, isDown: false)
        }
    }
}
