//
//  TimelineView.swift
//  QuickTrim
//

import SwiftUI
import AVFoundation

struct TimelineView: View {
    @EnvironmentObject var appState: AppState
    @State private var thumbnailImages: [Double: NSImage] = [:]
    @State private var isDragging = false
    @State private var lastScrubTime: Double = 0

    private let timecodeHeight: CGFloat = 20
    private let thumbnailHeight: CGFloat = 60
    private let playheadWidth: CGFloat = 2

    var body: some View {
        VStack(spacing: 0) {
            // Zoom controls and time display
            HStack {
                // Current time readout
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .foregroundColor(.secondary)
                    Text(formatTimecode(appState.currentTime))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

                Spacer()

                // Scrubbing toggle
                Toggle(isOn: $appState.scrubbingEnabled) {
                    Label("Scrubbing", systemImage: "waveform")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Enable audio scrubbing (⌘⌥S)")

                // Preview mode toggle
                Toggle(isOn: $appState.previewModeEnabled) {
                    Label("Preview", systemImage: "eye")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Hide binned regions (⌘⌥P)")

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

            // Timeline content
            GeometryReader { geometry in
                let contentWidth = max(geometry.size.width * appState.timelineZoom, geometry.size.width)

                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            // Background
                            Rectangle()
                                .fill(Color(nsColor: .textBackgroundColor))

                            VStack(spacing: 0) {
                                // Timecode ruler
                                TimecodeRulerView(
                                    duration: appState.duration,
                                    width: contentWidth,
                                    zoom: appState.timelineZoom
                                )
                                .frame(height: timecodeHeight)

                                // Thumbnail track with regions
                                ThumbnailTrackView(
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
                                    .id("playhead")
                            }
                        }
                        .frame(width: contentWidth, height: geometry.size.height)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDragging = true
                                    let proportion = value.location.x / contentWidth
                                    let time = max(0, min(proportion * appState.duration, appState.duration))

                                    if appState.scrubbingEnabled {
                                        // Scrubbing mode: update playhead in real-time
                                        appState.seek(to: time)
                                    } else {
                                        // Non-scrubbing: just track position
                                        lastScrubTime = time
                                    }
                                }
                                .onEnded { value in
                                    isDragging = false
                                    let proportion = value.location.x / contentWidth
                                    let time = max(0, min(proportion * appState.duration, appState.duration))
                                    appState.seek(to: time)
                                }
                        )
                    }
                }
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

struct TimecodeRulerView: View {
    let duration: Double
    let width: CGFloat
    let zoom: Double

    var body: some View {
        Canvas { context, size in
            guard duration > 0 else { return }

            let pixelsPerSecond = width / duration

            // Determine tick interval based on zoom
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

            // Draw minor ticks
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

                // Draw time label for major ticks
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

struct ThumbnailTrackView: View {
    @EnvironmentObject var appState: AppState
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            // Region backgrounds
            ForEach(appState.regions) { region in
                if !appState.previewModeEnabled || !region.isBinned {
                    RegionBackground(
                        region: region,
                        totalDuration: appState.duration,
                        totalWidth: width,
                        height: height,
                        previewMode: appState.previewModeEnabled
                    )
                }
            }

            // Thumbnails (show all in normal mode, filter in preview mode)
            if appState.previewModeEnabled {
                PreviewThumbnailStripView(width: width, height: height)
            } else {
                ThumbnailStripView(width: width, height: height)
            }

            // Region dividers (hide in preview mode for binned regions)
            ForEach(appState.regions.dropLast()) { region in
                if !appState.previewModeEnabled || !region.isBinned {
                    let x = (region.endTime / appState.duration) * width

                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 2)
                        .offset(x: x - 1)
                }
            }
        }
        .frame(width: width, height: height)
    }
}

struct RegionBackground: View {
    let region: Region
    let totalDuration: Double
    let totalWidth: CGFloat
    let height: CGFloat
    var previewMode: Bool = false

    var body: some View {
        let startX = (region.startTime / totalDuration) * totalWidth
        let regionWidth = (region.duration / totalDuration) * totalWidth

        Rectangle()
            .fill(region.isBinned && !previewMode ? Color.red.opacity(0.3) : Color.clear)
            .frame(width: regionWidth, height: height)
            .offset(x: startX)
            .overlay(
                Group {
                    if region.isBinned && !previewMode {
                        // Strikethrough pattern for binned regions
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

struct ThumbnailStripView: View {
    @EnvironmentObject var appState: AppState
    @State private var thumbnails: [(time: Double, image: NSImage)] = []

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
            generateThumbnails()
        }
        .onChange(of: appState.videoURL) { _, _ in
            generateThumbnails()
        }
        .onChange(of: width) { _, _ in
            generateThumbnails()
        }
    }

    private func generateThumbnails() {
        guard let url = appState.videoURL else {
            thumbnails = []
            return
        }

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
                    // Create placeholder for failed thumbnails
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

struct PreviewThumbnailStripView: View {
    @EnvironmentObject var appState: AppState
    @State private var thumbnails: [(time: Double, image: NSImage, regionId: UUID)] = []

    let width: CGFloat
    let height: CGFloat

    private let thumbnailWidth: CGFloat = 80

    private var keptRegions: [Region] {
        appState.regions.filter { !$0.isBinned }
    }

    private var totalKeptDuration: Double {
        keptRegions.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(keptRegions) { region in
                let regionWidth = (region.duration / appState.duration) * width

                ForEach(thumbnailsForRegion(region), id: \.time) { thumbnail in
                    Image(nsImage: thumbnail.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: thumbnailWidth, height: height)
                        .clipped()
                }
            }
        }
        .onAppear {
            generateThumbnails()
        }
        .onChange(of: appState.videoURL) { _, _ in
            generateThumbnails()
        }
        .onChange(of: appState.regions) { _, _ in
            generateThumbnails()
        }
        .onChange(of: width) { _, _ in
            generateThumbnails()
        }
    }

    private func thumbnailsForRegion(_ region: Region) -> [(time: Double, image: NSImage)] {
        thumbnails.filter { $0.regionId == region.id }.map { ($0.time, $0.image) }
    }

    private func generateThumbnails() {
        guard let url = appState.videoURL else {
            thumbnails = []
            return
        }

        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: thumbnailWidth * 2, height: height * 2)

        Task {
            var newThumbnails: [(time: Double, image: NSImage, regionId: UUID)] = []

            for region in keptRegions {
                let regionWidth = (region.duration / appState.duration) * width
                let numberOfThumbnails = max(1, Int(ceil(regionWidth / thumbnailWidth)))
                let interval = region.duration / Double(numberOfThumbnails)

                for i in 0..<numberOfThumbnails {
                    let time = region.startTime + Double(i) * interval + interval / 2
                    let cmTime = CMTime(seconds: time, preferredTimescale: 600)

                    do {
                        let (cgImage, _) = try await imageGenerator.image(at: cmTime)
                        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: thumbnailWidth, height: height))
                        newThumbnails.append((time: time, image: nsImage, regionId: region.id))
                    } catch {
                        let placeholder = NSImage(size: NSSize(width: thumbnailWidth, height: height))
                        newThumbnails.append((time: time, image: placeholder, regionId: region.id))
                    }
                }
            }

            await MainActor.run {
                self.thumbnails = newThumbnails
            }
        }
    }
}

#Preview {
    TimelineView()
        .environmentObject(AppState.shared)
        .frame(width: 800, height: 120)
}
