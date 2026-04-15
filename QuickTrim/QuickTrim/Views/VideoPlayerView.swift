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
                    PlayerWaveformCanvas(
                        samples: data.samples,
                        playbackPosition: appState.duration > 0 ? appState.currentTime / appState.duration : 0,
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

        Task {
            do {
                // Use rough waveform for faster loading - same method as timeline for consistency
                let data = try await WaveformGenerator.generateRoughWaveform(
                    from: url,
                    totalSamples: 800  // Double resolution for player view
                )
                await MainActor.run {
                    self.waveformData = data
                    self.isLoading = false
                }
            } catch {
                print("Waveform generation failed: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

struct PlayerWaveformCanvas: View {
    let samples: [Float]
    let playbackPosition: Double  // 0.0 to 1.0
    let regions: [Region]
    let duration: Double

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let barWidth = max(1, size.width / CGFloat(samples.count))

            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * barWidth
                let normalizedTime = Double(index) / Double(max(1, samples.count)) * duration
                let barHeight = CGFloat(abs(sample)) * midY * 0.9

                // Determine if this sample is in a binned region
                let isBinned = regions.contains { region in
                    region.isBinned &&
                    normalizedTime >= region.startTime &&
                    normalizedTime < region.endTime
                }

                // Color based on playback position and binned status
                let normalizedPosition = CGFloat(index) / CGFloat(max(1, samples.count))
                let baseColor: Color = isBinned ? .red : .green
                let color: Color = normalizedPosition < playbackPosition
                    ? baseColor
                    : baseColor.opacity(0.4)

                // Draw symmetric bar
                let rect = CGRect(
                    x: x,
                    y: midY - barHeight,
                    width: max(barWidth - 0.5, 1),
                    height: barHeight * 2
                )
                context.fill(Path(rect), with: .color(color))
            }

            // Draw playhead line
            let playheadX = size.width * playbackPosition
            let playheadPath = Path { path in
                path.move(to: CGPoint(x: playheadX, y: 0))
                path.addLine(to: CGPoint(x: playheadX, y: size.height))
            }
            context.stroke(playheadPath, with: .color(.red), lineWidth: 2)
        }
    }
}

#Preview {
    VideoPlayerView()
        .environmentObject(AppState())
        .frame(width: 600, height: 400)
}
