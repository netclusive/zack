import Foundation
import Testing

@testable import ZackCore

@Test func encodeWritesRiffHeader() {
    let data = WAVFile.encode(AudioClip(samples: [0, 0.5, -0.5]))
    #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
    #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
    #expect(data.count == 44 + 3 * 2)
}

@Test func roundTripKeepsSamplesAndRate() throws {
    let original = AudioClip(samples: [0, 0.25, -0.25, 1, -1], sampleRate: 16_000)
    let decoded = try WAVFile.decode(WAVFile.encode(original))
    #expect(decoded.sampleRate == 16_000)
    #expect(decoded.samples.count == original.samples.count)
    for (a, b) in zip(decoded.samples, original.samples) {
        #expect(abs(a - b) < 0.0001)
    }
}

@Test func decodeRejectsNonRiffData() {
    #expect(throws: WAVError.notRIFF) {
        try WAVFile.decode(Data("hello world!".utf8))
    }
}

@Test func decodeDownmixesStereo() throws {
    var data = Data()
    data.append(contentsOf: Array("RIFF".utf8))
    data.appendLE(UInt32(36 + 8))
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    data.appendLE(UInt32(16))
    data.appendLE(UInt16(1))
    data.appendLE(UInt16(2))
    data.appendLE(UInt32(16_000))
    data.appendLE(UInt32(16_000 * 4))
    data.appendLE(UInt16(4))
    data.appendLE(UInt16(16))
    data.append(contentsOf: Array("data".utf8))
    data.appendLE(UInt32(8))
    data.appendLE(Int16(16_384))
    data.appendLE(Int16(0))
    data.appendLE(Int16(-16_384))
    data.appendLE(Int16(-16_384))
    let clip = try WAVFile.decode(data)
    #expect(clip.samples.count == 2)
    #expect(abs(clip.samples[0] - 0.25) < 0.001)
    #expect(abs(clip.samples[1] + 0.5) < 0.001)
}

private func riffHeader(body: Data) -> Data {
    var data = Data()
    data.append(contentsOf: Array("RIFF".utf8))
    data.appendLE(UInt32(4 + body.count))
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(body)
    return data
}

private func chunk(_ id: String, _ payload: Data) -> Data {
    var data = Data()
    data.append(contentsOf: Array(id.utf8))
    data.appendLE(UInt32(payload.count))
    data.append(payload)
    return data
}

private func fmtPayload(tag: UInt16, channels: UInt16, sampleRate: UInt32, bits: UInt16) -> Data {
    var data = Data()
    data.appendLE(tag)
    data.appendLE(channels)
    data.appendLE(sampleRate)
    data.appendLE(sampleRate * UInt32(channels) * UInt32(bits / 8))
    data.appendLE(channels * (bits / 8))
    data.appendLE(bits)
    return data
}

@Test func decodeRejectsShortFmtChunkAtEnd() {
    let data = riffHeader(body: chunk("fmt ", Data([0x01, 0x00])))
    #expect(throws: WAVError.truncated) {
        try WAVFile.decode(data)
    }
}

@Test func decodeRejectsShortFmtChunkBeforeData() {
    var pcm = Data()
    pcm.appendLE(Int16(1_000))
    let body = chunk("fmt ", Data(count: 2)) + chunk("data", pcm)
    #expect(throws: WAVError.truncated) {
        try WAVFile.decode(riffHeader(body: body))
    }
}

@Test func decodeRejectsZeroSampleRate() {
    let fmt = fmtPayload(tag: 1, channels: 1, sampleRate: 0, bits: 16)
    let body = chunk("fmt ", fmt) + chunk("data", Data(count: 2))
    #expect(throws: WAVError.self) {
        try WAVFile.decode(riffHeader(body: body))
    }
}

@Test func decodeRejectsZeroChannels() {
    let fmt = fmtPayload(tag: 1, channels: 0, sampleRate: 16_000, bits: 16)
    let body = chunk("fmt ", fmt) + chunk("data", Data(count: 2))
    #expect(throws: WAVError.self) {
        try WAVFile.decode(riffHeader(body: body))
    }
}

@Test func decodeReadsFloat32Mono() throws {
    let values: [Float] = [0, 0.5, -0.25, 1]
    var pcm = Data()
    for value in values { pcm.appendLE(value.bitPattern) }
    let body = chunk("fmt ", fmtPayload(tag: 3, channels: 1, sampleRate: 16_000, bits: 32)) + chunk("data", pcm)
    let clip = try WAVFile.decode(riffHeader(body: body))
    #expect(clip.sampleRate == 16_000)
    #expect(clip.samples == values)
}

@Test func decodeSkipsOddSizedPaddedChunk() throws {
    var pcm = Data()
    pcm.appendLE(Int16(16_384))
    var list = chunk("LIST", Data([1, 2, 3]))
    list.append(0)  // pad byte
    let body = chunk("fmt ", fmtPayload(tag: 1, channels: 1, sampleRate: 16_000, bits: 16)) + list + chunk("data", pcm)
    let clip = try WAVFile.decode(riffHeader(body: body))
    #expect(clip.samples.count == 1)
    #expect(abs(clip.samples[0] - 0.5) < 0.001)
}

@Test func decodeRejectsDataChunkLargerThanInput() {
    var truncated = Data()
    truncated.append(contentsOf: Array("data".utf8))
    truncated.appendLE(UInt32(100))
    truncated.append(Data(count: 4))
    let body = chunk("fmt ", fmtPayload(tag: 1, channels: 1, sampleRate: 16_000, bits: 16)) + truncated
    #expect(throws: WAVError.truncated) {
        try WAVFile.decode(riffHeader(body: body))
    }
}

@Test func encodeClipsOutOfRangeSamples() throws {
    let decoded = try WAVFile.decode(WAVFile.encode(AudioClip(samples: [2.0, -2.0])))
    #expect(decoded.samples.count == 2)
    #expect(abs(decoded.samples[0] - 1.0) < 0.001)
    #expect(abs(decoded.samples[1] + 1.0) < 0.001)
}
