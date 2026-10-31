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
                        .monospacedDigit()
                        .frame(width: 48)
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

    /// Logarithmic mapping: 1x...50x spread evenly, so 100–1000% isn't
    /// crammed into the first fifth of the track.
    private var logZoom: Binding<Double> {
        Binding(
            get: { log(max(zoom, 1)) / log(AppState.maxTimelineZoom) },
            set: { zoom = pow(AppState.maxTimelineZoom, $0) }
        )
    }

    var body: some View {
        Slider(value: logZoom, in: 0...1)
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

// MARK: - Scroll Anchors

/// Invisible views laid across the timeline so ScrollViewReader can scroll
/// to a position. Spacing scales with zoom (~100pt apart) so centring on the
/// playhead stays precise at 5000%.
enum ScrollAnchors {
    static func count(for contentWidth: CGFloat) -> Int {
        max(100, min(2_000, Int(contentWidth / 100)))
    }

    /// Anchor index for a 0...1 position along the timeline.
    static func index(for position: Double, contentWidth: CGFloat) -> Int {
        let count = count(for: contentWidth)
        return min(count - 1, max(0, Int(position * Double(count))))
    }
}

// MARK: - Normal Timeline (full video)

struct NormalTimelineContent: View {
    @EnvironmentObject var appState: AppState
    let timecodeHeight: CGFloat
    let playheadWidth: CGFloat

    @State private var hoverX: CGFloat?
    @State private var isOptionPressed = false
    @State private var draggingMarkerIndex: Int?
    @State private var hoveredDragHandle: Int?

    private static let coordinateSpaceName = "normalTimelineContent"

    /// How close (in points) the pointer must be to a marker to target it.
    private let markerHitRadius: CGFloat = 10

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

                        // Region dividers (yellow vertical lines at trim points);
                        // orange while hovered for dragging or being dragged
                        if appState.regions.count > 1 && appState.duration > 0 {
                            ForEach(Array(appState.regions.dropLast().enumerated()), id: \.element.id) { index, region in
                                let x = (region.endTime / appState.duration) * contentWidth
                                let isActive = draggingMarkerIndex == index
                                    || (hoveredDragHandle == index && !isOptionPressed)
                                Rectangle()
                                    .fill(isActive ? Color.orange : Color.yellow)
                                    .frame(width: isActive ? 3 : 2, height: geometry.size.height)
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
                            ForEach(0..<ScrollAnchors.count(for: contentWidth), id: \.self) { index in
                                Color.clear
                                    .frame(width: contentWidth / CGFloat(ScrollAnchors.count(for: contentWidth)))
                                    .id("segment\(index)")
                            }
                        }
                        .allowsHitTesting(false)

                        // Drag handles: a 12pt grab zone around each marker.
                        // Hidden while Option is held (that's delete mode).
                        if appState.regions.count > 1 && appState.duration > 0 && !isOptionPressed {
                            ForEach(0..<(appState.regions.count - 1), id: \.self) { index in
                                Color.clear
                                    .contentShape(Rectangle())
                                    .frame(width: 12, height: geometry.size.height)
                                    .position(
                                        x: markerX(index, contentWidth: contentWidth),
                                        y: geometry.size.height / 2
                                    )
                                    .onHover { inside in
                                        if inside {
                                            hoveredDragHandle = index
                                            NSCursor.resizeLeftRight.push()
                                        } else {
                                            if hoveredDragHandle == index { hoveredDragHandle = nil }
                                            NSCursor.pop()
                                        }
                                    }
                                    .gesture(
                                        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpaceName))
                                            .onChanged { value in
                                                if draggingMarkerIndex == nil {
                                                    draggingMarkerIndex = index
                                                    appState.player?.pause()
                                                    appState.stopSkimming()
                                                    appState.beginMarkerDrag()
                                                }
                                                let time = timeFromPosition(value.location.x, width: contentWidth)
                                                // Show the frame at the cut while dragging
                                                if let applied = appState.moveMarker(at: index, to: time) {
                                                    appState.seek(to: applied)
                                                }
                                            }
                                            .onEnded { _ in
                                                draggingMarkerIndex = nil
                                            }
                                    )
                                    .help("Drag to move this marker")
                            }
                        }

                        // Option-hover near a marker: highlight it and offer delete
                        if let markerIndex = hoveredMarkerIndex(contentWidth: contentWidth) {
                            let x = markerX(markerIndex, contentWidth: contentWidth)

                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 2, height: geometry.size.height)
                                .position(x: x, y: geometry.size.height / 2)
                                .allowsHitTesting(false)

                            Button {
                                deleteMarker(markerIndex)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .red)
                                    .shadow(radius: 1)
                            }
                            .buttonStyle(.plain)
                            .help("Delete marker")
                            .position(x: x, y: timecodeHeight + 14)
                        }
                    }
                    .frame(width: contentWidth, height: geometry.size.height)
                    .coordinateSpace(name: Self.coordinateSpaceName)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard draggingMarkerIndex == nil else { return }
                                let time = timeFromPosition(value.location.x, width: contentWidth)
                                appState.seek(to: time)
                            }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverX = location.x
                            // Option = marker-editing mode, or mid-drag: don't
                            // let skimming move the playhead
                            guard appState.skimmingEnabled, !isOptionPressed,
                                  draggingMarkerIndex == nil else { return }
                            let time = timeFromPosition(location.x, width: contentWidth)
                            appState.skimTo(time: time)
                        case .ended:
                            hoverX = nil
                            appState.stopSkimming()
                        }
                    }
                }
                .background(ModifierKeyMonitor(isOptionPressed: $isOptionPressed))
                .onChange(of: isOptionPressed) { _, pressed in
                    if pressed { appState.stopSkimming() }
                }
                .onChange(of: appState.currentTime) { _, newTime in
                    if appState.capturePlayheadEnabled && appState.duration > 0 {
                        let index = ScrollAnchors.index(for: newTime / appState.duration, contentWidth: contentWidth)
                        withAnimation(.linear(duration: 0.1)) {
                            scrollProxy.scrollTo("segment\(index)", anchor: .center)
                        }
                    }
                }
                .onChange(of: appState.capturePlayheadEnabled) { _, newValue in
                    if newValue && appState.duration > 0 {
                        let index = ScrollAnchors.index(for: appState.currentTime / appState.duration, contentWidth: contentWidth)
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("segment\(index)", anchor: .center)
                        }
                    }
                }
                .onChange(of: appState.timelineZoom) { _, newZoom in
                    // Zooming grows the content under a fixed scroll offset,
                    // which would land you somewhere unrelated — keep the
                    // playhead in view instead.
                    guard appState.duration > 0 else { return }
                    let newWidth = max(geometry.size.width * newZoom, geometry.size.width)
                    let index = ScrollAnchors.index(for: appState.currentTime / appState.duration, contentWidth: newWidth)
                    DispatchQueue.main.async {
                        scrollProxy.scrollTo("segment\(index)", anchor: .center)
                    }
                }
            }
        }
    }

    private func timeFromPosition(_ x: CGFloat, width: CGFloat) -> Double {
        let proportion = x / width
        return max(0, min(proportion * appState.duration, appState.duration))
    }

    // MARK: Marker deletion (Option + hover)

    /// Marker i sits between regions[i] and regions[i + 1].
    private func markerX(_ index: Int, contentWidth: CGFloat) -> CGFloat {
        CGFloat(appState.regions[index].endTime / appState.duration) * contentWidth
    }

    /// The marker nearest the pointer, if Option is held and it's within reach.
    private func hoveredMarkerIndex(contentWidth: CGFloat) -> Int? {
        guard isOptionPressed,
              let hoverX,
              appState.duration > 0,
              appState.regions.count > 1 else { return nil }

        let nearest = (0..<(appState.regions.count - 1)).min {
            abs(markerX($0, contentWidth: contentWidth) - hoverX)
                < abs(markerX($1, contentWidth: contentWidth) - hoverX)
        }
        guard let nearest,
              abs(markerX(nearest, contentWidth: contentWidth) - hoverX) <= markerHitRadius
        else { return nil }
        return nearest
    }

    private func deleteMarker(_ index: Int) {
        guard index + 1 < appState.regions.count else { return }
        // Removing region i+1's start marker merges it with region i
        appState.removeStartMarker(for: appState.regions[index + 1])
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
                            ForEach(0..<ScrollAnchors.count(for: contentWidth), id: \.self) { index in
                                Color.clear
                                    .frame(width: contentWidth / CGFloat(ScrollAnchors.count(for: contentWidth)))
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
                        let index = ScrollAnchors.index(for: previewTime / previewDuration, contentWidth: contentWidth)
                        withAnimation(.linear(duration: 0.1)) {
                            scrollProxy.scrollTo("previewSegment\(index)", anchor: .center)
                        }
                    }
                }
                .onChange(of: appState.capturePlayheadEnabled) { _, newValue in
                    if newValue && previewDuration > 0 {
                        let previewTime = appState.convertToPreviewTime(appState.currentTime)
                        let index = ScrollAnchors.index(for: previewTime / previewDuration, contentWidth: contentWidth)
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("previewSegment\(index)", anchor: .center)
                        }
                    }
                }
                .onChange(of: appState.timelineZoom) { _, newZoom in
                    // Keep the playhead in view when zooming (see normal timeline)
                    guard previewDuration > 0 else { return }
                    let newWidth = max(geometry.size.width * newZoom, geometry.size.width)
                    let previewTime = appState.convertToPreviewTime(appState.currentTime)
                    let index = ScrollAnchors.index(for: previewTime / previewDuration, contentWidth: newWidth)
                    DispatchQueue.main.async {
                        scrollProxy.scrollTo("previewSegment\(index)", anchor: .center)
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

    /// Candidate label intervals in seconds, from frame-ish detail up to hours,
    /// so any duration/zoom combination finds a readable spacing.
    private static let niceIntervals: [Double] = [
        0.1, 0.2, 0.5,
        1, 2, 5, 10, 15, 30,
        60, 120, 300, 600, 900, 1800,
        3600, 7200, 14400
    ]

    var body: some View {
        Canvas { context, size in
            guard duration > 0 else { return }

            let pixelsPerSecond = width / duration

            // Smallest interval whose labels stay comfortably apart.
            let minLabelSpacing: CGFloat = 90
            let majorInterval = Self.niceIntervals.first {
                CGFloat($0) * pixelsPerSecond >= minLabelSpacing
            } ?? Self.niceIntervals.last!

            // Densest minor subdivision that keeps ticks at least ~10pt apart.
            let minorTicksPerMajor = [5, 4, 3, 2, 1].first {
                CGFloat(majorInterval / Double($0)) * pixelsPerSecond >= 10
            } ?? 1

            let minorInterval = majorInterval / Double(minorTicksPerMajor)

            var tickIndex = 0
            while true {
                let time = Double(tickIndex) * minorInterval
                if time > duration { break }

                let x = (time / duration) * width
                let isMajor = tickIndex % minorTicksPerMajor == 0

                let tickHeight: CGFloat = isMajor ? 10 : 5
                let tickPath = Path { path in
                    path.move(to: CGPoint(x: x, y: size.height - tickHeight))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }

                context.stroke(tickPath, with: .color(.secondary.opacity(0.5)), lineWidth: 1)

                if isMajor {
                    let label = formatTimeLabel(time, showTenths: majorInterval < 1)
                    let text = Text(label)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)

                    context.draw(text, at: CGPoint(x: x, y: 6), anchor: .top)
                }

                tickIndex += 1
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func formatTimeLabel(_ time: Double, showTenths: Bool) -> String {
        // Round to tenths first so e.g. 59.96s can't render as "0:60.0".
        let totalTenths = Int((time * 10).rounded())
        let totalSeconds = totalTenths / 10
        let tenths = totalTenths % 10
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        let base = hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
        return showTenths ? "\(base).\(tenths)" : base
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
            } else if appState.hasAudioTrack {
                // Video with audio: frame thumbnails with waveform beneath
                VStack(alignment: .leading, spacing: 0) {
                    ThumbnailStripView(
                        width: width,
                        height: height - statusBarHeight - VideoWaveformLayout.stripHeight
                    )
                    WaveformStripView(width: width, height: VideoWaveformLayout.stripHeight)
                }
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
            } else if appState.hasAudioTrack {
                // Video with audio: frame thumbnails with waveform beneath
                VStack(alignment: .leading, spacing: 0) {
                    PreviewThumbnailStripView(
                        keptRegions: keptRegions,
                        previewDuration: previewDuration,
                        width: width,
                        height: height - statusBarHeight - VideoWaveformLayout.stripHeight
                    )
                    PreviewWaveformStripView(
                        keptRegions: keptRegions,
                        previewDuration: previewDuration,
                        width: width,
                        height: VideoWaveformLayout.stripHeight
                    )
                }
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

// MARK: - Thumbnail Layout

enum ThumbnailLayout {
    /// Preferred on-screen width of one filmstrip frame.
    static let targetWidth: CGFloat = 80
    /// Upper bound on frames per strip: deep zoom (up to 50x) would otherwise
    /// ask for 1,000+ frames per zoom step. Beyond this, tiles widen instead.
    static let maxCount = 300

    static func count(for width: CGFloat) -> Int {
        min(Int(ceil(width / targetWidth)), maxCount)
    }
}

// MARK: - Thumbnail Strip (Normal mode)

struct ThumbnailStripView: View {
    @EnvironmentObject var appState: AppState
    @State private var thumbnails: [(time: Double, image: NSImage)] = []
    @State private var lastGeneratedURL: URL?
    @State private var lastGeneratedCount = 0
    @State private var lastGeneratedDuration: Double = 0
    @State private var generationTask: Task<Void, Never>?

    let width: CGFloat
    let height: CGFloat

    private let thumbnailWidth = ThumbnailLayout.targetWidth

    var body: some View {
        let tileWidth = width / CGFloat(max(1, thumbnails.count))
        HStack(spacing: 0) {
            ForEach(thumbnails, id: \.time) { thumbnail in
                Image(nsImage: thumbnail.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: tileWidth, height: height)
                    .clipped()
            }
        }
        // Tiles divide the width exactly; the clamp is a safety net so the
        // strip can never widen its container and misalign region overlays.
        .frame(width: width, height: height, alignment: .leading)
        .clipped()
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

        let countChanged = ThumbnailLayout.count(for: width) != lastGeneratedCount
        let urlChanged = url != lastGeneratedURL
        let durationChanged = lastGeneratedDuration == 0 && appState.duration > 0
        let needsData = thumbnails.isEmpty

        guard urlChanged || countChanged || durationChanged || needsData else { return }

        lastGeneratedURL = url
        lastGeneratedDuration = appState.duration
        // Don't update lastGeneratedCount yet — only on successful completion
        let capturedWidth = width

        generateThumbnails(url: url, capturedWidth: capturedWidth)
    }

    private func generateThumbnails(url: URL, capturedWidth: CGFloat) {
        generationTask?.cancel()

        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: thumbnailWidth * 2, height: height * 2)

        let numberOfThumbnails = ThumbnailLayout.count(for: capturedWidth)
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
                    self.lastGeneratedCount = numberOfThumbnails
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
    @State private var lastGeneratedCount = 0
    @State private var generationTask: Task<Void, Never>?

    let keptRegions: [Region]
    let previewDuration: Double
    let width: CGFloat
    let height: CGFloat

    private let thumbnailWidth = ThumbnailLayout.targetWidth

    var body: some View {
        let tileWidth = width / CGFloat(max(1, thumbnails.count))
        HStack(spacing: 0) {
            ForEach(thumbnails, id: \.time) { thumbnail in
                Image(nsImage: thumbnail.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: tileWidth, height: height)
                    .clipped()
            }
        }
        // Same width clamp as ThumbnailStripView.
        .frame(width: width, height: height, alignment: .leading)
        .clipped()
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
        let countChanged = ThumbnailLayout.count(for: width) != lastGeneratedCount
        let needsData = thumbnails.isEmpty

        guard idsChanged || countChanged || needsData else { return }

        lastKeptRegionIds = currentIds
        // Don't update lastGeneratedCount yet — only on successful completion
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

        let numberOfThumbnails = ThumbnailLayout.count(for: capturedWidth)
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
                    self.lastGeneratedCount = numberOfThumbnails
                }
            }
        }
    }
}

// MARK: - Waveform Strip (Normal mode)

/// Timeline waveform for the full duration. Data comes from the shared
/// decode-once WaveformCache, so zoom/width changes only redraw — they
/// never re-read the file.
struct WaveformStripView: View {
    @EnvironmentObject var appState: AppState
    @State private var waveformData: WaveformData?
    @State private var loadTask: Task<Void, Never>?

    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            if let data = waveformData {
                WaveformCanvasView(
                    data: data,
                    segments: WaveformSegment.linearTimeline(
                        duration: appState.duration,
                        width: width,
                        regions: appState.regions
                    )
                )
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: width, height: height)
        .onAppear {
            loadWaveform()
        }
        .onChange(of: appState.videoURL) { _, _ in
            waveformData = nil
            loadWaveform()
        }
    }

    private func loadWaveform() {
        guard let url = appState.videoURL else { return }
        loadTask?.cancel()

        let capturedDuration = appState.duration
        loadTask = Task {
            let data: WaveformData
            do {
                data = try await WaveformCache.shared.waveform(for: url)
            } catch {
                if Task.isCancelled { return }
                print("Waveform generation failed: \(error)")
                data = .silence(duration: capturedDuration)
            }
            if !Task.isCancelled {
                await MainActor.run {
                    self.waveformData = data
                }
            }
        }
    }
}

// MARK: - Preview Waveform Strip (collapsed mode)

/// Waveform for preview mode: kept regions rendered contiguously from the
/// same shared peak cache (no re-decode when regions change).
struct PreviewWaveformStripView: View {
    @EnvironmentObject var appState: AppState
    @State private var waveformData: WaveformData?
    @State private var loadTask: Task<Void, Never>?

    let keptRegions: [Region]
    let previewDuration: Double
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            if let data = waveformData {
                WaveformCanvasView(
                    data: data,
                    segments: WaveformSegment.previewTimeline(
                        keptRegions: keptRegions,
                        width: width
                    )
                )
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: width, height: height)
        .onAppear {
            loadWaveform()
        }
        .onChange(of: appState.videoURL) { _, _ in
            waveformData = nil
            loadWaveform()
        }
    }

    private func loadWaveform() {
        guard let url = appState.videoURL else { return }
        loadTask?.cancel()

        let capturedDuration = previewDuration
        loadTask = Task {
            let data: WaveformData
            do {
                data = try await WaveformCache.shared.waveform(for: url)
            } catch {
                if Task.isCancelled { return }
                print("Waveform generation failed: \(error)")
                data = .silence(duration: capturedDuration)
            }
            if !Task.isCancelled {
                await MainActor.run {
                    self.waveformData = data
                }
            }
        }
    }
}

#Preview {
    TimelineView()
        .environmentObject(AppState())
        .frame(width: 800, height: 120)
}
