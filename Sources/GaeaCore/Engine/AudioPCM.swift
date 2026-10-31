import AVFoundation
import Foundation
import MESCore

/// Gaea's audio conversions (AB-T-0392): a worker makes samples at its model's own rate and channels, and Gaea gives the
/// client the format it asked for (Audio §1.2's `output`, Base §7.2's stream plan), warning when it changed one. Samples
/// that need no change are passed through untouched, so a plugin's own WAV reaches the client byte for byte.
enum AudioPCM {
    /// Floats in [-1, 1] as 16-bit integers the way the fleet's TTS packages write their WAVs (`Int16(x * 32767)`, toward
    /// zero), so a streamed output's file equals the package's own WAV.
    static func int16(_ x: Float) -> Int16 { Int16(max(-1, min(1, x)) * 32767) }

    /// Interleaved floats as one stream encoding's bytes.
    static func encode(_ samples: [Float], _ encoding: StreamEncoding) -> Data {
        switch encoding {
        case .pcmF32LE:
            return samples.withUnsafeBufferPointer { Data(buffer: $0) }
        case .pcmS16LE:
            let ints = samples.map(int16)
            return ints.withUnsafeBufferPointer { Data(buffer: $0) }
        }
    }

    /// A WAV of interleaved floats: 16- or 24-bit integer, or 32-bit float.
    static func wav(_ samples: [Float], sampleRate: Int, channels: Int, bitDepth: Int) -> Data {
        var pcm = Data(capacity: samples.count * bitDepth / 8)
        switch bitDepth {
        case 24:
            for x in samples {
                let v = Int32(Double(max(-1, min(1, x))) * 8_388_607)
                pcm.append(contentsOf: [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v >> 16)])
            }
            return WAVFile(sampleRate: sampleRate, channels: channels, bitsPerSample: 24, pcm: pcm).data
        case 32:
            return WAVFile(sampleRate: sampleRate, channels: channels, bitsPerSample: 32, format: .float,
                           pcm: encode(samples, .pcmF32LE)).data
        default:
            return WAVFile(sampleRate: sampleRate, channels: channels, bitsPerSample: 16, pcm: encode(samples, .pcmS16LE)).data
        }
    }

    /// Interleaved samples from `from` channels to `to`: mono is duplicated, stereo averaged.
    static func remix(_ samples: [Float], from: Int, to: Int) -> [Float] {
        guard from != to else { return samples }
        if from == 1 { return samples.flatMap { Array(repeating: $0, count: to) } }
        return stride(from: 0, to: samples.count - (from - 1), by: from).map { i in
            samples[i..<(i + from)].reduce(0, +) / Float(from)
        }
    }
}

/// One output's samples on their way to the client: remixed, resampled with `AVAudioConverter` (its state kept across
/// chunks, so a stream resamples as one signal), and encoded.
final class AudioConversion: @unchecked Sendable {
    let fromRate: Int, fromChannels: Int, toRate: Int, toChannels: Int
    private let converter: AVAudioConverter?
    private let inFormat: AVAudioFormat?
    private let outFormat: AVAudioFormat?

    init(fromRate: Int, fromChannels: Int, toRate: Int, toChannels: Int) {
        self.fromRate = fromRate; self.fromChannels = fromChannels; self.toRate = toRate; self.toChannels = toChannels
        if fromRate != toRate,
           let i = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(fromRate), channels: AVAudioChannelCount(toChannels), interleaved: false),
           let o = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(toRate), channels: AVAudioChannelCount(toChannels), interleaved: false) {
            inFormat = i; outFormat = o
            converter = AVAudioConverter(from: i, to: o)
            converter?.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        } else {
            inFormat = nil; outFormat = nil; converter = nil
        }
    }

    var resamples: Bool { fromRate != toRate }
    var remixes: Bool { fromChannels != toChannels }

    /// The next piece of the signal, converted; `final` flushes what the resampler holds.
    func convert(_ samples: [Float], final: Bool) -> [Float] {
        let mixed = AudioPCM.remix(samples, from: fromChannels, to: toChannels)
        guard let converter, let inFormat, let outFormat else { return mixed }
        let frames = mixed.count / toChannels
        var supplied = false
        let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(max(1, frames)))!
        input.frameLength = AVAudioFrameCount(frames)
        for c in 0..<toChannels {
            let channel = input.floatChannelData![c]
            for f in 0..<frames { channel[f] = mixed[f * toChannels + c] }
        }
        var out: [Float] = []
        let capacity = AVAudioFrameCount(Double(frames) * Double(toRate) / Double(fromRate)) + 4096
        while true {
            let output = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity)!
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, outStatus in
                if !supplied && frames > 0 {
                    supplied = true
                    outStatus.pointee = .haveData
                    return input
                }
                outStatus.pointee = final ? .endOfStream : .noDataNow
                return nil
            }
            let n = Int(output.frameLength)
            for f in 0..<n { for c in 0..<toChannels { out.append(output.floatChannelData![c][f]) } }
            if status == .error || status == .endOfStream || status == .inputRanDry || n == 0 { break }
        }
        return out
    }
}
