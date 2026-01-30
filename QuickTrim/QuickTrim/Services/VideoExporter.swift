//
//  VideoExporter.swift
//  QuickTrim
//
//  Handles lossless video export using AVFoundation
//

import Foundation
import AVFoundation

enum ExportError: LocalizedError {
    case noVideoURL
    case noRegionsToExport
    case exportFailed(String)
    case assetLoadFailed
    case compositionFailed

    var errorDescription: String? {
        switch self {
        case .noVideoURL:
            return "No video file loaded"
        case .noRegionsToExport:
            return "No regions selected for export"
        case .exportFailed(let message):
            return "Export failed: \(message)"
        case .assetLoadFailed:
            return "Failed to load video asset"
        case .compositionFailed:
            return "Failed to create video composition"
        }
    }
}

class VideoExporter {

    static func export(
        sourceURL: URL,
        regions: [Region],
        outputURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard !regions.isEmpty else {
            throw ExportError.noRegionsToExport
        }

        // Sort regions by start time
        let sortedRegions = regions.sorted { $0.startTime < $1.startTime }

        // Remove existing file if it exists (user chose to overwrite via save panel)
        try? FileManager.default.removeItem(at: outputURL)

        // Load source asset
        let sourceAsset = AVURLAsset(url: sourceURL)

        // Try to use AVAssetExportSession with passthrough for near-lossless export
        let success = try await exportWithComposition(
            sourceAsset: sourceAsset,
            regions: sortedRegions,
            outputURL: outputURL,
            progressHandler: progressHandler
        )

        if success {
            return outputURL
        } else {
            throw ExportError.exportFailed("Export session failed")
        }
    }

    private static func exportWithComposition(
        sourceAsset: AVURLAsset,
        regions: [Region],
        outputURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> Bool {

        // Create composition
        let composition = AVMutableComposition()

        // Get tracks from source
        let videoTracks = try await sourceAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)

        let isAudioOnly = videoTracks.isEmpty && !audioTracks.isEmpty

        // Require at least one track type
        guard !videoTracks.isEmpty || !audioTracks.isEmpty else {
            throw ExportError.assetLoadFailed
        }

        // Add composition tracks
        var compositionVideoTrack: AVMutableCompositionTrack?
        var compositionAudioTrack: AVMutableCompositionTrack?

        if let sourceVideoTrack = videoTracks.first {
            compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        }

        if audioTracks.first != nil {
            compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        }

        // Insert time ranges from each region
        var currentTime = CMTime.zero

        for region in regions {
            let startTime = CMTime(seconds: region.startTime, preferredTimescale: 600)
            let endTime = CMTime(seconds: region.endTime, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startTime, end: endTime)

            do {
                // Insert video if available
                if let sourceVideoTrack = videoTracks.first,
                   let videoTrack = compositionVideoTrack {
                    try videoTrack.insertTimeRange(
                        timeRange,
                        of: sourceVideoTrack,
                        at: currentTime
                    )
                }

                // Insert audio if available
                if let sourceAudioTrack = audioTracks.first,
                   let audioTrack = compositionAudioTrack {
                    try audioTrack.insertTimeRange(
                        timeRange,
                        of: sourceAudioTrack,
                        at: currentTime
                    )
                }

                currentTime = CMTimeAdd(currentTime, CMTimeSubtract(endTime, startTime))
            } catch {
                print("Failed to insert time range: \(error)")
                throw ExportError.compositionFailed
            }
        }

        // Preserve video orientation if video exists
        if let sourceVideoTrack = videoTracks.first,
           let videoTrack = compositionVideoTrack {
            let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
            videoTrack.preferredTransform = preferredTransform
        }

        // Determine output file type based on source and media type
        let sourceExtension = sourceAsset.url.pathExtension.lowercased()
        let outputFileType: AVFileType

        if isAudioOnly {
            // Audio-only output types
            switch sourceExtension {
            case "mp3":
                // MP3 can't be written directly, use M4A
                outputFileType = .m4a
            case "aiff", "aif":
                outputFileType = .aiff
            case "wav", "wave":
                outputFileType = .wav
            case "m4a":
                outputFileType = .m4a
            default:
                outputFileType = .m4a  // Default audio format
            }
        } else {
            // Video output types
            switch sourceExtension {
            case "mov":
                outputFileType = .mov
            case "m4v":
                outputFileType = .m4v
            default:
                outputFileType = .mp4
            }
        }

        // Create export session - try passthrough first
        if let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) {
            exportSession.outputURL = outputURL
            exportSession.outputFileType = outputFileType
            exportSession.shouldOptimizeForNetworkUse = false

            // Monitor progress in background
            let progressTask = Task.detached {
                while !Task.isCancelled {
                    let progress = exportSession.progress
                    await MainActor.run {
                        progressHandler(Double(progress))
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
            }

            // Export
            await exportSession.export()

            // Stop progress monitoring
            progressTask.cancel()

            switch exportSession.status {
            case .completed:
                await MainActor.run { progressHandler(1.0) }
                return true
            case .failed:
                // If passthrough failed, try high quality encoding
                try? FileManager.default.removeItem(at: outputURL)
                return try await exportWithHighQuality(
                    composition: composition,
                    outputURL: outputURL,
                    outputFileType: outputFileType,
                    progressHandler: progressHandler
                )
            case .cancelled:
                throw ExportError.exportFailed("Export was cancelled")
            default:
                throw ExportError.exportFailed("Unexpected export status: \(exportSession.status.rawValue)")
            }
        } else {
            // Fall back to high quality preset
            return try await exportWithHighQuality(
                composition: composition,
                outputURL: outputURL,
                outputFileType: outputFileType,
                progressHandler: progressHandler
            )
        }
    }

    private static func exportWithHighQuality(
        composition: AVComposition,
        outputURL: URL,
        outputFileType: AVFileType,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> Bool {

        // Remove existing file if any (from failed passthrough attempt)
        try? FileManager.default.removeItem(at: outputURL)

        // Determine preset based on whether this is audio-only
        let isAudioOnly = [.m4a, .aiff, .wav, .mp3].contains(outputFileType)
        let presetName = isAudioOnly ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: presetName
        ) else {
            throw ExportError.exportFailed("Could not create export session")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType
        exportSession.shouldOptimizeForNetworkUse = false

        // Monitor progress in background
        let progressTask = Task.detached {
            while !Task.isCancelled {
                let progress = exportSession.progress
                await MainActor.run {
                    progressHandler(Double(progress))
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }

        // Export
        await exportSession.export()

        // Stop progress monitoring
        progressTask.cancel()

        switch exportSession.status {
        case .completed:
            await MainActor.run { progressHandler(1.0) }
            return true
        case .failed:
            if let error = exportSession.error {
                throw ExportError.exportFailed(error.localizedDescription)
            }
            throw ExportError.exportFailed("Unknown error")
        case .cancelled:
            throw ExportError.exportFailed("Export was cancelled")
        default:
            throw ExportError.exportFailed("Unexpected export status: \(exportSession.status.rawValue)")
        }
    }

}
