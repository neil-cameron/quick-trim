//
//  WaveformGenerator.swift
//  QuickTrim
//

import Foundation
import AVFoundation

struct WaveformData {
    let samples: [Float]  // Normalized -1.0 to 1.0
    let duration: Double
}

enum WaveformError: LocalizedError {
    case noAudioTrack
    case readingFailed
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "No audio track found"
        case .readingFailed:
            return "Failed to read audio data"
        case .invalidFormat:
            return "Invalid audio format"
        }
    }
}

class WaveformGenerator {

    /// Fast rough waveform generation using streaming with skip
    /// Reads file sequentially but only processes a fraction of the audio data
    /// - Parameters:
    ///   - url: Source file URL
    ///   - totalSamples: Total number of output samples to generate
    /// - Returns: WaveformData containing normalized samples
    static func generateRoughWaveform(
        from url: URL,
        totalSamples: Int = 200
    ) async throws -> WaveformData {
        let asset = AVURLAsset(url: url)

        // Load audio track
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw WaveformError.noAudioTrack
        }

        // Get duration
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds > 0 else {
            return WaveformData(samples: [], duration: 0)
        }

        // Create asset reader
        let reader = try AVAssetReader(asset: asset)

        // Configure output settings for PCM
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: outputSettings
        )
        reader.add(output)

        guard reader.startReading() else {
            throw WaveformError.readingFailed
        }

        // Estimate total samples based on typical 44.1kHz stereo
        let estimatedSampleRate = 44100
        let estimatedTotalSamples = Int(durationSeconds * Double(estimatedSampleRate) * 2) // stereo

        // Calculate how many raw samples per output bucket
        let samplesPerBucket = max(1, estimatedTotalSamples / totalSamples)

        // We'll skip most buffers and only process every Nth sample
        var waveformSamples: [Float] = []
        waveformSamples.reserveCapacity(totalSamples)

        var totalSamplesRead = 0
        var currentBucketMax: Int16 = 0
        var samplesInCurrentBucket = 0
        let skipFactor = max(1, samplesPerBucket / 100) // Only check every Nth sample for peak

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
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

            guard status == kCMBlockBufferNoErr, let dataPointer = dataPointer else {
                continue
            }

            let sampleCount = length / MemoryLayout<Int16>.size
            dataPointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { pointer in
                // Process samples with skip factor for speed
                var j = 0
                while j < sampleCount {
                    let absSample = abs(pointer[j])
                    if absSample > currentBucketMax {
                        currentBucketMax = absSample
                    }

                    samplesInCurrentBucket += skipFactor
                    totalSamplesRead += skipFactor

                    // Check if we've filled a bucket
                    if samplesInCurrentBucket >= samplesPerBucket {
                        let normalized = Float(currentBucketMax) / Float(Int16.max)
                        waveformSamples.append(normalized)
                        currentBucketMax = 0
                        samplesInCurrentBucket = 0

                        // Stop if we have enough samples
                        if waveformSamples.count >= totalSamples {
                            break
                        }
                    }

                    j += skipFactor
                }
            }

            // Stop early if we have enough samples
            if waveformSamples.count >= totalSamples {
                break
            }
        }

        // Add final bucket if there's remaining data
        if samplesInCurrentBucket > 0 && waveformSamples.count < totalSamples {
            let normalized = Float(currentBucketMax) / Float(Int16.max)
            waveformSamples.append(normalized)
        }

        reader.cancelReading()

        // Pad or trim to exact count
        while waveformSamples.count < totalSamples {
            waveformSamples.append(waveformSamples.last ?? 0)
        }
        if waveformSamples.count > totalSamples {
            waveformSamples = Array(waveformSamples.prefix(totalSamples))
        }

        return WaveformData(
            samples: waveformSamples,
            duration: durationSeconds
        )
    }

    /// Generate waveform samples from an audio/video file
    /// - Parameters:
    ///   - url: Source file URL
    ///   - samplesPerSecond: How many samples to extract per second of audio
    /// - Returns: WaveformData containing normalized samples
    static func generateWaveform(
        from url: URL,
        samplesPerSecond: Int = 100
    ) async throws -> WaveformData {
        let asset = AVURLAsset(url: url)

        // Load audio track
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw WaveformError.noAudioTrack
        }

        // Get duration
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        // Create asset reader
        let reader = try AVAssetReader(asset: asset)

        // Configure output settings for PCM
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: outputSettings
        )
        reader.add(output)

        guard reader.startReading() else {
            throw WaveformError.readingFailed
        }

        // Calculate total samples needed
        let totalSamples = max(1, Int(durationSeconds * Double(samplesPerSecond)))

        // Read and process audio buffers
        var allSamples: [Int16] = []
        allSamples.reserveCapacity(Int(durationSeconds * 44100))  // Estimate based on common sample rate

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
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

            guard status == kCMBlockBufferNoErr, let dataPointer = dataPointer else {
                continue
            }

            let sampleCount = length / MemoryLayout<Int16>.size
            dataPointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { pointer in
                let buffer = UnsafeBufferPointer(start: pointer, count: sampleCount)
                allSamples.append(contentsOf: buffer)
            }
        }

        guard !allSamples.isEmpty else {
            throw WaveformError.readingFailed
        }

        // Downsample to target resolution
        var waveformSamples: [Float] = []
        waveformSamples.reserveCapacity(totalSamples)

        let samplesPerBucket = max(1, allSamples.count / totalSamples)

        for i in 0..<totalSamples {
            let startIndex = i * samplesPerBucket
            let endIndex = min(startIndex + samplesPerBucket, allSamples.count)

            guard startIndex < allSamples.count else {
                waveformSamples.append(0)
                continue
            }

            // Find max absolute value in bucket (peak detection)
            var maxAbsSample: Int16 = 0
            for j in startIndex..<endIndex {
                let absSample = abs(allSamples[j])
                if absSample > maxAbsSample {
                    maxAbsSample = absSample
                }
            }

            // Normalize to -1.0 to 1.0
            let normalized = Float(maxAbsSample) / Float(Int16.max)
            waveformSamples.append(normalized)
        }

        return WaveformData(
            samples: waveformSamples,
            duration: durationSeconds
        )
    }

    /// Generate waveform for specific time ranges (for preview mode)
    /// - Parameters:
    ///   - url: Source file URL
    ///   - regions: Array of regions to extract
    ///   - samplesPerSecond: How many samples to extract per second
    /// - Returns: WaveformData containing concatenated samples from kept regions
    static func generateWaveform(
        from url: URL,
        forRegions regions: [Region],
        samplesPerSecond: Int = 100
    ) async throws -> WaveformData {
        // Generate full waveform first
        let fullData = try await generateWaveform(from: url, samplesPerSecond: samplesPerSecond)

        guard !regions.isEmpty else {
            return fullData
        }

        // Extract samples for specified regions only
        var previewSamples: [Float] = []
        let samplesPerSecondActual = Double(fullData.samples.count) / fullData.duration

        var totalDuration: Double = 0

        for region in regions {
            let startIndex = Int(region.startTime * samplesPerSecondActual)
            let endIndex = Int(region.endTime * samplesPerSecondActual)
            let clampedStart = max(0, min(startIndex, fullData.samples.count - 1))
            let clampedEnd = max(0, min(endIndex, fullData.samples.count))

            if clampedStart < clampedEnd {
                previewSamples.append(contentsOf: fullData.samples[clampedStart..<clampedEnd])
            }

            totalDuration += region.duration
        }

        return WaveformData(
            samples: previewSamples,
            duration: totalDuration
        )
    }
}
