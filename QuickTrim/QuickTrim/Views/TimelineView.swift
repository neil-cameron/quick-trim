//
//  TimelineView.swift
//  QuickTrim
//

import SwiftUI
import AVFoundation

struct TimelineView: View {
    @EnvironmentObject var appState: AppState
    @State private var isSkimming = false

    private let timecodeHeight: CGFloat = 20
    private let playheadWidth: CGFloat = 2

    var body: some View {
        VStack(spacing: 0) {
            // Zoom controls and time display
            HStack {
                // Trimmed time display (preview/export duration)
                HStack(spacing: 4) {
                    Image(systemName: "scissors")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text(formatTimecode(appState.previewCurrentTime))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.green)
                    Text("/")
                        .foregroundColor(.secondary)
                    Text(formatTimecode(appState.previewDuration))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.green.opacity(0.7))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

                Spacer()

                // Skimming toggle
                Toggle(isOn: $appState.skimmingEnabled) {
                    Label("Skimming", systemImage: "hand.point.up.left")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Enable skimming - hover to preview (⌘⌥S)")

                // Capture Playhead toggle (auto-scroll to follow playhead)
                Toggle(isOn: $appState.capturePlayheadEnabled) {
                    Image(systemName: "location.fill")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Capture playhead - auto-scroll to keep playhead visible")

                // Preview mode toggle
                Toggle(isOn: $appState.previewModeEnabled) {
                    Label("Preview", systemImage: "eye")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Show timeline as export preview (⌘⌥P)")

                Divider()
                    .frame(height: 16)

                // Zoom controls
                HStack(spacing: 8) {
                    Button(action: { appState.zoomOut() }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.plain)
                    .help("Zoom out (⌘-)")

                    Text("\(Int(appState.timelineZoom * 100))%")
                        .font(.caption)
                        .frame(width: 40)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            appState.timelineZoom = 1.0
                        }
                        .help("Double-click to reset to 100%")

                    Button(action: { appState.zoomIn() }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.plain)
                    .help("Zoom in (⌘+)")

                    ZoomSlider(zoom: $appState.timelineZoom)
                        .frame(width: 80)
                }

                Divider()
                    .frame(height: 16)

                // Mark Trim button
                Button(action: { appState.markTrim() }) {
                    Label("Mark Trim", systemImage: "scissors")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Mark trim point (M)")
                .disabled(appState.videoURL == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Timeline content - switch between normal and preview mode
            if appState.previewModeEnabled {
                PreviewTimelineContent(timecodeHeight: timecodeHeight, playheadWidth: playheadWidth)
            } else {
                NormalTimelineContent(timecodeHeight: timecodeHeight, playheadWidth: playheadWidth)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func formatTimecode(_ time: Double) -> String {
        guard time.isFinite && time >= 0 else { return "00:00:00:00" }

        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let frames = Int((time - floor(time)) * appState.frameRate)

        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
}

// MARK: - Zoom Slider with double-click reset

struct ZoomSlider: View {
    @Binding var zoom: Double

    var body: some View {
        Slider(value: $zoom, in: 0.5...10.0)
            .gesture(
                TapGesture(count: 2)
                    .onEnded {
                        zoom = 1.0
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        zoom = 1.0
                    }
            )
            .help("Double-click to reset to 100%")
    }
}

// MARK: - Normal Timeline (full video)

struct NormalTimelineContent: View {
    @EnvironmentObject var appState: AppState
    let timecodeHeight: CGFloat
    let playheadWidth: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(geometry.size.width * appState.timelineZoom, geometry.size.width)

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color(nsColor: .textBackgroundColor))

                        VStack(spacing: 0) {
                            TimecodeRulerView(
                                duration: appState.duration,
                                width: contentWidth,
                                zoom: appState.timelineZoom
                            )
                            .frame(height: timecodeHeight)

                            NormalThumbnailTrackView(
                                width: contentWidth,
                                height: geometry.size.height - timecodeHeight - 10
                            )
                        }

                        // Region status bars at bottom (green for kept, red for binned)
                        if appState.duration > 0 {
                            VStack {
                                Spacer()
                                HStack(spacing: 0) {
                                    ForEach(appState.regions) { region in
                                        let regionWidth = (region.duration / appState.duration) * contentWidth
                                        Rectangle()
                                            .fill(region.isBinned ? Color.red : Color.green)
                                            .frame(width: regionWidth, height: 4)
                                    }
                                }
                            }
                            .frame(height: geometry.size.height)
                        }

                        // Region dividers (yellow vertical lines at trim points)
                        if appState.regions.count > 1 && appState.duration > 0 {
                            ForEach(appState.regions.dropLast()) { region in
                                let x = (region.endTime / appState.duration) * contentWidth
                                Rectangle()
                                    .fill(Color.yellow)
                                    .frame(width: 2, height: geometry.size.height)
                                    .position(x: x, y: geometry.size.height / 2)
                            }
                        }

                        // Playhead
                        if appState.duration > 0 {
                            let playheadX = (appState.currentTime / appState.duration) * contentWidth

                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 2, height: geometry.size.height)
                                .position(x: playheadX, y: geometry.size.height / 2)
                        }

                        // Invisible anchor views for scrolling - on top but non-interactive
                        HStack(spacing: 0) {
                            ForEach(0..<100, id: \.self) { index in
                                Color.clear
                                    .frame(width: contentWidth / 100)
                                    .id("segment\(index)")
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .frame(width: contentWidth, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let time = timeFromPosition(value.location.x, width: contentWidth)
                                appState.seek(to: time)
                            }
                    )
                    .onContinuousHover { phase in
                        guard appState.skimmingEnabled else { return }
                        switch phase {
                        case .active(let location):
                            let time = timeFromPosition(location.x, width: contentWidth)
                            appState.skimTo(time: time)
                        case .ended:
                            appState.stopSkimming()
                        }
                    }
                }
                .onChange(of: appState.currentTime) { _, newTime in
                    if appState.capturePlayheadEnabled && appState.duration > 0 {
                        let position = newTime / appState.duration
                        let segmentIndex = min(99, max(0, Int(position * 100)))
                        withAnimation(.linear(duration: 0.1)) {
                            scrollProxy.scrollTo("segment\(segmentIndex)", anchor: .center)
                        }
                    }
                }
                .onChange(of: appState.capturePlayheadEnabled) { _, newValue in
                    if newValue && appState.duration > 0 {
                        let position = appState.currentTime / appState.duration
                        let segmentIndex = min(99, max(0, Int(position * 100)))
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("segment\(segmentIndex)", anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func timeFromPosition(_ x: CGFloat, width: CGFloat) -> Double {
        let proportion = x / width
        return max(0, min(proportion * appState.duration, appState.duration))
    }
}

// MARK: - Preview Timeline (collapsed to kept regions only)

struct PreviewTimelineContent: View {
    @EnvironmentObject var appState: AppState
    let timecodeHeight: CGFloat
    let playheadWidth: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(geometry.size.width * appState.timelineZoom, geometry.size.width)
            let keptRegions = appState.keptRegions
            let previewDuration = appState.previewDuration

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color(nsColor: .textBackgroundColor))

                        VStack(spacing: 0) {
                            // Preview timecode ruler (shows collapsed time)
                            TimecodeRulerView(
                                duration: previewDuration,
                                width: contentWidth,
                                zoom: appState.timelineZoom
                            )
                            .frame(height: timecodeHeight)

                            // Preview thumbnail track
                            PreviewThumbnailTrackView(
                                width: contentWidth,
                                height: geometry.size.height - timecodeHeight - 10
                            )
                        }

                        // Region dividers between kept regions (green vertical lines)
                        if keptRegions.count > 1 && previewDuration > 0 {
                            ForEach(Array(keptRegions.dropLast().enumerated()), id: \.element.id) { index, _ in
                                let previewTime = keptRegions.prefix(index + 1).reduce(0) { $0 + $1.duration }
                                let x = (previewTime / previewDuration) * contentWidth
                                Rectangle()
                                    .fill(Color.green.opacity(0.7))
                                    .frame(width: 2, height: geometry.size.height)
                                    .position(x: x, y: geometry.size.height / 2)
                            }
                        }

                        // Playhead in preview coordinates
                        if previewDuration > 0 {
                            let previewTime = appState.convertToPreviewTime(appState.currentTime)
                            let playheadX = (previewTime / previewDuration) * contentWidth

                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 2, height: geometry.size.height)
                                .position(x: playheadX, y: geometry.size.height / 2)
                        }

                        // Invisible anchor views for scrolling - on top but non-interactive
                        HStack(spacing: 0) {
                            ForEach(0..<100, id: \.self) { index in
                                Color.clear
                                    .frame(width: contentWidth / 100)
                                    .id("previewSegment\(index)")
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .frame(width: contentWidth, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let previewTime = previewTimeFromPosition(value.location.x, width: contentWidth, previewDuration: previewDuration)
                                let sourceTime = appState.convertFromPreviewTime(previewTime)
                                appState.seek(to: sourceTime)
                            }
                    )
                    .onContinuousHover { phase in
                        guard appState.skimmingEnabled else { return }
                        switch phase {
                        case .active(let location):
                            let previewTime = previewTimeFromPosition(location.x, width: contentWidth, previewDuration: previewDuration)
                            let sourceTime = appState.convertFromPreviewTime(previewTime)
                            appState.skimTo(time: sourceTime)
                        case .ended:
                            appState.stopSkimming()
                        }
                    }
                }
                .onChange(of: appState.currentTime) { _, _ in
                    if appState.capturePlayheadEnabled && previewDuration > 0 {
                        let previewTime = appState.convertToPreviewTime(appState.currentTime)
                        let position = previewTime / previewDuration
                        let segmentIndex = min(99, max(0, Int(position * 100)))
                        withAnimation(.linear(duration: 0.1)) {
                            scrollProxy.scrollTo("previewSegment\(segmentIndex)", anchor: .center)
                        }
                    }
                }
                .onChange(of: appState.capturePlayheadEnabled) { _, newValue in
                    if newValue && previewDuration > 0 {
                        let previewTime = appState.convertToPreviewTime(appState.currentTime)
                        let position = previewTime / previewDuration
                        let segmentIndex = min(99, max(0, Int(position * 100)))
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("previewSegment\(segmentIndex)", anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func previewTimeFromPosition(_ x: CGFloat, width: CGFloat, previewDuration: Double) -> Double {
        let proportion = x / width
        return max(0, min(proportion * previewDuration, previewDuration))
    }
}

// MARK: - Timecode Ruler

struct TimecodeRulerView: View {
    let duration: Double
    let width: CGFloat
    let zoom: Double

    var body: some View {
        Canvas { context, size in
            guard duration > 0 else { return }

            let pixelsPerSecond = width / duration

            let majorInterval: Double
            let minorTicksPerMajor: Int

            if pixelsPerSecond > 100 {
                majorInterval = 1.0
                minorTicksPerMajor = 4
            } else if pixelsPerSecond > 20 {
                majorInterval = 5.0
                minorTicksPerMajor = 5
            } else if pixelsPerSecond > 5 {
                majorInterval = 15.0
                minorTicksPerMajor = 3
            } else {
                majorInterval = 60.0
                minorTicksPerMajor = 4
            }

            let minorInterval = majorInterval / Double(minorTicksPerMajor)

            var time: Double = 0
            while time <= duration {
                let x = (time / duration) * width
                let isMajor = time.truncatingRemainder(dividingBy: majorInterval) < 0.001

                let tickHeight: CGFloat = isMajor ? 10 : 5
                let tickPath = Path { path in
                    path.move(to: CGPoint(x: x, y: size.height - tickHeight))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }

                context.stroke(tickPath, with: .color(.secondary.opacity(0.5)), lineWidth: 1)

                if isMajor {
                    let label = formatTimeLabel(time)
                    let text = Text(label)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)

                    context.draw(text, at: CGPoint(x: x, y: 6), anchor: .top)
                }

                time += minorInterval
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func formatTimeLabel(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60

        if time >= 3600 {
            let hours = Int(time) / 3600
            return String(format: "%d:%02d:%02d", hours, minutes % 60, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Normal Thumbnail Track

struct NormalThumbnailTrackView: View {
    @EnvironmentObject var appState: AppState
    let width: CGFloat
    let height: CGFloat

    private let statusBarHeight: CGFloat = 4

    var body: some View {
        ZStack(alignment: .leading) {
            // Region backgrounds (red overlay for binned)
            ForEach(appState.regions) { region in
                RegionBackground(
                    region: region,
                    totalDuration: appState.duration,
                    totalWidth: width,
                    height: height - statusBarHeight
                )
            }

            // Thumbnails or Waveform based on media type
            if appState.isAudioOnly {
                WaveformStripView(width: width, height: height - statusBarHeight)
            } else {
                ThumbnailStripView(width: width, height: height - statusBarHeight)
            }
            // Note: Status bars and dividers are now drawn at NormalTimelineContent level for proper alignment with playhead
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Preview Thumbnail Track (collapsed)

struct PreviewThumbnailTrackView: View {
    @EnvironmentObject var appState: AppState
    let width: CGFloat
    let height: CGFloat

    private let statusBarHeight: CGFloat = 4

    var body: some View {
        let keptRegions = appState.keptRegions
        let previewDuration = appState.previewDuration

        ZStack(alignment: .leading) {
            // Thumbnails or Waveform for each kept region, positioned contiguously
            if appState.isAudioOnly {
                PreviewWaveformStripView(
                    keptRegions: keptRegions,
                    previewDuration: previewDuration,
                    width: width,
                    height: height - statusBarHeight
                )
            } else {
                PreviewThumbnailStripView(
                    keptRegions: keptRegions,
                    previewDuration: previewDuration,
                    width: width,
                    height: height - statusBarHeight
                )
            }

            // Green status bar at bottom (all kept in preview mode)
            VStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(Color.green)
                    .frame(width: width, height: statusBarHeight)
            }
            // Note: Green dividers are now drawn at PreviewTimelineContent level for proper alignment with playhead
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Region Background

struct RegionBackground: View {
    let region: Region
    let totalDuration: Double
    let totalWidth: CGFloat
    let height: CGFloat

    var body: some View {
        let startX = (region.startTime / totalDuration) * totalWidth
        let regionWidth = (region.duration / totalDuration) * totalWidth

        Rectangle()
            .fill(region.isBinned ? Color.red.opacity(0.3) : Color.clear)
            .frame(width: regionWidth, height: height)
            .offset(x: startX)
            .overlay(
                Group {
                    if region.isBinned {
                        StrikethroughPattern()
                            .frame(width: regionWidth, height: height)
                            .offset(x: startX)
                            .opacity(0.3)
                    }
                }
            )
    }
}

struct StrikethroughPattern: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 15
            let lineWidth: CGFloat = 2

            var x: CGFloat = -size.height
            while x < size.width + size.height {
                let path = Path { path in
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                }
                context.stroke(path, with: .color(.red), lineWidth: lineWidth)
                x += spacing
            }
        }
    }
}

// MARK: - Thumbnail Strip (Normal mode)

struct ThumbnailStripView: View {
    @EnvironmentObject var appState: AppState
    @State private var thumbnails: [(time: Double, image: NSImage)] = []
    @State private var lastGeneratedURL: URL?
    @State private var lastGeneratedWidth: CGFloat = 0
    @State private var lastGeneratedDuration: Double = 0
    @State private var generationTask: Task<Void, Never>?

    let width: CGFloat
    let height: CGFloat

    private let thumbnailWidth: CGFloat = 80

    var body: some View {
        HStack(spacing: 0) {
            ForEach(thumbnails, id: \.time) { thumbnail in
                Image(nsImage: thumbnail.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbnailWidth, height: height)
                    .clipped()
            }
        }
        .onAppear {
            generateThumbnailsIfNeeded()
        }
        .onChange(of: appState.videoURL) { _, _ in
            // Reset cache on new video
            lastGeneratedURL = nil
            lastGeneratedDuration = 0
            thumbnails = []
            generateThumbnailsIfNeeded()
        }
        .onChange(of: appState.duration) { _, newDuration in
            // Regenerate when duration becomes available (async load)
            if newDuration > 0 && lastGeneratedDuration == 0 {
                generateThumbnailsIfNeeded()
            }
        }
        .onChange(of: width) { _, _ in
            generateThumbnailsIfNeeded()
        }
    }

    private func generateThumbnailsIfNeeded() {
        // Need valid URL and duration
        guard let url = appState.videoURL, appState.duration > 0 else {
            return
        }

        let widthChanged = abs(width - lastGeneratedWidth) > 20
        let urlChanged = url != lastGeneratedURL
        let durationChanged = lastGeneratedDuration == 0 && appState.duration > 0
        let needsData = thumbnails.isEmpty

        guard urlChanged || widthChanged || durationChanged || needsData else { return }

        lastGeneratedURL = url
        lastGeneratedDuration = appState.duration
        // Don't update lastGeneratedWidth yet — only on successful completion
        let capturedWidth = width

        generateThumbnails(url: url, capturedWidth: capturedWidth)
    }

    private func generateThumbnails(url: URL, capturedWidth: CGFloat) {
        generationTask?.cancel()

        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: thumbnailWidth * 2, height: height * 2)

        let numberOfThumbnails = Int(ceil(capturedWidth / thumbnailWidth))
        guard numberOfThumbnails > 0 && appState.duration > 0 else { return }

        let interval = appState.duration / Double(numberOfThumbnails)

        generationTask = Task {
            var newThumbnails: [(time: Double, image: NSImage)] = []

            for i in 0..<numberOfThumbnails {
                if Task.isCancelled { return }

                let time = Double(i) * interval + interval / 2
                let cmTime = CMTime(seconds: time, preferredTimescale: 600)

                do {
                    let (cgImage, _) = try await imageGenerator.image(at: cmTime)
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: thumbnailWidth, height: height))
                    newThumbnails.append((time: time, image: nsImage))
                } catch {
                    let placeholder = NSImage(size: NSSize(width: thumbnailWidth, height: height))
                    newThumbnails.append((time: time, image: placeholder))
                }
            }

            if !Task.isCancelled {
                await MainActor.run {
                    self.thumbnails = newThumbnails
                    self.lastGeneratedWidth = capturedWidth
                }
            }
        }
    }
}

// MARK: - Preview Thumbnail Strip (collapsed mode)

struct PreviewThumbnailStripView: View {
    @EnvironmentObject var appState: AppState
    @State private var thumbnails: [(time: Double, image: NSImage)] = []
    @State private var lastKeptRegionIds: [UUID] = []
    @State private var lastGeneratedWidth: CGFloat = 0
    @State private var generationTask: Task<Void, Never>?

    let keptRegions: [Region]
    let previewDuration: Double
    let width: CGFloat
    let height: CGFloat

    private let thumbnailWidth: CGFloat = 80

    var body: some View {
        HStack(spacing: 0) {
            ForEach(thumbnails, id: \.time) { thumbnail in
                Image(nsImage: thumbnail.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbnailWidth, height: height)
                    .clipped()
            }
        }
        .onAppear {
            generateThumbnailsIfNeeded()
        }
        .onChange(of: keptRegions.map { $0.id }) { _, _ in
            generateThumbnailsIfNeeded()
        }
        .onChange(of: width) { _, _ in
            generateThumbnailsIfNeeded()
        }
    }

    private func generateThumbnailsIfNeeded() {
        guard let url = appState.videoURL else {
            thumbnails = []
            return
        }

        let currentIds = keptRegions.map { $0.id }
        let idsChanged = currentIds != lastKeptRegionIds
        let widthChanged = abs(width - lastGeneratedWidth) > 20
        let needsData = thumbnails.isEmpty

        guard idsChanged || widthChanged || needsData else { return }

        lastKeptRegionIds = currentIds
        // Don't update lastGeneratedWidth yet — only on successful completion
        let capturedWidth = width

        generateThumbnails(url: url, capturedWidth: capturedWidth)
    }

    private func generateThumbnails(url: URL, capturedWidth: CGFloat) {
        generationTask?.cancel()

        guard previewDuration > 0 else {
            thumbnails = []
            return
        }

        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: thumbnailWidth * 2, height: height * 2)

        let numberOfThumbnails = Int(ceil(capturedWidth / thumbnailWidth))
        guard numberOfThumbnails > 0 else { return }

        let interval = previewDuration / Double(numberOfThumbnails)

        generationTask = Task {
            var newThumbnails: [(time: Double, image: NSImage)] = []

            for i in 0..<numberOfThumbnails {
                if Task.isCancelled { return }

                // Calculate preview time, then convert to source time
                let previewTime = Double(i) * interval + interval / 2
                let sourceTime = appState.convertFromPreviewTime(previewTime)
                let cmTime = CMTime(seconds: sourceTime, preferredTimescale: 600)

                do {
                    let (cgImage, _) = try await imageGenerator.image(at: cmTime)
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: thumbnailWidth, height: height))
                    newThumbnails.append((time: previewTime, image: nsImage))
                } catch {
                    let placeholder = NSImage(size: NSSize(width: thumbnailWidth, height: height))
                    newThumbnails.append((time: previewTime, image: placeholder))
                }
            }

            if !Task.isCancelled {
                await MainActor.run {
                    self.thumbnails = newThumbnails
                    self.lastGeneratedWidth = capturedWidth
                }
            }
        }
    }
}

// MARK: - Waveform Strip (Normal mode - for audio files)

struct WaveformStripView: View {
    @EnvironmentObject var appState: AppState
    @State private var waveformData: WaveformData?
    @State private var lastGeneratedURL: URL?
    @State private var lastGeneratedWidth: CGFloat = 0
    @State private var generationTask: Task<Void, Never>?

    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            if let data = waveformData {
                TimelineWaveformCanvas(
                    samples: data.samples,
                    regions: appState.regions,
                    duration: appState.duration,
                    width: width,
                    height: height
                )
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                ProgressView()
            }
        }
        .frame(width: width, height: height)
        .onAppear {
            loadWaveformIfNeeded()
        }
        .onChange(of: appState.videoURL) { _, _ in
            lastGeneratedURL = nil
            waveformData = nil
            loadWaveformIfNeeded()
        }
        .onChange(of: width) { _, _ in
            loadWaveformIfNeeded()
        }
    }

    private func loadWaveformIfNeeded() {
        guard let url = appState.videoURL, appState.duration > 0 else { return }

        let urlChanged = url != lastGeneratedURL
        let widthChanged = abs(width - lastGeneratedWidth) > 20

        // Always regenerate if we have no data (previous attempt may have been cancelled)
        let needsData = waveformData == nil

        guard urlChanged || widthChanged || needsData else { return }

        // Cancel any in-flight generation
        generationTask?.cancel()

        lastGeneratedURL = url
        // Don't update lastGeneratedWidth yet — only on successful completion.
        // This prevents a cancelled task from blocking future regeneration attempts.
        let capturedWidth = width

        generationTask = Task {
            do {
                // Use rough waveform for faster initial display
                // Sample count based on pixels - roughly 1 sample per 2 pixels
                let samplesNeeded = max(200, Int(capturedWidth / 2))
                let data = try await WaveformGenerator.generateRoughWaveform(
                    from: url,
                    totalSamples: samplesNeeded
                )
                if !Task.isCancelled {
                    await MainActor.run {
                        self.waveformData = data
                        self.lastGeneratedWidth = capturedWidth
                    }
                }
            } catch {
                if !Task.isCancelled {
                    print("Waveform generation failed: \(error)")
                    // Set empty waveform to clear spinner
                    await MainActor.run {
                        self.waveformData = WaveformData(samples: [0], duration: appState.duration)
                        self.lastGeneratedWidth = capturedWidth
                    }
                }
            }
        }
    }
}

struct TimelineWaveformCanvas: View {
    let samples: [Float]
    let regions: [Region]
    let duration: Double
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let barWidth = max(1, size.width / CGFloat(max(1, samples.count)))

            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * barWidth
                let normalizedTime = Double(index) / Double(max(1, samples.count)) * duration

                // Determine if this sample is in a binned region
                let isBinned = regions.contains { region in
                    region.isBinned &&
                    normalizedTime >= region.startTime &&
                    normalizedTime < region.endTime
                }

                let barHeight = CGFloat(abs(sample)) * midY * 0.9
                let color: Color = isBinned ? .red.opacity(0.5) : .green

                let rect = CGRect(
                    x: x,
                    y: midY - barHeight,
                    width: max(barWidth - 0.5, 1),
                    height: barHeight * 2
                )
                context.fill(Path(rect), with: .color(color))
            }
        }
    }
}

// MARK: - Preview Waveform Strip (collapsed mode - for audio files)

struct PreviewWaveformStripView: View {
    @EnvironmentObject var appState: AppState
    @State private var waveformData: WaveformData?
    @State private var lastKeptRegionIds: [UUID] = []
    @State private var lastGeneratedWidth: CGFloat = 0
    @State private var generationTask: Task<Void, Never>?

    let keptRegions: [Region]
    let previewDuration: Double
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            if let data = waveformData {
                PreviewWaveformCanvas(
                    samples: data.samples,
                    width: width,
                    height: height
                )
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                ProgressView()
            }
        }
        .frame(width: width, height: height)
        .onAppear {
            generatePreviewWaveform(force: true)
        }
        .onChange(of: keptRegions.map { $0.id }) { _, _ in
            generatePreviewWaveform()
        }
        .onChange(of: width) { _, _ in
            generatePreviewWaveform()
        }
    }

    private func generatePreviewWaveform(force: Bool = false) {
        guard let url = appState.videoURL,
              previewDuration > 0 else {
            waveformData = nil
            return
        }

        let currentIds = keptRegions.map { $0.id }
        let idsChanged = currentIds != lastKeptRegionIds
        let widthChanged = abs(width - lastGeneratedWidth) > 20
        // Always regenerate if we have no data (previous attempt may have been cancelled)
        let needsData = waveformData == nil

        guard force || idsChanged || widthChanged || needsData else { return }

        lastKeptRegionIds = currentIds
        // Don't update lastGeneratedWidth yet — only on successful completion
        let capturedWidth = width

        generationTask?.cancel()
        generationTask = Task {
            do {
                // Use rough waveform for faster display
                let samplesNeeded = max(200, Int(capturedWidth / 2))
                let fullData = try await WaveformGenerator.generateRoughWaveform(
                    from: url,
                    totalSamples: samplesNeeded
                )

                if Task.isCancelled { return }

                // Extract samples for kept regions only
                var previewSamples: [Float] = []
                let samplesPerSecondActual = Double(fullData.samples.count) / fullData.duration

                for region in keptRegions {
                    let startIndex = Int(region.startTime * samplesPerSecondActual)
                    let endIndex = Int(region.endTime * samplesPerSecondActual)
                    let clampedStart = max(0, min(startIndex, fullData.samples.count - 1))
                    let clampedEnd = max(0, min(endIndex, fullData.samples.count))

                    if clampedStart < clampedEnd {
                        previewSamples.append(contentsOf: fullData.samples[clampedStart..<clampedEnd])
                    }
                }

                if Task.isCancelled { return }

                // Always set waveform data even if samples are empty (prevents infinite spinner)
                let previewData = WaveformData(samples: previewSamples.isEmpty ? [0] : previewSamples, duration: previewDuration)

                await MainActor.run {
                    self.waveformData = previewData
                    self.lastGeneratedWidth = capturedWidth
                }
            } catch {
                if !Task.isCancelled {
                    print("Preview waveform generation failed: \(error)")
                    await MainActor.run {
                        self.waveformData = WaveformData(samples: [0], duration: previewDuration)
                        self.lastGeneratedWidth = capturedWidth
                    }
                }
            }
        }
    }
}

struct PreviewWaveformCanvas: View {
    let samples: [Float]
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let barWidth = max(1, size.width / CGFloat(max(1, samples.count)))

            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * barWidth
                let barHeight = CGFloat(abs(sample)) * midY * 0.9

                let rect = CGRect(
                    x: x,
                    y: midY - barHeight,
                    width: max(barWidth - 0.5, 1),
                    height: barHeight * 2
                )
                context.fill(Path(rect), with: .color(.green))
            }
        }
    }
}

#Preview {
    TimelineView()
        .environmentObject(AppState())
        .frame(width: 800, height: 120)
}
