import Darwin
import Foundation
import OSLog

/// User-side client. The service exposes addressed reports and a bounded,
/// validated device-selection operation; it never accepts executable commands.
final class HCISocketSource {
    var onReport: (([UInt8]) -> Void)?
    var onActive: ((Bool) -> Void)?
    var onReset: (() -> Void)?
    var onStatus: ((String) -> Void)?
    private let logger = Logger(subsystem: "local.codex.RemoteMic", category: "hci-service")
    private var source: DispatchSourceRead?
    private var timer: Timer?
    private var descriptor: Int32 = -1
    private var pending = Data()
    private var active = false
    private var expectedAddress: String?
    private var lastMessage = ProcessInfo.processInfo.systemUptime
    private var status = ""
    private var supportsConfiguration = false
    private var configurationRequest: (value: RemoteConfiguration, started: TimeInterval,
        completion: (Result<RemoteConfiguration, Error>) -> Void)?

    private struct Message: Decodable {
        let type: String
        let address: String
        let received_at: Double
        let captured_at: Double?
        let bytes: [UInt8]?
        let ready: Bool?
        let remote_connected: Bool?
        let protocol_version: Int?
        let configuration: RemoteConfiguration?
    }

    func start() {
        stop()
        connect()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.descriptor < 0 {
                self.connect()
            } else if ProcessInfo.processInfo.systemUptime - self.lastMessage > 4 ||
                        self.configurationRequest.map({ ProcessInfo.processInfo.systemUptime - $0.started > 4 }) == true {
                self.disconnect()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        disconnect()
    }

    func configure(_ value: RemoteConfiguration, completion: @escaping (Result<RemoteConfiguration, Error>) -> Void) {
        guard descriptor >= 0 else { completion(.failure(RemoteSettingsError.unavailableService)); return }
        guard supportsConfiguration else { completion(.failure(RemoteSettingsError.outdatedService)); return }
        guard configurationRequest == nil else { completion(.failure(RemoteSettingsError.saveFailed)); return }
        do {
            let encoded = try JSONEncoder().encode(value)
            guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
                throw RemoteSettingsError.saveFailed
            }
            object["type"] = "configure"
            var request = try JSONSerialization.data(withJSONObject: object)
            request.append(10)
            configurationRequest = (value, ProcessInfo.processInfo.systemUptime, completion)
            let sent = request.withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress, $0.count, 0) }
            if sent != request.count { disconnect() }
        } catch { completion(.failure(error)) }
    }

    private func connect() {
        guard let configuredAddress = RemoteIdentity.configuredAddress else {
            setStatus(L10n.tr("按键：等待兼容辅助服务"))
            return
        }
        expectedAddress = configuredAddress
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { Darwin.close(fd); return }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let path = Array("/var/run/local.codex.RemoteMic.hci.sock".utf8) + [0]
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path)
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        var uid: uid_t = 99999
        var gid: gid_t = 99999
        guard result == 0, getpeereid(fd, &uid, &gid) == 0, uid == 0 else {
            Darwin.close(fd)
            setStatus(L10n.tr("按键：等待兼容辅助服务"))
            return
        }
        descriptor = fd
        pending.removeAll()
        lastMessage = ProcessInfo.processInfo.systemUptime
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { Darwin.close(fd) }
        self.source = source
        source.resume()
        setStatus(L10n.tr("按键：正在连接兼容通道"))
    }

    private func disconnect() {
        let request = configurationRequest
        configurationRequest = nil
        supportsConfiguration = false
        source?.cancel()
        source = nil
        descriptor = -1
        pending.removeAll()
        setActive(false)
        request?.completion(.failure(RemoteSettingsError.saveFailed))
    }

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        // Bound each callback so unexpected input cannot monopolize the UI.
        for _ in 0..<16 {
            guard descriptor >= 0 else { return }
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { disconnect(); return }
            if count < 0 {
                if errno != EAGAIN && errno != EWOULDBLOCK { disconnect() }
                return
            }
            pending.append(contentsOf: buffer.prefix(count))
            guard pending.count <= 65536 else { disconnect(); return }
            while let end = pending.firstIndex(of: 10) {
                let line = Data(pending[..<end])
                pending.removeSubrange(...end)
                guard let message = try? JSONDecoder().decode(Message.self, from: line),
                      message.address.uppercased() == expectedAddress else {
                    disconnect()
                    return
                }
                lastMessage = ProcessInfo.processInfo.systemUptime
                if message.type == "configured" || message.type == "configuration_error" {
                    let request = configurationRequest
                    configurationRequest = nil
                    if let request, message.type == "configured", message.configuration == request.value {
                        request.completion(.success(request.value))
                    } else {
                        request?.completion(.failure(RemoteSettingsError.saveFailed))
                    }
                    return
                }
                let now = Date().timeIntervalSince1970
                let age = now - message.received_at
                guard age >= -0.1, age < 0.25 else { onReset?(); continue }
                switch message.type {
                case "connected":
                    supportsConfiguration = (message.protocol_version ?? 1) >= 2
                    setStatus(L10n.tr("按键：正在等待遥控器数据"))
                case "heartbeat":
                    if message.ready == true, message.remote_connected == true {
                        setActive(true)
                        setStatus(L10n.tr("按键：兼容桥接已连接"))
                    } else {
                        setActive(false)
                        setStatus(message.ready == true ? L10n.tr("按键：等待遥控器连接") : L10n.tr("按键：等待蓝牙原始数据，请检查兼容配置"))
                    }
                case "report":
                    guard let bytes = message.bytes,
                          RemoteButtonReport.decode(bytes, includesReportID: false) != nil else { continue }
                    if let captured = message.captured_at, now - captured > 0.25 {
                        onReset?()
                        continue
                    }
                    setActive(true)
                    setStatus(L10n.tr("按键：兼容桥接已连接"))
                    logger.notice("Report bytes=\(bytes.map { String(format: "%02X", $0) }.joined(separator: " "), privacy: .public) handoff_ms=\(age * 1000)")
                    onReport?(bytes)
                case "reset": onReset?()
                default: break
                }
            }
        }
    }

    private func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        onActive?(value)
    }

    private func setStatus(_ value: String) {
        guard status != value else { return }
        status = value
        logger.notice("\(value, privacy: .public)")
        onStatus?(value)
    }
}
