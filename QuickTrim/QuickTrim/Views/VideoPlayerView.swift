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
                VideoPlayer(player: player)
                    .onAppear {
                        // Ensure video controls are visible
                    }
            } else {
                Rectangle()
                    .fill(Color.black)
                    .overlay(
                        Text("No video loaded")
                            .foregroundColor(.gray)
                    )
            }

            // Custom controls bar
            HStack(spacing: 16) {
                // Play/Pause button
                Button(action: {
                    if appState.isPlaying {
                        appState.player?.pause()
                    } else {
                        appState.player?.play()
                    }
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
        } else if speed < 1.0 {
            return String(format: "%.2gx", speed)
        } else {
            return String(format: "%.2gx", speed)
        }
    }
}

#Preview {
    VideoPlayerView()
        .environmentObject(AppState.shared)
        .frame(width: 600, height: 400)
}
