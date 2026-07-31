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
        WindowGroup(id: "document") {
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
                    if let appState = getFocusedAppState(), appState.videoURL == nil {
                        appState.showOpenPanel()
                    } else {
                        WindowManager.shared.openNewWindowWithOpenPanel()
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

                Button("Toggle Bin for Current Region") {
                    getFocusedAppState()?.toggleBinForCurrentRegion()
                }
                .keyboardShortcut("b", modifiers: [])

                Button("Remove Current Region Start Marker") {
                    getFocusedAppState()?.removeStartMarkerForCurrentRegion()
                }
                .keyboardShortcut("b", modifiers: .option)

                Divider()

                Button("Crop") {
                    if let appState = getFocusedAppState() {
                        appState.isCropModeActive.toggle()
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .option])

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

                Button("Toggle Capture Playhead") {
                    if let appState = getFocusedAppState() {
                        appState.capturePlayheadEnabled.toggle()
                    }
                }
                .keyboardShortcut("s", modifiers: [.control, .option, .command])

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
        // Use the stored openWindow action from the active view
        WindowManager.shared.openNewWindow()
    }

    private func getFocusedAppState() -> AppState? {
        guard let window = NSApp.keyWindow,
              let contentView = window.contentView,
              let hostingView = DocumentHostingView.find(in: contentView) else {
            return nil
        }
        return hostingView.appState
    }
}

// Singleton to manage window creation from menu commands
class WindowManager {
    static let shared = WindowManager()
    var openWindowAction: (() -> Void)?
    var showOpenPanelOnNextWindow: Bool = false
    var pendingURL: URL?

    func openNewWindow() {
        if let action = openWindowAction {
            action()
        }
    }

    func openNewWindowWithOpenPanel() {
        showOpenPanelOnNextWindow = true
        openNewWindow()
    }

    func openNewWindow(withURL url: URL) {
        pendingURL = url
        openNewWindow()
    }

    /// Finds an already-open window whose document is blank (no video loaded).
    static func findBlankAppState() -> AppState? {
        for window in NSApp.windows {
            if let contentView = window.contentView,
               let hostingView = DocumentHostingView.find(in: contentView),
               let appState = hostingView.appState,
               appState.videoURL == nil {
                return appState
            }
        }
        return nil
    }
}

// Custom hosting view to store AppState reference
class DocumentHostingView: NSView {
    var appState: AppState?

    /// Recursively search a view hierarchy for a DocumentHostingView
    static func find(in view: NSView) -> DocumentHostingView? {
        if let hostingView = view as? DocumentHostingView {
            return hostingView
        }
        for subview in view.subviews {
            if let found = find(in: subview) {
                return found
            }
        }
        return nil
    }
}

// Wrapper view that creates a unique AppState per window
struct DocumentWindowView: View {
    @StateObject private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView()
            .environmentObject(appState)
            .background(
                DocumentHostingViewRepresentable(appState: appState)
            )
            .onAppear {
                // Register the openWindow action for menu commands
                WindowManager.shared.openWindowAction = { [openWindow] in
                    openWindow(id: "document")
                }

                // If a file was waiting for the next window (Finder "Open" or
                // Cmd+O from a window with content), load it into this one.
                if let url = WindowManager.shared.pendingURL {
                    WindowManager.shared.pendingURL = nil
                    appState.openVideo(url: url)
                } else if WindowManager.shared.showOpenPanelOnNextWindow {
                    WindowManager.shared.showOpenPanelOnNextWindow = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        appState.showOpenPanel()
                    }
                }
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
        guard let url = urls.first else { return }

        // Reuse a blank window if one is already open (or is the window
        // SwiftUI is about to create for a cold launch); otherwise open
        // a brand new window for it. Either way, no delay/race needed:
        // a freshly-created window picks up the pending URL itself in
        // DocumentWindowView.onAppear.
        if let appState = WindowManager.findBlankAppState() {
            appState.openVideo(url: url)
            // On a cold launch with a file to open, SwiftUI can spin up more
            // than one initial "document" window before this delegate call
            // runs. Now that the file has a home, any window still blank
            // is launch noise, not a window the user asked for.
            closeOtherBlankWindows(keeping: appState)
        } else {
            WindowManager.shared.openNewWindow(withURL: url)
        }
    }

    private func closeOtherBlankWindows(keeping appState: AppState) {
        for window in NSApp.windows {
            guard let contentView = window.contentView,
                  let hostingView = DocumentHostingView.find(in: contentView),
                  let windowAppState = hostingView.appState,
                  windowAppState !== appState,
                  windowAppState.videoURL == nil else { continue }
            window.close()
        }
    }

    // Windows here are always transient (a blank drop target or a loaded
    // video); there's nothing worth restoring across launches.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running when window closes so user can open new files
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Check if any window has unsaved changes
        let hasUnsavedChanges = NSApp.windows.contains { window in
            guard let contentView = window.contentView,
                  let hostingView = DocumentHostingView.find(in: contentView),
                  let appState = hostingView.appState else {
                return false
            }
            return appState.hasUserCreatedRegions
        }

        guard hasUnsavedChanges else {
            return .terminateNow
        }

        // Show a single confirmation for all unsaved work
        let alert = NSAlert()
        alert.messageText = "Unsaved Changes"
        alert.informativeText = "You have windows with unsaved trim regions. Are you sure you want to quit?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit Without Saving")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            return .terminateNow
        } else {
            return .terminateCancel
        }
    }
}
