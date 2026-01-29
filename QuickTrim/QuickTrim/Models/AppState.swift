//
//  AppState.swift
//  QuickTrim
//

import SwiftUI
import AVFoundation
import Combine

class AppState: ObservableObject {
    static let shared = AppState()

    // Video state
    @Published var videoURL: URL?
    @Published var player: AVPlayer?
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var frameRate: Double = 30
    @Published var isPlaying: Bool = false

    // Regions
    @Published var regions: [Region] = []

    // Timeline
    @Published var timelineZoom: Double = 1.0
    @Published var skimmingEnabled: Bool = false
    @Published var previewModeEnabled: Bool = false

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

    var canExport: Bool {
        guard videoURL != nil, !regions.isEmpty else { return false }
        // At least one region must NOT be binned
        return regions.contains { !$0.isBinned }
    }

    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func openVideo(url: URL) {
        // Clean up previous video
        cleanUp()

        videoURL = url

        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)

        // Get duration and frame rate
        Task { @MainActor in
            do {
                let durationValue = try await asset.load(.duration)
                self.duration = CMTimeGetSeconds(durationValue)

                if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                    let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
                    self.frameRate = Double(nominalFrameRate)
                }

                // Initialize with single region covering entire video
                self.regions = [Region(startTime: 0, endTime: self.duration)]
                self.undoStack = []
                self.redoStack = []

            } catch {
                print("Error loading video: \(error)")
            }
        }

        // Observe playback time
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = CMTimeGetSeconds(time)
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
        videoURL = nil
        duration = 0
        currentTime = 0
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
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .avi]
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
        savePanel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Export Trimmed Video"
        savePanel.message = "Choose where to save the exported video"
        savePanel.nameFieldLabel = "Export As:"

        // Generate default filename
        let originalFilename = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        savePanel.nameFieldStringValue = "\(originalFilename)_export.\(ext)"

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
                    alert.informativeText = "Video exported to:\n\(resultURL.path)"
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
