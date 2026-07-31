//
//  AppState.swift
//  QuickTrim
//

import SwiftUI
import AVFoundation
import Combine
import UniformTypeIdentifiers

class AppState: ObservableObject {
    /// Tolerance for time comparisons (seconds). Accounts for floating-point imprecision in seek operations.
    static let timeTolerance: Double = 0.01

    // Media state
    @Published var videoURL: URL?
    @Published var player: AVPlayer?
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var frameRate: Double = 30
    @Published var isPlaying: Bool = false
    @Published var isAudioOnly: Bool = false
    @Published var hasAudioTrack: Bool = false

    // Regions
    @Published var regions: [Region] = []

    // Timeline
    @Published var timelineZoom: Double = 1.0
    @Published var skimmingEnabled: Bool = true  // Enabled by default
    @Published var previewModeEnabled: Bool = false
    @Published var capturePlayheadEnabled: Bool = false  // Auto-scroll to keep playhead visible

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

    // Export options
    @Published var exportRemoveAudio: Bool = false
    @Published var exportTranscode: Bool = false

    // Crop
    @Published var cropLeft: Int = 0
    @Published var cropTop: Int = 0
    @Published var cropRight: Int = 0
    @Published var cropBottom: Int = 0
    @Published var isCropModeActive: Bool = false
    @Published var videoNativeSize: CGSize = .zero

    var hasCrop: Bool {
        cropLeft > 0 || cropTop > 0 || cropRight > 0 || cropBottom > 0
    }

    var croppedSize: CGSize {
        let w = max(1, Int(videoNativeSize.width) - cropLeft - cropRight)
        let h = max(1, Int(videoNativeSize.height) - cropTop - cropBottom)
        return CGSize(width: w, height: h)
    }

    func resetCrop() {
        cropLeft = 0
        cropTop = 0
        cropRight = 0
        cropBottom = 0
    }

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

    var currentRegionID: Region.ID? {
        region(containing: currentTime)?.id
    }

    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var isAccessingSecurityScopedResource = false

    // Audio skimming
    private var skimStopTask: Task<Void, Never>?
    @Published var isSkimming: Bool = false

    // Set by seekToStart so togglePlayPause always seek-then-plays from
    // the intended position, avoiding AVPlayer race conditions.
    // Cleared only by togglePlayPause after it has used the value.
    private var pendingSeekTime: Double?

    // Set when play starts from a known-good position (e.g. after Home+Space).
    // Prevents handlePreviewModePlayback from interfering before the time
    // observer has caught up to the actual seek position.
    private var safePlaybackStartTime: Double?

    init() {}

    deinit {
        cleanUp()
    }

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

                self.hasAudioTrack = audioTracks.first != nil

                if let videoTrack = videoTracks.first {
                    // Has video track - treat as video file
                    self.isAudioOnly = false
                    // Some variable-frame-rate files report 0; fall back so
                    // frame stepping (1/frameRate) never divides by zero.
                    let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
                    self.frameRate = nominalFrameRate > 0 ? Double(nominalFrameRate) : 30.0

                    // Load native video size (accounting for rotation)
                    let naturalSize = try await videoTrack.load(.naturalSize)
                    let preferredTransform = try await videoTrack.load(.preferredTransform)
                    let transformedSize = naturalSize.applying(preferredTransform)
                    self.videoNativeSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
                } else if audioTracks.first != nil {
                    // No video track but has audio - audio-only file
                    self.isAudioOnly = true
                    self.frameRate = 30.0  // Use standard rate for UI timeline
                } else {
                    // No usable tracks
                    self.presentOpenFailure(
                        for: url,
                        reason: "The file contains no playable video or audio."
                    )
                    return
                }

