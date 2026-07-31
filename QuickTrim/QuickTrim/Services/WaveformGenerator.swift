//
//  WaveformGenerator.swift
//  QuickTrim
//
//  Decodes a file's audio once into a high-resolution peak cache
//  (per-bucket min/max + RMS), from which any zoom level can be
//  rendered without touching the file again.
//

import Foundation
import AVFoundation

/// High-resolution waveform peak cache.
///
/// Each bucket summarises a fixed slice of time (a few milliseconds) with the
/// minimum sample, maximum sample, and RMS level in that slice. Rendering at
/// any width/zoom aggregates or interpolates these buckets — the audio file
/// is only ever decoded once.
struct WaveformData {
    let minSamples: [Float]   // per-bucket minimum, -1.0...0.0
    let maxSamples: [Float]   // per-bucket maximum, 0.0...1.0
    let rmsSamples: [Float]   // per-bucket RMS, 0.0...1.0
    let duration: Double
    let peakLevel: Float      // loudest |sample| in the whole file, 0.0...1.0

    var bucketCount: Int { maxSamples.count }

    var bucketsPerSecond: Double {
        duration > 0 ? Double(bucketCount) / duration : 0
    }

    /// Gain that scales the file's loudest peak up to `targetFill` of the
    /// available half-height (peak normalization, like Logic). Never shrinks
    /// full-scale audio, and caps the boost so near-silent files don't
    /// explode into noise.
    func normalizationGain(targetFill: Float, maxBoost: Float = 10) -> CGFloat {
        guard peakLevel > 0 else { return 1 }
        return CGFloat(min(max(targetFill / peakLevel, 1), maxBoost))
    }

    static let empty = WaveformData(minSamples: [], maxSamples: [], rmsSamples: [], duration: 0, peakLevel: 0)

    /// Silent waveform of a given duration (fallback when decoding fails).
    static func silence(duration: Double) -> WaveformData {
        let count = 100
        return WaveformData(
            minSamples: Array(repeating: 0, count: count),
            maxSamples: Array(repeating: 0, count: count),
            rmsSamples: Array(repeating: 0, count: count),
            duration: duration,
            peakLevel: 0
        )
    }
}

enum WaveformError: LocalizedError {
    case noAudioTrack
    case readingFailed

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "No audio track found"
        case .readingFailed:
            return "Failed to read audio data"
        }
    }
}

/// Process-wide cache so the timeline, preview strip, and player view all
/// share a single decode per file, and zoom/resize never re-reads the file.
actor WaveformCache {
    static let shared = WaveformCache()

    private var tasks: [URL: Task<WaveformData, Error>] = [:]
    private var order: [URL] = []
    private let maxEntries = 4

    func waveform(for url: URL) async throws -> WaveformData {
        if let existing = tasks[url] {
            return try await existing.value
        }

        let task = Task {
            try await WaveformGenerator.decode(url: url)
        }
        tasks[url] = task
        order.append(url)

        // Evict oldest entries beyond the cap
        while order.count > maxEntries {
            let evicted = order.removeFirst()
            tasks[evicted]?.cancel()
            tasks[evicted] = nil
        }

        do {
            return try await task.value
        } catch {
            // Don't cache failures
            tasks[url] = nil
            order.removeAll { $0 == url }
            throw error
        }
    }
}

enum WaveformGenerator {

    /// Peak-cache resolution: one bucket per 5ms of audio, bounded so very
    /// short files still get detail and very long files stay in memory budget.
    private static func bucketCount(for duration: Double) -> Int {
        let target = Int(duration * 200)
        return min(max(target, 2_000), 1_500_000)
    }

    /// Decode the file's audio track into a WaveformData peak cache.
    /// Reads every sample (no skipping), mixes channels to mono, and uses the
    /// stream's real sample rate and channel count.
    static func decode(url: URL) async throws -> WaveformData {
        let asset = AVURLAsset(url: url)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw WaveformError.noAudioTrack
        }

        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        guard duration > 0 else { return .empty }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else {
            throw WaveformError.readingFailed
        }

        // Real stream format (sample rate / channels) from the first buffer
        var sampleRate: Double = 0
        var channelCount = 1

        let totalBuckets = bucketCount(for: duration)

        var minSamples = [Float](repeating: 0, count: totalBuckets)
        var maxSamples = [Float](repeating: 0, count: totalBuckets)
        var rmsSamples = [Float](repeating: 0, count: totalBuckets)

        var framesPerBucket = 0
        var bucketIndex = 0
        var bucketMin: Float = 0
        var bucketMax: Float = 0
        var bucketSumSquares: Double = 0
        var framesInBucket = 0

        func flushBucket() {
            guard bucketIndex < totalBuckets, framesInBucket > 0 else { return }
            minSamples[bucketIndex] = bucketMin
            maxSamples[bucketIndex] = bucketMax
            rmsSamples[bucketIndex] = Float(sqrt(bucketSumSquares / Double(framesInBucket)))
            bucketIndex += 1
            bucketMin = 0
            bucketMax = 0
            bucketSumSquares = 0
            framesInBucket = 0
        }

        while let sampleBuffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                throw CancellationError()
            }

            if sampleRate == 0,
               let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee {
                sampleRate = asbd.mSampleRate
                channelCount = max(1, Int(asbd.mChannelsPerFrame))
                let totalFrames = duration * sampleRate
                framesPerBucket = max(1, Int(totalFrames / Double(totalBuckets)))
            }

            guard framesPerBucket > 0,
                  let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPointer
            )
            guard status == kCMBlockBufferNoErr, let dataPointer else { continue }

            let floatCount = length / MemoryLayout<Float>.size
            let frameCount = floatCount / channelCount

            dataPointer.withMemoryRebound(to: Float.self, capacity: floatCount) { floats in
                for frame in 0..<frameCount {
                    // Mix interleaved channels to mono
                    var mono: Float = 0
                    let base = frame * channelCount
                    for channel in 0..<channelCount {
                        mono += floats[base + channel]
                    }
                    mono /= Float(channelCount)

                    if mono < bucketMin { bucketMin = mono }
                    if mono > bucketMax { bucketMax = mono }
                    bucketSumSquares += Double(mono * mono)
                    framesInBucket += 1

                    if framesInBucket >= framesPerBucket {
                        flushBucket()
                    }
                }
            }
        }

        flushBucket()
        reader.cancelReading()

        guard bucketIndex > 0 else {
            throw WaveformError.readingFailed
        }

        // Trim unfilled tail (decoder can deliver slightly less than duration)
        if bucketIndex < totalBuckets {
            minSamples.removeLast(totalBuckets - bucketIndex)
            maxSamples.removeLast(totalBuckets - bucketIndex)
            rmsSamples.removeLast(totalBuckets - bucketIndex)
        }

        let maxPeak = maxSamples.max() ?? 0
        let minPeak = minSamples.min() ?? 0
        let peakLevel = max(maxPeak, abs(minPeak))

        return WaveformData(
            minSamples: minSamples,
            maxSamples: maxSamples,
            rmsSamples: rmsSamples,
            duration: duration,
            peakLevel: peakLevel
        )
    }
}
