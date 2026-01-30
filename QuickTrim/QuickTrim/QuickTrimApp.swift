//
//  QuickTrimApp.swift
//  QuickTrim
//
//  A lightweight video trimming app for macOS
//

import SwiftUI
import AVFoundation

@main
struct QuickTrimApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            DocumentWindowView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            // New Window command
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    openNewWindow()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open...") {
                    if let appState = getFocusedAppState() {
                        appState.showOpenPanel()
                    } else {
                        openNewWindow()
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Divider()

                Button("Export") {
                    getFocusedAppState()?.exportVideo()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    getFocusedAppState()?.undo()
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("Redo") {
                    getFocusedAppState()?.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandMenu("Playback") {
                Button("Play/Pause") {
                    getFocusedAppState()?.togglePlayPause()
                }
                .keyboardShortcut(" ", modifiers: [])

                Button("Go to Start") {
                    getFocusedAppState()?.seekToStart()
                }
                .keyboardShortcut(.home, modifiers: [])

                Divider()

                Button("Go Back 1 Frame") {
                    getFocusedAppState()?.stepFrame(forward: false)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button("Go Forward 1 Frame") {
                    getFocusedAppState()?.stepFrame(forward: true)
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                Divider()

                Button("Go Back 10 Frames") {
                    getFocusedAppState()?.stepFrames(-10)
                }
                .keyboardShortcut(.leftArrow, modifiers: .shift)

                Button("Go Forward 10 Frames") {
                    getFocusedAppState()?.stepFrames(10)
                }
                .keyboardShortcut(.rightArrow, modifiers: .shift)

                Divider()

                Button("Go Back 1 Second") {
                    getFocusedAppState()?.stepSeconds(-1)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])

                Button("Go Forward 1 Second") {
                    getFocusedAppState()?.stepSeconds(1)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            }

            CommandMenu("Timeline") {
                Button("Mark Trim") {
                    getFocusedAppState()?.markTrim()
                }
                .keyboardShortcut("m", modifiers: [])

                Divider()

                Button("Bin Region Left of Playhead") {
                    getFocusedAppState()?.binRegionLeftOfPlayhead()
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Bin Region Right of Playhead") {
                    getFocusedAppState()?.binRegionRightOfPlayhead()
                }
                .keyboardShortcut("]", modifiers: .command)

                Divider()

                Button("Toggle Skimming") {
                    if let appState = getFocusedAppState() {
                        appState.skimmingEnabled.toggle()
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .option])

                Button("Toggle Preview Mode") {
                    if let appState = getFocusedAppState() {
                        appState.previewModeEnabled.toggle()
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .option])

                Divider()

                Button("Zoom In") {
                    getFocusedAppState()?.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    getFocusedAppState()?.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)
            }
        }
        .windowResizability(.contentSize)
    }

    private func openNewWindow() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Bundle.main.bundleIdentifier!) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
    }

    private func getFocusedAppState() -> AppState? {
        guard let window = NSApp.keyWindow,
              let contentView = window.contentView,
              let hostingView = findHostingView(in: contentView) else {
            return nil
        }
        return hostingView.appState
    }

    private func findHostingView(in view: NSView) -> DocumentHostingView? {
        if let hostingView = view as? DocumentHostingView {
            return hostingView
        }
        for subview in view.subviews {
            if let found = findHostingView(in: subview) {
                return found
            }
        }
        return nil
    }
}

// Custom hosting view to store AppState reference
class DocumentHostingView: NSView {
    var appState: AppState?
}

// Wrapper view that creates a unique AppState per window
struct DocumentWindowView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        ContentView()
            .environmentObject(appState)
            .background(
                DocumentHostingViewRepresentable(appState: appState)
            )
            .onOpenURL { url in
                appState.openVideo(url: url)
            }
    }
}

struct DocumentHostingViewRepresentable: NSViewRepresentable {
    let appState: AppState

    func makeNSView(context: Context) -> DocumentHostingView {
        let view = DocumentHostingView()
        view.appState = appState
        return view
    }

    func updateNSView(_ nsView: DocumentHostingView, context: Context) {
        nsView.appState = appState
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        // Open file in a new window or existing empty window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let url = urls.first {
                // Find an empty window or create one
                if let window = NSApp.keyWindow,
                   let contentView = window.contentView,
                   let hostingView = self.findHostingView(in: contentView),
                   let appState = hostingView.appState,
                   appState.videoURL == nil {
                    appState.openVideo(url: url)
                } else {
                    // Create a new window by opening the app
                    self.openURLInNewWindow(url)
                }
            }
        }
    }

    private func findHostingView(in view: NSView) -> DocumentHostingView? {
        if let hostingView = view as? DocumentHostingView {
            return hostingView
        }
        for subview in view.subviews {
            if let found = findHostingView(in: subview) {
                return found
            }
        }
        return nil
    }

    private func openURLInNewWindow(_ url: URL) {
        // Store URL for new window
        pendingURL = url

        // Open new window
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Bundle.main.bundleIdentifier!) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in
                // After window opens, load the URL
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let url = self.pendingURL,
                       let window = NSApp.keyWindow,
                       let contentView = window.contentView,
                       let hostingView = self.findHostingView(in: contentView),
                       let appState = hostingView.appState {
                        appState.openVideo(url: url)
                        self.pendingURL = nil
                    }
                }
            }
        }
    }

    private var pendingURL: URL?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running when window closes so user can open new files
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Check all windows for unsaved changes
        for window in NSApp.windows {
            if let contentView = window.contentView,
               let hostingView = findHostingView(in: contentView),
               let appState = hostingView.appState,
               appState.hasUserCreatedRegions {
                appState.showCloseConfirmation = true
                return .terminateLater
            }
        }
        return .terminateNow
    }
}
