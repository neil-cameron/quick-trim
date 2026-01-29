//
//  RegionsPaneView.swift
//  QuickTrim
//

import SwiftUI
import AVFoundation

struct RegionsPaneView: View {
    @EnvironmentObject var appState: AppState

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
                            RegionRowView(region: region, index: index)
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
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

struct RegionRowView: View {
    @EnvironmentObject var appState: AppState
    let region: Region
    let index: Int

    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            // Thumbnail
            ZStack {
                if let thumbnail = thumbnail {
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
                loadThumbnail()
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

            // Bin toggle button
            Button(action: {
                appState.toggleBin(for: region)
            }) {
                Image(systemName: region.isBinned ? "trash.fill" : "trash")
                    .foregroundColor(region.isBinned ? .red : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(region.isBinned ? "Restore region" : "Bin region")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(region.isBinned ? Color.red.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(region.isBinned ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Seek to middle of region when clicked
            appState.seek(to: region.middleTime)
        }
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

#Preview {
    RegionsPaneView()
        .environmentObject(AppState.shared)
        .frame(width: 280, height: 400)
}
