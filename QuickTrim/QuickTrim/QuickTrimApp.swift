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

            // Close / Close All go through WindowCloseGuard so unexported
            // regions aren't lost silently (⌘W used to close without asking).
            CommandGroup(replacing: .saveItem) {
                Button("Close") {
                    if let window = NSApp.keyWindow {
                        WindowCloseGuard.requestClose(window)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("Close All") {
                    for window in NSApp.windows where window.isVisible {
                        WindowCloseGuard.requestClose(window)
                    }
                }
                .keyboardShortcut("w", modifiers: [.command, .option])
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    if let editor = activeTextEditor() {
                        editor.undoManager?.undo()
                    } else {
                        getFocusedAppState()?.undo()
                    }
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("Redo") {
                    if let editor = activeTextEditor() {
                        editor.undoManager?.redo()
                    } else {
                        getFocusedAppState()?.redo()
                    }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandMenu("Playback") {
                Button("Play/Pause") {
                    trimShortcut { $0.togglePlayPause() }
                }
                .keyboardShortcut(" ", modifiers: [])

                Button("Go to Start") {
                    trimShortcut { $0.seekToStart() }
                }
                .keyboardShortcut(.home, modifiers: [])

                Divider()

                Button("Go Back 1 Frame") {
                    trimShortcut { $0.stepFrame(forward: false) }
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button("Go Forward 1 Frame") {
                    trimShortcut { $0.stepFrame(forward: true) }
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                Divider()

                Button("Go Back 10 Frames") {
                    trimShortcut { $0.stepFrames(-10) }
                }
                .keyboardShortcut(.leftArrow, modifiers: .shift)

                Button("Go Forward 10 Frames") {
                    trimShortcut { $0.stepFrames(10) }
                }
                .keyboardShortcut(.rightArrow, modifiers: .shift)

                Divider()

                Button("Go Back 1 Second") {
                    trimShortcut { $0.stepSeconds(-1) }
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])

                Button("Go Forward 1 Second") {
                    trimShortcut { $0.stepSeconds(1) }
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            }

            CommandMenu("Timeline") {
                Button("Mark Trim") {
                    trimShortcut { $0.markTrim() }
                }
                .keyboardShortcut("m", modifiers: [])

                Divider()

                Button("Toggle Bin for Current Region") {
                    trimShortcut { $0.toggleBinForCurrentRegion() }
                }
                .keyboardShortcut("b", modifiers: [])

                Button("Remove Current Region Start Marker") {
                    trimShortcut { $0.removeStartMarkerForCurrentRegion() }
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

            AboutAndHelpCommands()
        }
        .windowResizability(.contentSize)

        // About window (QuickTrim › About QuickTrim). commandsRemoved() keeps
        // it out of the Window menu; it's opened from the app menu only.
        Window("About QuickTrim", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()
    }

    private func openNewWindow() {
        // Use the stored openWindow action from the active view
        WindowManager.shared.openNewWindow()
    }

    /// The field editor of a text field being typed in (a crop value, the
    /// Help search field…).
    private func activeTextEditor() -> NSTextView? {
        NSApp.keyWindow?.firstResponder as? NSTextView
    }

    /// Runs a bare-key shortcut (Space, M, B, arrows, Home) on the focused
    /// trim window. Menu key equivalents fire before the focused view sees
    /// the key, so when you're typing in a text field, or the front window
    /// isn't a trim window (Help, About), the keystroke is passed on instead —
    /// otherwise typing "markers" in Help search would lose its m, and Space
    /// couldn't scroll a help page.
    private func trimShortcut(_ action: (AppState) -> Void) {
        guard activeTextEditor() == nil, let appState = getFocusedAppState() else {
            passKeyToFocusedView()
            return
        }
        action(appState)
    }

    private func passKeyToFocusedView() {
        guard let event = NSApp.currentEvent, event.type == .keyDown,
              let responder = NSApp.keyWindow?.firstResponder,
              !(responder is NSWindow) else { return }  // a bare window would just beep
        responder.keyDown(with: event)
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

// MARK: - Window Close Guard

/// Confirms before closing a window whose trim regions haven't been exported.
///
/// SwiftUI owns each window's delegate, so rather than replacing it (which can
/// break SwiftUI's window management) the two real close routes — the title
/// bar close button and File › Close — are routed through here.
enum WindowCloseGuard {
    static func requestClose(_ window: NSWindow) {
        guard let contentView = window.contentView,
              let hostingView = DocumentHostingView.find(in: contentView) else {
            // Not a QuickTrim document window (e.g. About): normal close
            window.performClose(nil)
            return
        }

        guard let appState = hostingView.appState, appState.hasUserCreatedRegions else {
            window.close()
            return
        }

        let name = appState.videoURL?.lastPathComponent ?? "this file"
        let alert = NSAlert()
        alert.messageText = "Close Without Exporting?"
        alert.informativeText = "Your trim regions for \u{201C}\(name)\u{201D} haven't been exported and will be lost."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                // close(), not performClose(): skips re-asking, and avoids any
                // chance of re-entering this guard via the close button
                window.close()
            }
        }
    }
}

// Custom hosting view to store AppState reference
class DocumentHostingView: NSView {
    var appState: AppState?

    /// Route the title bar's close button through WindowCloseGuard.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let closeButton = window?.standardWindowButton(.closeButton) else { return }
        closeButton.target = self
        closeButton.action = #selector(closeButtonPressed(_:))
    }

    @objc private func closeButtonPressed(_ sender: Any?) {
        guard let window else { return }
        WindowCloseGuard.requestClose(window)
    }

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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Help menu search: help topics listed beneath the menu commands
        NSApp.registerUserInterfaceItemSearchHandler(HelpMenuSearch.shared)
    }

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
