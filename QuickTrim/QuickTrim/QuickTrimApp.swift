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
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onOpenURL { url in
                    appState.openVideo(url: url)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    appState.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Divider()

                Button("Export") {
                    appState.exportVideo()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!appState.canExport)
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    appState.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!appState.canUndo)

                Button("Redo") {
                    appState.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!appState.canRedo)
            }

            CommandMenu("Playback") {
                Button("Play/Pause") {
                    appState.togglePlayPause()
                }
                .keyboardShortcut(" ", modifiers: [])
                .disabled(appState.videoURL == nil)

                Divider()

                Button("Go Back 1 Frame") {
                    appState.stepFrame(forward: false)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(appState.videoURL == nil)

                Button("Go Forward 1 Frame") {
                    appState.stepFrame(forward: true)
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(appState.videoURL == nil)

                Divider()

                Button("Go Back 10 Frames") {
                    appState.stepFrames(-10)
                }
                .keyboardShortcut(.leftArrow, modifiers: .shift)
                .disabled(appState.videoURL == nil)

                Button("Go Forward 10 Frames") {
                    appState.stepFrames(10)
                }
                .keyboardShortcut(.rightArrow, modifiers: .shift)
                .disabled(appState.videoURL == nil)

                Divider()

                Button("Go Back 1 Second") {
                    appState.stepSeconds(-1)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
                .disabled(appState.videoURL == nil)

                Button("Go Forward 1 Second") {
                    appState.stepSeconds(1)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
                .disabled(appState.videoURL == nil)
            }

            CommandMenu("Timeline") {
                Button("Mark Trim") {
                    appState.markTrim()
                }
                .keyboardShortcut("m", modifiers: [])
                .disabled(appState.videoURL == nil)

                Divider()

                Button("Bin Region Left of Playhead") {
                    appState.binRegionLeftOfPlayhead()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(appState.videoURL == nil)

                Button("Bin Region Right of Playhead") {
                    appState.binRegionRightOfPlayhead()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(appState.videoURL == nil)

                Divider()

                Toggle("Enable Scrubbing", isOn: $appState.scrubbingEnabled)
                    .keyboardShortcut("s", modifiers: [.command, .option])

                Toggle("Preview Mode", isOn: $appState.previewModeEnabled)
                    .keyboardShortcut("p", modifiers: [.command, .option])

                Divider()

                Button("Zoom In") {
                    appState.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(appState.videoURL == nil)

                Button("Zoom Out") {
                    appState.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(appState.videoURL == nil)
            }
        }
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first {
            AppState.shared.openVideo(url: url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppState.shared.hasUnsavedChanges {
            AppState.shared.showCloseConfirmation = true
            return .terminateLater
        }
        return .terminateNow
    }
}
