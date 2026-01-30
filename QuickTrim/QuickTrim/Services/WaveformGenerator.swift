//
//  WaveformGenerator.swift
//  QuickTrim
//

import Foundation
import AVFoundation
import Accelerate

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