                // Initialize with single region covering entire media
                self.regions = [Region(startTime: 0, endTime: self.duration)]
                self.undoStack = []
                self.redoStack = []

            } catch {
                self.presentOpenFailure(for: url, reason: error.localizedDescription)
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

    /// Tell the user a file couldn't be opened and reset to the drop zone
    /// instead of leaving the window half-loaded.
    private func presentOpenFailure(for url: URL, reason: String) {
        cleanUp()

        let alert = NSAlert()
        alert.messageText = "Could Not Open \u{201C}\(url.lastPathComponent)\u{201D}"
        alert.informativeText = reason
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func cleanUp() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
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
        hasAudioTrack = false
        videoNativeSize = .zero
        cropLeft = 0
        cropTop = 0
        cropRight = 0
        cropBottom = 0
        isCropModeActive = false
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
        if abs(currentTime - region.startTime) < Self.timeTolerance || abs(currentTime - region.endTime) < Self.timeTolerance {
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

    func toggleBinForCurrentRegion() {
        guard let region = region(containing: currentTime) else { return }
        toggleBin(for: region)
    }

    func canRemoveStartMarker(for region: Region) -> Bool {
        guard let index = regions.firstIndex(where: { $0.id == region.id }) else { return false }
        return index > 0
    }

    func removeStartMarker(for region: Region) {
        guard let index = regions.firstIndex(where: { $0.id == region.id }), index > 0 else { return }

        saveStateForUndo()

        let previousRegion = regions[index - 1]
        let mergedRegion = Region(
            startTime: previousRegion.startTime,
            endTime: region.endTime,
            isBinned: region.isBinned
        )

        regions.removeSubrange((index - 1)...index)
        regions.insert(mergedRegion, at: index - 1)
    }

    func removeStartMarkerForCurrentRegion() {
        guard let region = region(containing: currentTime) else { return }
        removeStartMarker(for: region)
    }

    func region(containing time: Double) -> Region? {
        guard !regions.isEmpty else { return nil }

        let clampedTime = max(0, min(time, duration))
        if clampedTime >= duration - Self.timeTolerance {
            return regions.max { $0.endTime < $1.endTime }
        }

        return regions.first { $0.contains(time: clampedTime) }
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
        // Always cancel any pending skim stop so it doesn't interfere with playback
        skimStopTask?.cancel()
        if isSkimming {
            isSkimming = false
        }

        if isPlaying {
            player?.pause()
            safePlaybackStartTime = nil
        } else {
            guard let player = player else { return }

            // If seekToStart set a pending target, always seek-then-play from there.
            // In preview mode, nudge one frame forward from the region boundary to
            // avoid AVPlayer edge cases where playback silently fails at exact
            // region start positions.
            if let seekTarget = pendingSeekTime {
                pendingSeekTime = nil
                let playFrom: Double
                if previewModeEnabled {
                    playFrom = seekTarget + (1.0 / frameRate)
                } else {
                    playFrom = seekTarget
                }
                safePlaybackStartTime = playFrom
                let cmTime = CMTime(seconds: playFrom, preferredTimescale: 600)
                player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    self?.player?.play()
                }
                return
            }

            let actualTime = CMTimeGetSeconds(player.currentTime())

            // Determine the valid playback end point
            let endTime: Double
            if previewModeEnabled {
                endTime = keptRegions.last?.endTime ?? duration
            } else {
                endTime = duration
            }

            // If we're at or past the end, seek to start first, then play
            if actualTime >= endTime - Self.timeTolerance {
                let startTime: Double
                if previewModeEnabled {
                    startTime = keptRegions.first?.startTime ?? 0
                } else {
                    startTime = 0
                }
                let cmTime = CMTime(seconds: startTime, preferredTimescale: 600)
                player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    self?.player?.play()
                }
                return
            }

            // In preview mode, check if we need to jump to a kept region first
            if previewModeEnabled {
                let inBinnedRegion = regions.contains { region in
                    region.isBinned && actualTime >= region.startTime - Self.timeTolerance && actualTime < region.endTime
                }

                if inBinnedRegion {
                    // Find the next kept region
                    if let nextKept = keptRegions.first(where: { $0.startTime >= actualTime - Self.timeTolerance }) {
                        let cmTime = CMTime(seconds: nextKept.startTime, preferredTimescale: 600)
                        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                            self?.player?.play()
                        }
                        return
                    } else if let firstKept = keptRegions.first {
                        let cmTime = CMTime(seconds: firstKept.startTime, preferredTimescale: 600)
                        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                            self?.player?.play()
                        }
                        return
                    }
                }
            }

            player.play()
        }
    }

    func seek(to time: Double, completion: ((Bool) -> Void)? = nil) {
        let targetTime = max(0, min(time, duration))
        currentTime = targetTime

        let cmTime = CMTime(seconds: targetTime, preferredTimescale: 600)
        if let completion = completion {
            player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: completion)
        } else {
            player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    /// Seek and briefly play audio for skimming feedback (FCP-style)
    func skimTo(time: Double) {
        // Never hijack real playback: hovering the timeline while playing
        // would otherwise seek the playhead and pause 150ms later.
        if isPlaying && !isSkimming { return }

        seek(to: time)

        // Play audio briefly during skimming for all media types
        guard skimmingEnabled else { return }

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
        player?.pause()

        let targetTime: Double
        if previewModeEnabled {
            targetTime = keptRegions.first?.startTime ?? 0
        } else {
            targetTime = 0
        }

        // Store pending target so togglePlayPause always does a fresh seek-then-play.
        // We do the actual seek here for visual feedback, but togglePlayPause will
        // re-seek to guarantee the position before calling play().
        pendingSeekTime = targetTime
        currentTime = targetTime  // Update UI immediately

        let cmTime = CMTime(seconds: targetTime, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // Handle preview mode playback - skip binned regions
    private func handlePreviewModePlayback(currentTime: Double) {
        // Only handle during actual playback (not when paused)
        guard isPlaying else { return }

        // If we just started playback from a known-good position (e.g. Home+Space),
        // the time observer may report a stale position for a few ticks. Wait until
        // the reported time is near our target before applying binned-region logic.
        if let safeTime = safePlaybackStartTime {
            if abs(currentTime - safeTime) > 0.5 {
                // Time observer hasn't caught up yet — skip this tick
                return
            }
            // We've arrived at (or past) the safe position — resume normal logic
            safePlaybackStartTime = nil
        }

        // Check if we're in a binned region
        let inBinnedRegion = regions.contains { region in
            region.isBinned && currentTime >= region.startTime - Self.timeTolerance && currentTime < region.endTime
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
            if currentTime >= lastKept.endTime - Self.timeTolerance {
                player?.pause()
            }
        }
    }

    // MARK: - Timeline Zoom

    func zoomIn() {
        timelineZoom = min(timelineZoom * 1.5, 10.0)
    }

    func zoomOut() {
        // 100% is the floor: the timeline never renders below window width
        timelineZoom = max(timelineZoom / 1.5, 1.0)
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

        let options = ExportOptions(
            removeAudio: exportRemoveAudio,
            transcodeOutput: exportTranscode,
            cropLeft: cropLeft,
            cropTop: cropTop,
            cropRight: cropRight,
            cropBottom: cropBottom,
            videoSize: videoNativeSize
        )

        Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let resultURL = try await VideoExporter.export(
                    sourceURL: sourceURL,
                    regions: keptRegions,
                    outputURL: outputURL,
                    options: options,
                    progressHandler: { progress in
                        DispatchQueue.main.async {
                            self.exportProgress = progress
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
