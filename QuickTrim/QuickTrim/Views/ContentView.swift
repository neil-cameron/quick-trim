//
//  ContentView.swift
//  QuickTrim
//

import SwiftUI
import AVKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var timelineHeight: CGFloat = 120

    private let regionsPaneWidth: CGFloat = 280

    var body: some View {
        ZStack {
            if appState.videoURL != nil {
                mainLayout
            } else {
                DropZoneView()
            }

            if appState.isExporting {
                ExportProgressOverlay(progress: appState.exportProgress)
            }

            if appState.showCloseConfirmation {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onAppear {
                        appState.confirmClose()
                    }
            }
        }
        .background(KeyEventHandler())
    }

    var mainLayout: some View {
        VStack(spacing: 0) {
            // Top section: Video + Regions
            HStack(spacing: 0) {
                // Video player pane
                VideoPlayerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // Regions pane
                RegionsPaneView()
                    .frame(width: regionsPaneWidth)
            }

            Divider()

            // Timeline at bottom
            TimelineView()
                .frame(height: timelineHeight)
        }
    }
}

struct DropZoneView: View {
    @EnvironmentObject var appState: AppState
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "film")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Drop a video file here")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("or")
                .foregroundColor(.secondary)

            Button("Open Video...") {
                appState.showOpenPanel()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [10])
                )
                .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.5))
                .padding(40)
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }

            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let url = url {
                    DispatchQueue.main.async {
                        appState.openVideo(url: url)
                    }
                }
            }
            return true
        }
    }
}

struct ExportProgressOverlay: View {
    let progress: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Exporting...")
                    .font(.headline)

                ProgressView(value: progress)
                    .frame(width: 200)

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThickMaterial)
            )
        }
    }
}

struct KeyEventHandler: NSViewRepresentable {
    func makeNSView(context: Context) -> KeyEventView {
        let view = KeyEventView()
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyEventView, context: Context) {}
}

class KeyEventView: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let appState = AppState.shared
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case 49: // Space bar
            if modifiers.isEmpty {
                appState.togglePlayPause()
            } else {
                super.keyDown(with: event)
            }
        case 123: // Left arrow
            if modifiers.contains([.command, .shift]) {
                // Cmd+Shift+Left: 1 second back
                appState.stepSeconds(-1)
            } else if modifiers.contains(.shift) && !modifiers.contains(.command) {
                // Shift+Left: 10 frames back
                appState.stepFrames(-10)
            } else if modifiers.isEmpty {
                // Left: 1 frame back
                appState.stepFrame(forward: false)
            } else {
                super.keyDown(with: event)
            }
        case 124: // Right arrow
            if modifiers.contains([.command, .shift]) {
                // Cmd+Shift+Right: 1 second forward
                appState.stepSeconds(1)
            } else if modifiers.contains(.shift) && !modifiers.contains(.command) {
                // Shift+Right: 10 frames forward
                appState.stepFrames(10)
            } else if modifiers.isEmpty {
                // Right: 1 frame forward
                appState.stepFrame(forward: true)
            } else {
                super.keyDown(with: event)
            }
        case 46: // M key
            if modifiers.isEmpty {
                appState.markTrim()
            } else {
                super.keyDown(with: event)
            }
        case 115: // Home key
            if modifiers.isEmpty {
                appState.seekToStart()
            } else {
                super.keyDown(with: event)
            }
        default:
            super.keyDown(with: event)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
