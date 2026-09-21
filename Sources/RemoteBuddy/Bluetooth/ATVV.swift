import Foundation

enum ATVVCodec: UInt8 {
    case adpcm8k = 0x01
    case adpcm16k = 0x02

    var sampleRate: Int { self == .adpcm16k ? 16_000 : 8_000 }
}

enum ATVVVersion { case v04, v10 }

struct ATVVCapabilities {
    let version: ATVVVersion
    let codecs: UInt8
    let frameSize: Int

    var preferredCodec: ATVVCodec? {
        if codecs & ATVVCodec.adpcm16k.rawValue != 0 { return .adpcm16k }
        if codecs & ATVVCodec.adpcm8k.rawValue != 0 { return .adpcm8k }
        return nil
    }
}

enum ATVVEvent {
    case capabilities(ATVVCapabilities)
    case startSearch
    case audioStart(reason: UInt8, codec: ATVVCodec, streamID: UInt8)
    case audioStop(reason: UInt8)
    case audioSync(codec: ATVVCodec, sequence: UInt16, predictor: Int16, stepIndex: UInt8)
    case error(UInt16)
    case unknown
}

struct ATVVSession {
    static let serviceUUID = "AB5E0001-5A21-4F05-BC7D-AF01F617B664"
    static let commandUUID = "AB5E0002-5A21-4F05-BC7D-AF01F617B664"
    static let audioUUID = "AB5E0003-5A21-4F05-BC7D-AF01F617B664"
    static let controlUUID = "AB5E0004-5A21-4F05-BC7D-AF01F617B664"

    let capabilitiesRequest = Data([0x0a, 0x01, 0x00, 0x00, 0x03, 0x03])
    private(set) var capabilities: ATVVCapabilities?
    private(set) var codec: ATVVCodec?
    private(set) var streamID: UInt8 = 0
    private var sequence: UInt16 = 0
    private var decoder = ADPCMDecoder()
    private var synchronizedForNextStart = false
    private var audioActive = false

    mutating func accept(_ capabilities: ATVVCapabilities) -> Bool {
        guard let codec = capabilities.preferredCodec else { return false }
        self.capabilities = capabilities
        self.codec = codec
        decoder.reset(predictor: 0, stepIndex: 0)
        sequence = 0
        synchronizedForNextStart = false
        audioActive = false
        return true
    }

    mutating func parseControl(_ data: Data) -> ATVVEvent {
        let b = [UInt8](data)
        guard let opcode = b.first else { return .unknown }
        switch opcode {
        case 0x00:
            return .audioStop(reason: b.count > 1 ? b[1] : 0)
        case 0x04:
            if capabilities?.version == .v10, b.count >= 4, let c = ATVVCodec(rawValue: b[2]) {
                return .audioStart(reason: b[1], codec: c, streamID: b[3])
            }
            return .audioStart(reason: 0, codec: codec ?? .adpcm8k, streamID: 0)
        case 0x08:
            return .startSearch
        case 0x0a:
            guard capabilities?.version == .v10, b.count >= 7,
                  let c = ATVVCodec(rawValue: b[1]) else { return .unknown }
            let seq = UInt16(b[2]) << 8 | UInt16(b[3])
            let pred = Int16(bitPattern: UInt16(b[4]) << 8 | UInt16(b[5]))
            return .audioSync(codec: c, sequence: seq, predictor: pred, stepIndex: b[6])
        case 0x0b:
            guard let caps = Self.parseCapabilities(b) else { return .unknown }
            return .capabilities(caps)
        case 0x0c:
            let code = b.count >= 3 ? UInt16(b[1]) << 8 | UInt16(b[2]) : 0xffff
            return .error(code)
        default:
            return .unknown
        }
    }

    static func parseCapabilities(_ b: [UInt8]) -> ATVVCapabilities? {
        guard b.count >= 3, b[0] == 0x0b else { return nil }
        switch UInt16(b[1]) << 8 | UInt16(b[2]) {
        case 0x0004 where b.count >= 9:
            return ATVVCapabilities(
                version: .v04,
                codecs: b[4],
                frameSize: Int(UInt16(b[5]) << 8 | UInt16(b[6]))
            )
        case 0x0100 where b.count >= 7:
            return ATVVCapabilities(
                version: .v10,
                codecs: b[3],
                frameSize: Int(UInt16(b[5]) << 8 | UInt16(b[6]))
            )
        default:
            return nil
        }
    }

    mutating func prepareOpen() {
        sequence = 0
        decoder.reset(predictor: 0, stepIndex: 0)
        synchronizedForNextStart = false
        audioActive = false
    }

    mutating func applySync(codec: ATVVCodec, sequence: UInt16, predictor: Int16, stepIndex: UInt8) {
        self.codec = codec
        self.sequence = sequence
        decoder.reset(predictor: predictor, stepIndex: stepIndex)
        synchronizedForNextStart = !audioActive
    }

    mutating func begin(codec: ATVVCodec, streamID: UInt8) {
        self.codec = codec
        self.streamID = streamID
        if !synchronizedForNextStart {
            sequence = 0
            decoder.reset(predictor: 0, stepIndex: 0)
        }
        synchronizedForNextStart = false
        audioActive = true
    }

    mutating func end() {
        audioActive = false
        synchronizedForNextStart = false
    }

    func openCommand() -> Data? {
        guard let capabilities, let codec else { return nil }
        return capabilities.version == .v04
            ? Data([0x0c, 0x00, codec.rawValue])
            : Data([0x0c, 0x00])
    }

    func closeCommand() -> Data? {
        guard let capabilities else { return nil }
        return capabilities.version == .v04 ? Data([0x0d]) : Data([0x0d, streamID])
    }

    func closeAllCommand() -> Data? {
        guard let capabilities else { return nil }
        return capabilities.version == .v04 ? Data([0x0d]) : Data([0x0d, 0xff])
    }

    func keepAliveCommand() -> Data? {
        guard let capabilities else { return nil }
        return capabilities.version == .v04 ? openCommand() : Data([0x0e, streamID])
    }

    mutating func decodeAudio(_ data: Data) -> [Int16]? {
        guard let capabilities, codec != nil else { return nil }
        let b = [UInt8](data)
        switch capabilities.version {
        case .v04:
            guard b.count == capabilities.frameSize, b.count >= 6 else { return nil }
            let predictor = Int16(bitPattern: UInt16(b[3]) << 8 | UInt16(b[4]))
            decoder.reset(predictor: predictor, stepIndex: b[5])
            return [predictor] + decoder.decode(b.dropFirst(6))
        case .v10:
            guard !b.isEmpty else { return nil }
            sequence &+= 1
            return decoder.decode(b)
        }
    }
}
