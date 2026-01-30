//
//  AppState.swift
//  QuickTrim
//

import SwiftUI
import AVFoundation
import Combine
import UniformTypeIdentifiers

class AppState: ObservableObject {
    // Media state
    @Published var videoURL: URL?
    @Published var player: AVPlayer?
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var frameRate: Double = 30
    @Published var isPlaying: Bool = false
    @Published var isAudioOnly: Bool = false

    // Regions
    @Published var regions: [Region] = []

    // Timeline
    @Published var timelineZoom: Double = 1.0
    @Published var skimmingEnabled: Bool = true  // Enabled by default
    @Published var previewModeEnabled: Bool = false

    // Preview mode computed properties
    var keptRegions: [Region] {
        regions.filter { !$0.isBinned }.sorted { $0.startTime < $1.startTime }
    }

    var previewDuration: Double {
        keptRegions.reduce(0) { $0 + $1.duration }
    }

    var previewCurrentTime: Double {
        convertToPreviewTime(currentTime)
    }

    // Convert source time to preview time (collapsed timeline position)
    func convertToPreviewTime(_ sourceTime: Double) -> Double {
        var previewTime: Double = 0

        for region in keptRegions {
            if sourceTime < region.startTime {
                // Before this region
                return previewTime
            } else if sourceTime >= region.startTime && sourceTime <= region.endTime {
                // Inside this region
                return previewTime + (sourceTime - region.startTime)
            } else {
                // After this region, accumulate its duration
                previewTime += region.duration
            }
        }

        return previewTime
    }

    // Convert preview time back to source time
    func convertFromPreviewTime(_ previewTime: Double) -> Double {
        var remainingTime = previewTime

        for region in keptRegions {
            if remainingTime <= region.duration {
                return region.startTime + remainingTime
            }
            remainingTime -= region.duration
        }

        // If we're past all regions, return end of last region
        return keptRegions.last?.endTime ?? 0
    }

    // UI state
    @Published var showCloseConfirmation: Bool = false
    @Published var isExporting: Bool = false
    @Published var exportProgress: Double = 0

    // Undo/Redo
    private var undoStack: [RegionState] = []
    private var redoStack: [RegionState] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasUnsavedChanges: Bool { !undoStack.isEmpty && videoURL != nil }

    /// True if user has created trim regions (more than the initial single region)
    var hasUserCreatedRegions: Bool {
        videoURL != nil && regions.count > 1
    }

    var canExport: Bool {
        guard videoURL != nil, !regions.isEmpty else { return false }
        // At least one region must NOT be binned
        return regions.contains { !$0.isBinned }
    }

    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var isAccessingSecurityScopedResource = false

    // Audio skimming
    private var skimStopTask: Task<Void, Never>?
    @Published var isSkimming: Bool = false

    init() {}

    func openVideo(url: URL) {
        // Clean up previous video
        cleanUp()

        // Start accessing security-scoped resource for sandboxed apps
        isAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()

        videoURL = url

        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)

