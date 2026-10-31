import Foundation

public enum WAVError: Error, Equatable, Sendable {
    case notRIFF
    case unsupportedFormat(String)
    case truncated
}

/// Minimal WAV codec. Writes 16-bit PCM mono; reads 16-bit PCM or 32-bit float, downmixing to mono.
public enum WAVFile {
    public static func encode(_ clip: AudioClip) -> Data {
        let sampleRate = UInt32(clip.sampleRate)
        let dataSize = UInt32(clip.samples.count * 2)
        var data = Data(capacity: 44 + Int(dataSize))
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLE(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))  // PCM
        data.appendLE(UInt16(1))  // mono
        data.appendLE(sampleRate)
        data.appendLE(sampleRate * 2)  // byte rate
        data.appendLE(UInt16(2))  // block align
        data.appendLE(UInt16(16))  // bits per sample
        data.append(contentsOf: Array("data".utf8))
        data.appendLE(dataSize)
        for sample in clip.samples {
            data.appendLE(Int16((max(-1, min(1, sample)) * Float(Int16.max)).rounded()))
        }
        return data
    }

    public static func decode(_ data: Data) throws -> AudioClip {
        let bytes = [UInt8](data)
        guard bytes.count >= 12,
            String(decoding: bytes[0..<4], as: UTF8.self) == "RIFF",
            String(decoding: bytes[8..<12], as: UTF8.self) == "WAVE"
        else { throw WAVError.notRIFF }

        var format: Format?
        var offset = 12
        while offset + 8 <= bytes.count {
            let chunkID = String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
            let size = Int(bytes.readLE(UInt32.self, at: offset + 4))
            let body = offset + 8
            guard body + size <= bytes.count else { throw WAVError.truncated }
            if chunkID == "fmt " {
                guard size >= 16 else { throw WAVError.truncated }
                let parsed = Format(
                    tag: bytes.readLE(UInt16.self, at: body),
                    channels: Int(bytes.readLE(UInt16.self, at: body + 2)),
                    sampleRate: Double(bytes.readLE(UInt32.self, at: body + 4)),
                    bits: bytes.readLE(UInt16.self, at: body + 14))
                guard parsed.channels > 0, parsed.sampleRate > 0 else {
                    throw WAVError.unsupportedFormat("zero channels or sample rate")
                }
                format = parsed
            } else if chunkID == "data" {
                guard let format else { throw WAVError.unsupportedFormat("data chunk before fmt chunk") }
                return try decodeSamples(Array(bytes[body..<body + size]), format: format)
            }
            offset = body + size + (size % 2)
        }
        throw WAVError.truncated
    }

    private struct Format {
        let tag: UInt16
        let channels: Int
        let sampleRate: Double
        let bits: UInt16
    }

    private static func decodeSamples(_ body: [UInt8], format: Format) throws -> AudioClip {
        var values: [Float] = []
        switch (format.tag, format.bits) {
        case (1, 16), (0xFFFE, 16):
            values.reserveCapacity(body.count / 2)
            for index in 0..<(body.count / 2) {
                let raw = Int16(bitPattern: body.readLE(UInt16.self, at: index * 2))
                values.append(Float(raw) / Float(Int16.max))
            }
        case (3, 32):
            values.reserveCapacity(body.count / 4)
            for index in 0..<(body.count / 4) {
                values.append(Float(bitPattern: body.readLE(UInt32.self, at: index * 4)))
            }
        default:
            throw WAVError.unsupportedFormat("format tag \(format.tag), \(format.bits) bit")
        }
        return AudioClip(samples: downmix(values, channels: format.channels), sampleRate: format.sampleRate)
    }

    private static func downmix(_ interleaved: [Float], channels: Int) -> [Float] {
        guard channels > 1 else { return interleaved }
        return stride(from: 0, to: interleaved.count - channels + 1, by: channels).map { start in
            interleaved[start..<start + channels].reduce(0, +) / Float(channels)
        }
    }
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

extension Array where Element == UInt8 {
    func readLE<T: FixedWidthInteger>(_: T.Type, at index: Int) -> T {
        var value: T = 0
        for byte in 0..<MemoryLayout<T>.size {
            value |= T(self[index + byte]) << (8 * byte)
        }
        return value
    }
}
