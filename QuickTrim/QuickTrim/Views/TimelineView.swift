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

    // Display time based on preview mode
    private var displayCurrentTime: Double {
        appState.previewModeEnabled ? appState.previewCurrentTime : appState.currentTime
    }

    private var displayDuration: Double {
        appState.previewModeEnabled ? appState.previewDuration : appState.duration
    }

    var body: some View {
        VStack(spacing: 0) {
            // Zoom controls and time display
            HStack {
                // Current time readout
                HStack(spacing: 4) {
                    Image(systemName: appState.previewModeEnabled ? "eye" : "timer")
                        .foregroundColor(appState.previewModeEnabled ? .accentColor : .secondary)
                    Text(formatTimecode(displayCurrentTime))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                    Text("/")
                        .foregroundColor(.secondary)
                    Text(formatTimecode(displayDuration))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(appState.previewModeEnabled ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                )

                Spacer()

                // Skimming toggle
                Toggle(isOn: $appState.skimmingEnabled) {
                    Label("Skimming", systemImage: "hand.point.up.left")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Enable skimming - hover to preview (⌘⌥S)")

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

                    Button(action: { appState.zoomIn() }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.plain)
                    .help("Zoom in (⌘+)")

                    Slider(value: $appState.timelineZoom, in: 0.5...10.0)
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

// MARK: - Normal Timeline (full video)

struct NormalTimelineContent: View {
    @EnvironmentObject var appState: AppState
    let timecodeHeight: CGFloat
    let playheadWidth: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(geometry.size.width * appState.timelineZoom, geometry.size.width)

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

                    // Playhead
                    if appState.duration > 0 {
                        let playheadX = (appState.currentTime / appState.duration) * contentWidth

                        Rectangle()
                            .fill(Color.red)
                            .frame(width: playheadWidth)
                            .offset(x: playheadX - playheadWidth / 2)
                    }
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
                        appState.seek(to: time)
                    case .ended:
                        break
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

    private var keptRegions: [Region] {
        appState.regions.filter { !$0.isBinned }
    }

    private var previewDuration: Double {
        keptRegions.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(geometry.size.width * appState.timelineZoom, geometry.size.width)

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

                    // Playhead in preview coordinates
                    if previewDuration > 0 {
                        let previewTime = convertToPreviewTime(appState.currentTime)
                        let playheadX = (previewTime / previewDuration) * contentWidth

                        Rectangle()
                            .fill(Color.red)
                            .frame(width: playheadWidth)
                            .offset(x: playheadX - playheadWidth / 2)
                    }
                }
                .frame(width: contentWidth, height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let previewTime = previewTimeFromPosition(value.location.x, width: contentWidth)
                            let sourceTime = convertFromPreviewTime(previewTime)
                            appState.seek(to: sourceTime)
                        }
                )
                .onContinuousHover { phase in
                    guard appState.skimmingEnabled else { return }
                    switch phase {
                    case .active(let location):
                        let previewTime = previewTimeFromPosition(location.x, width: contentWidth)
                        let sourceTime = convertFromPreviewTime(previewTime)
                        appState.seek(to: sourceTime)
                    case .ended:
                        break
                    }
                }
            }
        }
    }

    private func previewTimeFromPosition(_ x: CGFloat, width: CGFloat) -> Double {
        let proportion = x / width
        return max(0, min(proportion * previewDuration, previewDuration))
    }

    // Convert source time to preview time (collapsed timeline position)
    private func convertToPreviewTime(_ sourceTime: Double) -> Double {
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
    private func convertFromPreviewTime(_ previewTime: Double) -> Double {
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

    var body: some View {
        ZStack(alignment: .leading) {
            // Region backgrounds
            ForEach(appState.regions) { region in
                RegionBackground(
                    region: region,
                    totalDuration: appState.duration,
                    totalWidth: width,
                    height: height
                )
            }

            // Thumbnails
            ThumbnailStripView(width: width, height: height)

            // Region dividers
            ForEach(appState.regions.dropLast()) { region in
                let x = (region.endTime / appState.duration) * width

                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 2)
                    .offset(x: x - 1)
            }
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Preview Thumbnail Track (collapsed)

struct PreviewThumbnailTrackView: View {
    @EnvironmentObject var appState: AppState
    let width: CGFloat
    let height: CGFloat

    private var keptRegions: [Region] {
        appState.regions.filter { !$0.isBinned }
    }

    private var previewDuration: Double {
        keptRegions.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Thumbnails for each kept region, positioned contiguously
            PreviewThumbnailStripView(
                keptRegions: keptRegions,
                previewDuration: previewDuration,
                width: width,
                height: height
            )

            // Region dividers between kept regions
            if keptRegions.count > 1 {
                ForEach(Array(keptRegions.dropLast().enumerated()), id: \.element.id) { index, _ in
                    let previewTime = keptRegions.prefix(index + 1).reduce(0) { $0 + $1.duration }
                    let x = (previewTime / previewDuration) * width

                    Rectangle()
                        .fill(Color.green)
                        .frame(width: 2)
                        .offset(x: x - 1)
                }
            }
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
            generateThumbnailsIfNeeded()
        }
        .onChange(of: width) { _, _ in
            generateThumbnailsIfNeeded()
        }
    }

    private func generateThumbnailsIfNeeded() {
        // Only regenerate if URL or width changed significantly
        guard let url = appState.videoURL else {
            thumbnails = []
            lastGeneratedURL = nil
            return
        }

        let widthChanged = abs(width - lastGeneratedWidth) > 50
        let urlChanged = url != lastGeneratedURL

        guard urlChanged || widthChanged else { return }

        lastGeneratedURL = url
        lastGeneratedWidth = width

        generateThumbnails(url: url)
    }

    private func generateThumbnails(url: URL) {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: thumbnailWidth * 2, height: height * 2)

        let numberOfThumbnails = Int(ceil(width / thumbnailWidth))
        guard numberOfThumbnails > 0 && appState.duration > 0 else { return }

        let interval = appState.duration / Double(numberOfThumbnails)

        Task {
            var newThumbnails: [(time: Double, image: NSImage)] = []

            for i in 0..<numberOfThumbnails {
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

            await MainActor.run {
                self.thumbnails = newThumbnails
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
        let widthChanged = abs(width - lastGeneratedWidth) > 50

        guard idsChanged || widthChanged else { return }

        lastKeptRegionIds = currentIds
        lastGeneratedWidth = width

        generateThumbnails(url: url)
    }

    private func generateThumbnails(url: URL) {
        guard previewDuration > 0 else {
            thumbnails = []
            return
        }

        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: thumbnailWidth * 2, height: height * 2)

        let numberOfThumbnails = Int(ceil(width / thumbnailWidth))
        guard numberOfThumbnails > 0 else { return }

        let interval = previewDuration / Double(numberOfThumbnails)

        Task {
            var newThumbnails: [(time: Double, image: NSImage)] = []

            for i in 0..<numberOfThumbnails {
                // Calculate preview time, then convert to source time
                let previewTime = Double(i) * interval + interval / 2
                let sourceTime = convertFromPreviewTime(previewTime)
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

            await MainActor.run {
                self.thumbnails = newThumbnails
            }
        }
    }

    private func convertFromPreviewTime(_ previewTime: Double) -> Double {
        var remainingTime = previewTime

        for region in keptRegions {
            if remainingTime <= region.duration {
                return region.startTime + remainingTime
            }
            remainingTime -= region.duration
        }

        return keptRegions.last?.endTime ?? 0
    }
}

#Preview {
    TimelineView()
        .environmentObject(AppState.shared)
        .frame(width: 800, height: 120)
}