        // Get duration and frame rate
        Task { @MainActor in
            do {
                let durationValue = try await asset.load(.duration)
                self.duration = CMTimeGetSeconds(durationValue)

                // Check for video and audio tracks
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)

                if let videoTrack = videoTracks.first {
                    // Has video track - treat as video file
                    self.isAudioOnly = false
                    let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
                    self.frameRate = Double(nominalFrameRate)
                } else if audioTracks.first != nil {
                    // No video track but has audio - audio-only file
                    self.isAudioOnly = true
                    self.frameRate = 30.0  // Use standard rate for UI timeline
                } else {
                    // No usable tracks
                    print("Error: No video or audio tracks found")
                    return
                }

                // Initialize with single region covering entire media
                self.regions = [Region(startTime: 0, endTime: self.duration)]
                self.undoStack = []
                self.redoStack = []

            } catch {
                print("Error loading media: \(error)")
            }
        }

        // Observe playback time
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let newTime = CMTimeGetSeconds(time)
            self.currentTime = newTime

            // In preview mode, skip binned regions during playback
            if self.previewModeEnabled && self.isPlaying {
                self.handlePreviewModePlayback(currentTime: newTime)
            }
        }

        // Observe playing state
        player?.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.isPlaying = status == .playing
            }
            .store(in: &cancellables)
    }

    func cleanUp() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil

        // Stop accessing security-scoped resource
        if isAccessingSecurityScopedResource, let url = videoURL {
            url.stopAccessingSecurityScopedResource()
            isAccessingSecurityScopedResource = false
        }

        videoURL = nil
        duration = 0
        currentTime = 0
        isAudioOnly = false
        regions = []
        undoStack = []
        redoStack = []
        cancellables.removeAll()
    }

    // MARK: - Region Management

    private func saveStateForUndo() {
        undoStack.append(RegionState(regions: regions))
        redoStack.removeAll()
    }

    func markTrim() {
        guard duration > 0 else { return }
        guard currentTime > 0 && currentTime < duration else { return }

        // Find the region containing the current time
        guard let regionIndex = regions.firstIndex(where: { $0.contains(time: currentTime) }) else { return }

        let region = regions[regionIndex]

        // Don't split if we're at the start or end of the region
        if abs(currentTime - region.startTime) < 0.01 || abs(currentTime - region.endTime) < 0.01 {
            return
        }

        saveStateForUndo()

        // Split the region at current time
        let leftRegion = Region(startTime: region.startTime, endTime: currentTime, isBinned: region.isBinned)
        let rightRegion = Region(startTime: currentTime, endTime: region.endTime, isBinned: region.isBinned)

        regions.remove(at: regionIndex)
        regions.insert(contentsOf: [leftRegion, rightRegion], at: regionIndex)
    }

    func toggleBin(for region: Region) {
        guard let index = regions.firstIndex(where: { $0.id == region.id }) else { return }

        saveStateForUndo()
        regions[index].isBinned.toggle()
    }

    func binRegionLeftOfPlayhead() {
        guard let index = regions.lastIndex(where: { $0.endTime <= currentTime + 0.01 }) else { return }

        saveStateForUndo()
        regions[index].isBinned = true
    }

    func binRegionRightOfPlayhead() {
        guard let index = regions.firstIndex(where: { $0.startTime >= currentTime - 0.01 }) else { return }

        saveStateForUndo()
        regions[index].isBinned = true
    }

    // MARK: - Undo/Redo

    func undo() {
        guard let previousState = undoStack.popLast() else { return }
        redoStack.append(RegionState(regions: regions))
        regions = previousState.regions
    }

    func redo() {
        guard let nextState = redoStack.popLast() else { return }
        undoStack.append(RegionState(regions: regions))
        regions = nextState.regions
    }

    // MARK: - Playback

    func togglePlayPause() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
    }

    func seek(to time: Double) {
        let cmTime = CMTime(seconds: max(0, min(time, duration)), preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Seek and briefly play audio for skimming feedback (FCP-style)
    func skimTo(time: Double) {
        seek(to: time)

        // Only do audio playback for audio-only files during skimming
        guard isAudioOnly && skimmingEnabled else { return }

        // Cancel any pending stop task
        skimStopTask?.cancel()

        // Start playing if not already
        if !isSkimming {
            isSkimming = true
            player?.play()
        }

        // Schedule stop after brief playback
        skimStopTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
            if !Task.isCancelled {
                player?.pause()
                isSkimming = false
            }
        }
    }

    /// Stop audio skimming
    func stopSkimming() {
        skimStopTask?.cancel()
        if isSkimming {
            player?.pause()
            isSkimming = false
        }
    }

    func stepFrame(forward: Bool) {
        player?.pause()
        let frameDuration = 1.0 / frameRate
        let newTime = forward ? currentTime + frameDuration : currentTime - frameDuration
        seek(to: newTime)
    }

    func stepFrames(_ count: Int) {
        player?.pause()
        let frameDuration = 1.0 / frameRate
        let newTime = currentTime + (Double(count) * frameDuration)
        seek(to: newTime)
    }

    func stepSeconds(_ seconds: Double) {
        player?.pause()
        seek(to: currentTime + seconds)
    }

    func seekToStart() {
        if previewModeEnabled {
            // In preview mode, seek to start of first kept region
            if let firstKept = keptRegions.first {
                seek(to: firstKept.startTime)
            }
        } else {
            seek(to: 0)
        }
    }

    // Handle preview mode playback - skip binned regions
    private func handlePreviewModePlayback(currentTime: Double) {
        // Only handle during actual playback (not when paused)
        guard isPlaying else { return }

        // Check if we're in a binned region
        let inBinnedRegion = regions.contains { region in
            region.isBinned && currentTime >= region.startTime && currentTime < region.endTime
        }

        if inBinnedRegion {
            // Find the next kept region after current time
            if let nextKept = keptRegions.first(where: { $0.startTime >= currentTime }) {
                // Jump to the start of the next kept region
                seek(to: nextKept.startTime)
            } else {
                // No more kept regions, stop playback
                player?.pause()
            }
            return
        }

        // Check if we've reached the end of the last kept region
        if let lastKept = keptRegions.last {
            if currentTime >= lastKept.endTime - 0.02 {
                player?.pause()
            }
        }
    }

    // MARK: - Timeline Zoom

    func zoomIn() {
        timelineZoom = min(timelineZoom * 1.5, 10.0)
    }

    func zoomOut() {
        timelineZoom = max(timelineZoom / 1.5, 0.5)
    }

    // MARK: - File Operations

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            // Video types
            .movie, .video, .mpeg4Movie, .quickTimeMovie, .avi,
            // Audio types
            .mp3, .mpeg4Audio, .aiff, .wav
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            openVideo(url: url)
        }
    }

    func exportVideo() {
        guard let sourceURL = videoURL, canExport else { return }

        let keptRegions = regions.filter { !$0.isBinned }
        guard !keptRegions.isEmpty else { return }

        // Show save panel to get write permission
        let savePanel = NSSavePanel()

        // Set allowed types based on media type
        // Note: AVFoundation cannot write MP3 files, so we don't offer it as an export option
        if isAudioOnly {
            savePanel.allowedContentTypes = [.mpeg4Audio, .aiff, .wav]
            savePanel.title = "Export Trimmed Audio"
            savePanel.message = "Choose where to save the exported audio"
        } else {
            savePanel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
            savePanel.title = "Export Trimmed Video"
            savePanel.message = "Choose where to save the exported video"
        }

        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldLabel = "Export As:"

        // Generate default filename
        let originalFilename = sourceURL.deletingPathExtension().lastPathComponent
        let sourceExt = sourceURL.pathExtension.lowercased()

        // Use appropriate output extension (MP3 sources export to M4A since AVFoundation can't write MP3)
        let outputExt: String
        if isAudioOnly {
            outputExt = (sourceExt == "mp3") ? "m4a" : sourceExt
        } else {
            outputExt = sourceExt
        }
        savePanel.nameFieldStringValue = "\(originalFilename)_export.\(outputExt)"

        // Set default directory to source file's directory
        savePanel.directoryURL = sourceURL.deletingLastPathComponent()

        guard savePanel.runModal() == .OK, let outputURL = savePanel.url else {
            return
        }

        isExporting = true
        exportProgress = 0

        Task {
            do {
                let resultURL = try await VideoExporter.export(
                    sourceURL: sourceURL,
                    regions: keptRegions,
                    outputURL: outputURL,
                    progressHandler: { [weak self] progress in
                        DispatchQueue.main.async {
                            self?.exportProgress = progress
                        }
                    }
                )

                await MainActor.run {
                    self.isExporting = false
                    self.exportProgress = 1.0

                    // Show success alert
                    let alert = NSAlert()
                    alert.messageText = "Export Complete"
                    alert.informativeText = "\(self.isAudioOnly ? "Audio" : "Video") exported to:\n\(resultURL.path)"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Show in Finder")

                    if alert.runModal() == .alertSecondButtonReturn {
                        NSWorkspace.shared.selectFile(resultURL.path, inFileViewerRootedAtPath: "")
                    }

                    // Clear undo stack after successful export
                    self.undoStack.removeAll()
                    self.redoStack.removeAll()
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false

                    let alert = NSAlert()
                    alert.messageText = "Export Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .critical
                    alert.runModal()
                }
            }
        }
    }

    func confirmClose() {
        let alert = NSAlert()
        alert.messageText = "Unsaved Changes"
        alert.informativeText = "You have unsaved trim regions. Are you sure you want to close?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Close Without Saving")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        } else {
            NSApplication.shared.reply(toApplicationShouldTerminate: false)
            showCloseConfirmation = false
        }
    }
}

struct RegionState {
    let regions: [Region]
}
