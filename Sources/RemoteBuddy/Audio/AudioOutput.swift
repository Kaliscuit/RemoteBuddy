import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

final class SampleRing {
    private let lock = NSLock()
    private var storage = [Float](repeating: 0, count: 65_536)
    private var readIndex = 0
    private var writeIndex = 0
    private var count = 0

    func append(_ samples: [Int16], sampleRate: Int) {
        lock.lock()
        defer { lock.unlock() }
        let duplicate = sampleRate == 8_000 ? 2 : 1
        for sample in samples {
            let value = max(-1, min(1, Float(sample) / 8192.0))
            for _ in 0..<duplicate {
                storage[writeIndex] = value
                writeIndex = (writeIndex + 1) % storage.count
                if count == storage.count {
                    readIndex = (readIndex + 1) % storage.count
                } else {
                    count += 1
                }
            }
        }
    }

    func read(into pointer: UnsafeMutablePointer<Float>, count requested: Int) {
        lock.lock()
        defer { lock.unlock() }
        for index in 0..<requested {
            if count > 0 {
                pointer[index] = storage[readIndex]
                readIndex = (readIndex + 1) % storage.count
                count -= 1
            } else {
                pointer[index] = 0
            }
        }
    }

    func clear() {
        lock.lock()
        readIndex = 0
        writeIndex = 0
        count = 0
        lock.unlock()
    }
}

final class AudioOutput {
    private let engine = AVAudioEngine()
    private let ring = SampleRing()
    private var sourceNode: AVAudioSourceNode?
    private(set) var deviceName = ""

    func start(preferredDeviceName: String = "BlackHole 2ch") throws {
        let device = try findOutputDevice(containing: preferredDeviceName)
        guard let audioUnit = engine.outputNode.audioUnit else {
            throw NSError(domain: "RemoteMic", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.tr("无法访问音频输出单元")])
        }
        var deviceID = device.id
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else {
            throw NSError(domain: "RemoteMic", code: 3, userInfo: [NSLocalizedDescriptionKey: L10n.tr("无法创建 16 kHz 音频格式")])
        }
        let source = AVAudioSourceNode(format: format) { [ring] _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let data = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            ring.read(into: data, count: Int(frameCount))
            return noErr
        }
        sourceNode = source
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        engine.prepare()
        try engine.start()
        deviceName = device.name
    }

    func feed(_ samples: [Int16], sampleRate: Int) {
        ring.append(samples, sampleRate: sampleRate)
    }

    func clear() { ring.clear() }

    private func findOutputDevice(containing needle: String) throws -> (id: AudioDeviceID, name: String) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        )
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices
        )
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }

        for id in devices {
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameReference: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(
                id, &nameAddress, 0, nil, &nameSize, &nameReference
            ) == noErr, let nameReference {
                let name = nameReference.takeUnretainedValue() as String
                if name.localizedCaseInsensitiveContains(needle) {
                    return (id, name)
                }
            }
        }
        throw NSError(
            domain: "RemoteMic",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: L10n.format("未找到 %@，请先安装 BlackHole 2ch", needle)]
        )
    }
}
