//
//  AboutView.swift
//  QuickTrim
//
//  Custom About window (QuickTrim › About QuickTrim) and the Help menu.
//

import SwiftUI
import AppKit

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "© 2026 Neil Cameron"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .padding(.top, 8)

            Text("QuickTrim")
                .font(.system(size: 24, weight: .semibold))
                .padding(.top, 6)

            Text("Version \(version) (\(build))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)

            Text("Fast, lossless trimming for video and audio.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            Divider()
                .padding(.vertical, 16)

            VStack(spacing: 2) {
                Text("Created by")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Neil Cameron")
                    .font(.headline)
            }

            Button("QuickTrim Help") {
                QuickTrimHelp.open()
            }
            .buttonStyle(.link)
            .padding(.top, 14)

            Text(copyright)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
        }
        .padding(.horizontal, 32)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .frame(width: 360)
    }
}

/// Opens the bundled Apple Help Book (QuickTrim.help) in Help Viewer.
enum QuickTrimHelp {
    static var bookName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") as? String
            ?? "com.quicktrim.app.help"
    }

    static func open() {
        NSApp.showHelp(nil)
    }

    /// Opens the help book at a named anchor (see the `<a name>` tags in the pages).
    static func open(anchor: String) {
        NSHelpManager.shared.openHelpAnchor(anchor, inBook: bookName)
    }
}

/// Replaces the standard About panel and Help menu items.
struct AboutAndHelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About QuickTrim") {
                openWindow(id: "about")
            }
        }

        CommandGroup(replacing: .help) {
            Button("QuickTrim Help") {
                QuickTrimHelp.open()
            }
            .keyboardShortcut("?", modifiers: .command)

            Divider()

            Button("Keyboard Shortcuts") {
                QuickTrimHelp.open(anchor: "shortcuts")
            }
            Button("Exporting and File Formats") {
                QuickTrimHelp.open(anchor: "export")
            }
            Button("Troubleshooting") {
                QuickTrimHelp.open(anchor: "troubleshooting")
            }
        }
    }
}
