//
//  AboutView.swift
//  QuickTrim
//
//  Custom About window (QuickTrim › About QuickTrim) and the Help menu.
//  The help window itself is in HelpCenter.swift.
//

import SwiftUI
import AppKit

enum AppInfo {
    static let name = "QuickTrim"
    static let author = "Neil Cameron"
    static let copyrightYear = "2026"
    static let tagline = "Fast, lossless trimming for video and audio."

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    /// The app icon with transparent corners. The AppIcon PNGs have their
    /// dark background baked in, which shows as a black square outside the
    /// Dock; this cut-out (also used by the Help pages) doesn't.
    static var icon: NSImage {
        if let url = Bundle.main.url(forResource: "icon", withExtension: "png", subdirectory: "Help"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp.applicationIconImage
    }
}

/// Replaces the stock About panel (QuickTrim menu → "About QuickTrim").
/// Layout and styling match FollowUp's About window.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: AppInfo.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                .padding(.top, 34)

            Text(AppInfo.name)
                .font(.system(size: 26, weight: .semibold))
                .padding(.top, 14)

            Text(AppInfo.version)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Text(AppInfo.tagline)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .padding(.horizontal, 28)

            Divider()
                .frame(width: 140)
                .padding(.vertical, 18)

            VStack(spacing: 3) {
                Text("Created by")
                    .font(.system(size: 10.5, weight: .medium))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.tertiary)
                Text(AppInfo.author)
                    .font(.system(size: 17, weight: .medium))
            }

            Button {
                HelpCenter.show()
            } label: {
                Label("QuickTrim Help", systemImage: "questionmark.circle")
            }
            .controlSize(.regular)
            .padding(.top, 20)

            Text("© \(AppInfo.copyrightYear) \(AppInfo.author). All rights reserved.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 20)
                .padding(.bottom, 20)
        }
        .frame(width: 340)
        .modifier(AboutWindowStyle())
    }
}

/// FollowUp's frosted window background and no-minimise behaviour. Both
/// need macOS 15; on 14 the window keeps its standard background.
private struct AboutWindowStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .containerBackground(.regularMaterial, for: .window)
                .windowMinimizeBehavior(.disabled)
        } else {
            content
        }
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
                HelpCenter.show()
            }
            .keyboardShortcut("?", modifiers: .command)

            Divider()

            Button("Keyboard Shortcuts") {
                HelpCenter.show("shortcuts")
            }
            Button("Exporting and File Formats") {
                HelpCenter.show("export")
            }
            Button("Troubleshooting") {
                HelpCenter.show("troubleshooting")
            }
        }
    }
}
