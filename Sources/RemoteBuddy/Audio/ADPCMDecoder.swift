import Foundation

struct ADPCMDecoder {
    private static let indexTable: [Int] = [
        -1, -1, -1, -1, 2, 4, 6, 8,
        -1, -1, -1, -1, 2, 4, 6, 8,
    ]

    private static let stepTable: [Int] = [
        7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
        34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143,
        157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544,
        598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707,
        1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871,
        5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
        15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
    ]

    private(set) var predictor = 0
    private(set) var stepIndex = 0

    mutating func reset(predictor: Int16, stepIndex: UInt8) {
        self.predictor = Int(predictor)
        self.stepIndex = min(88, Int(stepIndex))
    }

    mutating func decode<S: Sequence>(_ bytes: S) -> [Int16] where S.Element == UInt8 {
        var result: [Int16] = []
        for byte in bytes {
            // Google Voice over BLE 1.0, section 4.2: high nibble first.
            // IMA WAV packs nibbles differently; ATVV is not an IMA WAV block.
            result.append(decodeNibble(Int(byte >> 4)))
            result.append(decodeNibble(Int(byte & 0x0f)))
        }
        return result
    }

    private mutating func decodeNibble(_ nibble: Int) -> Int16 {
        let step = Self.stepTable[stepIndex]
        var delta = step >> 3
        if nibble & 1 != 0 { delta += step >> 2 }
        if nibble & 2 != 0 { delta += step >> 1 }
        if nibble & 4 != 0 { delta += step }
        predictor += nibble & 8 != 0 ? -delta : delta
        predictor = min(32767, max(-32768, predictor))
        stepIndex += Self.indexTable[nibble]
        stepIndex = min(88, max(0, stepIndex))
        return Int16(predictor)
    }
}
