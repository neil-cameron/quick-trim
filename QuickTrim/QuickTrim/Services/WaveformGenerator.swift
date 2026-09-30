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
    /// Identity for cheap change detection (comparing the sample arrays
    /// would cost as much as the redraw it's meant to avoid).
    let id = UUID()
    let minSamples: [Float]   // per-bucket minimum, -1.0...0.0
    let maxSamples: [Float]   // per-bucket maximum, 0.0...1.0
    let rmsSamples: [Float]   // per-bucket RMS, 0.0...1.0
    let duration: Double
    let peakLevel: Float      // loudest |sample| in the whole file, 0.0...1.0
    /// Exact bucket rate from the decoded stream (bucket i starts at
    /// i / bucketsPerSecond seconds). Stored rather than derived from
    /// bucketCount/duration, which drifts when the container's duration
    /// and the decoded sample count disagree slightly.
    let bucketsPerSecond: Double

    var bucketCount: Int { maxSamples.count }

    /// Gain that scales the file's loudest peak up to `targetFill` of the
    /// available half-height (peak normalization, like Logic). Never shrinks
    /// full-scale audio, and caps the boost so near-silent files don't
    /// explode into noise.
    func normalizationGain(targetFill: Float, maxBoost: Float = 10) -> CGFloat {
        guard peakLevel > 0 else { return 1 }
        return CGFloat(min(max(targetFill / peakLevel, 1), maxBoost))
    }

    static let empty = WaveformData(minSamples: [], maxSamples: [], rmsSamples: [], duration: 0, peakLevel: 0, bucketsPerSecond: 0)

    /// Silent waveform of a given duration (fallback when decoding fails).
    static func silence(duration: Double) -> WaveformData {
        let count = 100
        return WaveformData(
            minSamples: Array(repeating: 0, count: count),
            maxSamples: Array(repeating: 0, count: count),
            rmsSamples: Array(repeating: 0, count: count),
            duration: duration,
            peakLevel: 0,
            bucketsPerSecond: duration > 0 ? Double(count) / duration : 0
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

        let targetBucketsPerSecond = Double(bucketCount(for: duration)) / duration
        let estimatedBuckets = bucketCount(for: duration) + 16

        var minSamples: [Float] = []
        var maxSamples: [Float] = []
        var rmsSamples: [Float] = []
        minSamples.reserveCapacity(estimatedBuckets)
        maxSamples.reserveCapacity(estimatedBuckets)
        rmsSamples.reserveCapacity(estimatedBuckets)

        // Fractional frames per bucket (e.g. 220.5 at 44.1kHz). Bucket
        // boundaries are placed at exact multiples of this, so bucket i
        // always starts at i / bucketsPerSecond seconds — rounding it to an
        // integer made the waveform drift ~7s per hour on 44.1kHz audio.
        var framesPerBucket: Double = 0
        var frameIndex = 0
        var nextBoundary: Double = 0
        var bucketMin: Float = 0
        var bucketMax: Float = 0
        var bucketSumSquares: Double = 0
        var framesInBucket = 0

        func flushBucket() {
            guard framesInBucket > 0 else { return }
            minSamples.append(bucketMin)
            maxSamples.append(bucketMax)
            rmsSamples.append(Float(sqrt(bucketSumSquares / Double(framesInBucket))))
            bucketMin = 0
            bucketMax = 0
            bucketSumSquares = 0
            framesInBucket = 0
        }

        // Scratch buffer for the (rare) non-contiguous block buffer case
        var copyBuffer: [Float] = []

        while let sampleBuffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                throw CancellationError()
            }

            if sampleRate == 0,
               let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee,
               asbd.mSampleRate > 0 {
                sampleRate = asbd.mSampleRate
                channelCount = max(1, Int(asbd.mChannelsPerFrame))
                framesPerBucket = max(1, sampleRate / targetBucketsPerSecond)
                nextBoundary = framesPerBucket
            }

            guard framesPerBucket > 0,
                  let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }

            let processFloats: (UnsafePointer<Float>, Int) -> Void = { floats, floatCount in
                let frameCount = floatCount / channelCount
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
                    frameIndex += 1

                    if Double(frameIndex) >= nextBoundary {
                        flushBucket()
                        nextBoundary += framesPerBucket
                    }
                }
            }

            var lengthAtOffset = 0
            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: &lengthAtOffset,
                totalLengthOut: &totalLength,
                dataPointerOut: &dataPointer
            )
            guard status == kCMBlockBufferNoErr else { continue }

            let floatCount = totalLength / MemoryLayout<Float>.size

            if let dataPointer, lengthAtOffset == totalLength {
                // Contiguous (the normal case): read in place
                dataPointer.withMemoryRebound(to: Float.self, capacity: floatCount) { floats in
                    processFloats(floats, floatCount)
                }
            } else {
                // Non-contiguous: the pointer only covers the first segment,
                // so copy the whole buffer out rather than read past it.
                if copyBuffer.count < floatCount {
                    copyBuffer = [Float](repeating: 0, count: floatCount)
                }
                let copyStatus = copyBuffer.withUnsafeMutableBytes { raw in
                    CMBlockBufferCopyDataBytes(
                        blockBuffer,
                        atOffset: 0,
                        dataLength: floatCount * MemoryLayout<Float>.size,
                        destination: raw.baseAddress!
                    )
                }
                guard copyStatus == kCMBlockBufferNoErr else { continue }
                copyBuffer.withUnsafeBufferPointer { floats in
                    processFloats(floats.baseAddress!, floatCount)
                }
            }
        }

        flushBucket()
        reader.cancelReading()

        guard !maxSamples.isEmpty, framesPerBucket > 0 else {
            throw WaveformError.readingFailed
        }

        let maxPeak = maxSamples.max() ?? 0
        let minPeak = minSamples.min() ?? 0
        let peakLevel = max(maxPeak, abs(minPeak))

        return WaveformData(
            minSamples: minSamples,
            maxSamples: maxSamples,
            rmsSamples: rmsSamples,
            duration: duration,
            peakLevel: peakLevel,
            bucketsPerSecond: sampleRate / framesPerBucket
        )
    }
}
