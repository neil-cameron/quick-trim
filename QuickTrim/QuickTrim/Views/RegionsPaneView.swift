//
//  RegionsPaneView.swift
//  QuickTrim
//

import SwiftUI
import AVFoundation
import AppKit

struct RegionsPaneView: View {
    @EnvironmentObject var appState: AppState
    @State private var isOptionPressed = false
    @State private var showExportSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Regions")
                    .font(.headline)

                Spacer()

                Text("\(appState.regions.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Region list
            if appState.regions.isEmpty {
                VStack {
                    Spacer()
                    Text("No regions")
                        .foregroundColor(.secondary)
                    Text("Press M to mark a trim point")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(appState.regions.enumerated()), id: \.element.id) { index, region in
                            RegionRowView(
                                region: region,
                                index: index,
                                isRemoveModeEnabled: isOptionPressed
                            )
                        }
                    }
                    .padding(8)
                }
            }

            Divider()

            // Export button
            VStack(spacing: 8) {
                // Summary
                HStack {
                    let keptCount = appState.regions.filter { !$0.isBinned }.count
                    let binnedCount = appState.regions.filter { $0.isBinned }.count

                    Text("\(keptCount) kept")
                        .foregroundColor(.green)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text("\(binnedCount) binned")
                        .foregroundColor(.red)

                    Spacer()
                }
                .font(.caption)

                HStack(spacing: 8) {
                    Button(action: { appState.exportVideo() }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!appState.canExport)

                    Button(action: { showExportSettings.toggle() }) {
                        Image(systemName: "gearshape")
                    }
                    .controlSize(.large)
                    .popover(isPresented: $showExportSettings) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Export Options")
                                .font(.headline)

                            Toggle("No sound", isOn: $appState.exportRemoveAudio)
                                .disabled(appState.isAudioOnly)

                            Toggle("Transcode output", isOn: $appState.exportTranscode)
                                .disabled(appState.isAudioOnly)
                        }
                        .padding()
                        .frame(width: 200)
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .background(ModifierKeyMonitor(isOptionPressed: $isOptionPressed))
    }
}

struct RegionRowView: View {
    @EnvironmentObject var appState: AppState
    let region: Region
    let index: Int
    let isRemoveModeEnabled: Bool

    @State private var thumbnail: NSImage?

    private var isCurrentRegion: Bool {
        appState.currentRegionID == region.id
    }

    var body: some View {
        HStack(spacing: 10) {
            // Thumbnail or waveform preview
            ZStack {
                if appState.isAudioOnly {
                    // Show mini waveform for audio files
                    RegionWaveformPreview(region: region)
                        .frame(width: 60, height: 40)
                        .cornerRadius(4)
                } else if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 40)
                        .clipped()
                        .cornerRadius(4)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 40)
                        .cornerRadius(4)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.5)
                        )
                }

                if region.isBinned {
                    Rectangle()
                        .fill(Color.red.opacity(0.5))
                        .frame(width: 60, height: 40)
                        .cornerRadius(4)

                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                        .font(.title3)
                }
            }
            .onAppear {
                if !appState.isAudioOnly {
                    loadThumbnail()
                }
            }

            // Region info
            VStack(alignment: .leading, spacing: 4) {
                Text("Region \(index + 1)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(region.isBinned ? .secondary : .primary)

                Text(formatTimeRange())
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)

                Text(formatDuration())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .strikethrough(region.isBinned, color: .red)

            Spacer()

            // Bin toggle button, or start-marker removal while Option is held.
            Button(action: {
                if isRemoveModeEnabled || NSEvent.modifierFlags.contains(.option) {
                    appState.removeStartMarker(for: region)
                } else {
                    appState.toggleBin(for: region)
                }
            }) {
                Image(systemName: actionIconName)
                    .foregroundColor(actionIconColor)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(isRemoveModeEnabled && !canRemoveStartMarker)
            .help(actionHelpText)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(rowBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(rowBorderColor, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Seek to start of region when clicked
            appState.seek(to: region.startTime)
        }
    }

    private var canRemoveStartMarker: Bool {
        appState.canRemoveStartMarker(for: region)
    }

    private var actionIconName: String {
        if isRemoveModeEnabled {
            return canRemoveStartMarker ? "minus.circle.fill" : "minus.circle"
        }

        return region.isBinned ? "trash.fill" : "trash"
    }

    private var actionIconColor: Color {
        if isRemoveModeEnabled {
            return canRemoveStartMarker ? .orange : .secondary.opacity(0.45)
        }

        return region.isBinned ? .red : .secondary
    }

    private var actionHelpText: String {
        if isRemoveModeEnabled {
            return canRemoveStartMarker
                ? "Remove start marker and merge with previous region"
                : "First region has no start marker to remove"
        }

        return region.isBinned ? "Restore region" : "Bin region"
    }

    private var rowBackgroundColor: Color {
        if isCurrentRegion {
            return Color.accentColor.opacity(region.isBinned ? 0.18 : 0.14)
        }

        return region.isBinned ? Color.red.opacity(0.1) : Color(nsColor: .controlBackgroundColor)
    }

    private var rowBorderColor: Color {
        if isCurrentRegion {
            return Color.accentColor
        }

        return region.isBinned ? Color.red.opacity(0.3) : Color.clear
    }

    private func formatTimeRange() -> String {
        "\(formatTime(region.startTime)) → \(formatTime(region.endTime))"
    }

    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let frames = Int((time - floor(time)) * appState.frameRate)
        return String(format: "%02d:%02d:%02d", minutes, seconds, frames)
    }

    private func formatDuration() -> String {
        let duration = region.duration
        if duration >= 60 {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        } else {
            return String(format: "%.1fs", duration)
        }
    }

    private func loadThumbnail() {
        guard let url = appState.videoURL else { return }

        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 120, height: 80)

        let time = CMTime(seconds: region.middleTime, preferredTimescale: 600)

        Task {
            do {
                let (cgImage, _) = try await imageGenerator.image(at: time)
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 60, height: 40))

                await MainActor.run {
                    self.thumbnail = nsImage
                }
            } catch {
                print("Failed to generate thumbnail: \(error)")
            }
        }
    }
}

