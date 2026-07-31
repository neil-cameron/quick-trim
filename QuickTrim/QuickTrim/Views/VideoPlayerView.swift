//
//  VideoPlayerView.swift
//  QuickTrim
//

import SwiftUI
import AVKit

struct VideoPlayerView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if let player = appState.player {
                if appState.isAudioOnly {
                    // Show waveform visualization for audio files
                    AudioVisualizationView()
                } else if appState.isCropModeActive {
                    // Full video with crop overlay
                    ZStack {
                        AVPlayerContainerView(player: player)
                        CropOverlayView()
                    }
                } else if appState.hasCrop {
                    // Cropped video display
                    CroppedVideoView(player: player)
                } else {
                    AVPlayerContainerView(player: player)
                }
            } else {
                Rectangle()
                    .fill(Color.black)
                    .overlay(
                        Text("No media loaded")
                            .foregroundColor(.gray)
                    )
            }

            // Crop controls panel (shown in crop mode)
            if appState.isCropModeActive && !appState.isAudioOnly {
                Divider()
                CropControlsPanel()
            }

            // Custom controls bar
            HStack(spacing: 16) {
                // Play/Pause button
                Button(action: {
                    appState.togglePlayPause()
                }) {
                    Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(appState.player == nil)

                // Current time display
                Text(formatTime(appState.currentTime))
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 80, alignment: .leading)

                Text("/")
                    .foregroundColor(.secondary)

                Text(formatTime(appState.duration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)

                Spacer()

                // Frame stepping buttons
                HStack(spacing: 8) {
                    Button(action: { appState.stepFrame(forward: false) }) {
                        Image(systemName: "backward.frame.fill")
                    }
                    .buttonStyle(.plain)
                    .help("Previous frame (←)")

                    Button(action: { appState.stepFrame(forward: true) }) {
                        Image(systemName: "forward.frame.fill")
                    }
                    .buttonStyle(.plain)
                    .help("Next frame (→)")
                }
                .disabled(appState.player == nil)

                // Crop toggle (video only)
                if !appState.isAudioOnly && appState.player != nil {
                    Divider()
                        .frame(height: 20)

                    Toggle(isOn: $appState.isCropModeActive) {
                        Image(systemName: "crop")
                    }
                    .toggleStyle(.button)
                    .help("Crop video")
                }

                Divider()
                    .frame(height: 20)

                // Playback speed
                PlaybackSpeedPicker()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite && time >= 0 else { return "00:00:00" }

        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let frames = Int((time - floor(time)) * appState.frameRate)

        if hours > 0 {
            return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
        } else {
            return String(format: "%02d:%02d:%02d", minutes, seconds, frames)
        }
    }
}

struct AVPlayerContainerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

struct PlaybackSpeedPicker: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSpeed: Float = 1.0

    private let speeds: [Float] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        Picker("Speed", selection: $selectedSpeed) {
            ForEach(speeds, id: \.self) { speed in
                Text(speedLabel(speed))
                    .tag(speed)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 80)
        .onChange(of: selectedSpeed) { _, newValue in
            appState.player?.rate = appState.isPlaying ? newValue : 0
            appState.player?.defaultRate = newValue
        }
    }

    private func speedLabel(_ speed: Float) -> String {
        if speed == 1.0 {
            return "1x"
        } else {
            return String(format: "%.2gx", speed)
        }
    }
}

// MARK: - Audio Visualization View

struct AudioVisualizationView: View {
    @EnvironmentObject var appState: AppState
    @State private var waveformData: WaveformData?
    @State private var isLoading = true
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Rectangle()
                    .fill(Color.black)

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading waveform...")
                            .foregroundColor(.gray)
                    }
                } else if let data = waveformData {
                    // Static waveform centered in view
                    PlayerWaveformView(
                        data: data,
                        currentTime: appState.currentTime,
                        regions: appState.regions,
                        duration: appState.duration
                    )
                    .padding(20)
                } else {
                    // Fallback: audio icon
                    VStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.system(size: 80))
                            .foregroundColor(.green)
                        Text("Audio File")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear {
            loadWaveform()
        }
        .onChange(of: appState.videoURL) { _, _ in
            loadWaveform()
        }
    }

    private func loadWaveform() {
        guard let url = appState.videoURL else { return }
        isLoading = true
        waveformData = nil
        loadTask?.cancel()

        loadTask = Task {
            do {
                let data = try await WaveformCache.shared.waveform(for: url)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.waveformData = data
                    self.isLoading = false
                }
            } catch {
                if Task.isCancelled { return }
                print("Waveform generation failed: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

/// Full-size player waveform: played portion at full brightness, upcoming
/// portion dimmed, binned regions red, with a playhead line.
///
/// The waveform itself is static during playback — only the dim overlay and
/// playhead move — so the peak cache isn't re-aggregated 20x/second.
struct PlayerWaveformView: View {
    let data: WaveformData
    let currentTime: Double
    let regions: [Region]
    let duration: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let playheadX = duration > 0
                ? CGFloat(currentTime / duration) * width
                : 0

            ZStack(alignment: .topLeading) {
                StaticPlayerWaveform(
                    data: data,
                    regions: regions,
                    duration: duration,
                    width: width
                )
                .equatable()

                // Dim the unplayed portion
                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: max(0, width - playheadX), height: geometry.size.height)
                    .offset(x: playheadX)

                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2, height: geometry.size.height)
                    .offset(x: playheadX - 1)
            }
        }
    }
}

/// Equatable wrapper so SwiftUI skips redrawing the waveform canvas when
/// only the playback position changed.
struct StaticPlayerWaveform: View, Equatable {
    let data: WaveformData
    let regions: [Region]
    let duration: Double
    let width: CGFloat

    static func == (lhs: StaticPlayerWaveform, rhs: StaticPlayerWaveform) -> Bool {
        lhs.duration == rhs.duration
            && lhs.width == rhs.width
            && lhs.regions == rhs.regions
            && lhs.data.bucketCount == rhs.data.bucketCount
    }

    var body: some View {
        WaveformCanvasView(
            data: data,
            segments: WaveformSegment.linearTimeline(
                duration: duration,
                width: width,
                regions: regions
            ),
            targetFill: WaveformFill.player
        )
    }
}

#Preview {
    VideoPlayerView()
        .environmentObject(AppState())
        .frame(width: 600, height: 400)
}