struct ModifierKeyMonitor: NSViewRepresentable {
    @Binding var isOptionPressed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isOptionPressed: $isOptionPressed)
    }

    func makeNSView(context: Context) -> ModifierKeyMonitorView {
        let view = ModifierKeyMonitorView()
        view.onOptionChanged = context.coordinator.setOptionPressed
        return view
    }

    func updateNSView(_ nsView: ModifierKeyMonitorView, context: Context) {
        context.coordinator.isOptionPressed = $isOptionPressed
        nsView.onOptionChanged = context.coordinator.setOptionPressed
        nsView.updateFromCurrentModifiers()
    }

    static func dismantleNSView(_ nsView: ModifierKeyMonitorView, coordinator: Coordinator) {
        nsView.stopMonitoring()
    }

    final class Coordinator {
        var isOptionPressed: Binding<Bool>

        init(isOptionPressed: Binding<Bool>) {
            self.isOptionPressed = isOptionPressed
        }

        func setOptionPressed(_ pressed: Bool) {
            guard isOptionPressed.wrappedValue != pressed else { return }
            isOptionPressed.wrappedValue = pressed
        }
    }
}

final class ModifierKeyMonitorView: NSView {
    var onOptionChanged: ((Bool) -> Void)?

    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            stopMonitoring()
            onOptionChanged?(false)
        } else {
            startMonitoring()
            updateFromCurrentModifiers()
        }
    }

    deinit {
        stopMonitoring()
    }

    func updateFromCurrentModifiers() {
        publishOptionState(from: NSEvent.modifierFlags)
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func startMonitoring() {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .leftMouseDown, .leftMouseUp]) { [weak self] event in
            self?.publishOptionState(from: event.modifierFlags)
            return event
        }
    }

    private func publishOptionState(from modifierFlags: NSEvent.ModifierFlags) {
        let pressed = modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.option)

        DispatchQueue.main.async { [weak self] in
            self?.onOptionChanged?(pressed)
        }
    }
}

// MARK: - Region Waveform Preview (for audio files)

struct RegionWaveformPreview: View {
    let region: Region

    var body: some View {
        Canvas { context, size in
            let color: Color = region.isBinned ? .red : .green

            // Draw a simple waveform representation
            let midY = size.height / 2
            let barCount = 15
            let barWidth = size.width / CGFloat(barCount)

            for i in 0..<barCount {
                // Generate pseudo-random heights based on region timing for visual variety
                let seed = (region.startTime + Double(i) * 0.1).truncatingRemainder(dividingBy: 1.0)
                let height = CGFloat(0.3 + seed * 0.6) * midY

                let rect = CGRect(
                    x: CGFloat(i) * barWidth + 1,
                    y: midY - height,
                    width: barWidth - 2,
                    height: height * 2
                )
                context.fill(Path(rect), with: .color(color.opacity(0.8)))
            }
        }
        .background(Color.black.opacity(0.3))
    }
}

#Preview {
    RegionsPaneView()
        .environmentObject(AppState())
        .frame(width: 280, height: 400)
}
