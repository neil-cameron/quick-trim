# Repository Guidelines

## Project Structure & Module Organization
- `QuickTrim/QuickTrim.xcodeproj`: Xcode project for the macOS app.
- `QuickTrim/QuickTrim`: App source root.
  - `Models/`: App state and data structures (e.g., `AppState`, `Region`).
  - `Services/`: Media processing utilities (e.g., waveform generation, export).
  - `Views/`: SwiftUI screens and components.
  - `Assets.xcassets/`: App icons and asset catalogs.
  - `Info.plist`, `QuickTrim.entitlements`, `QuickTrimApp.swift`: app configuration and entry point.
- `QuickTrim/generate_icons.sh`: Helper script for regenerating AppIcon PNGs from SVG.
- `Icon/`: Source artwork and exported icon assets. Do not edit generated app icon PNGs directly unless regenerating the catalog.
- `README.md`: User-facing app overview, shortcuts, and supported formats.

## Build, Test, and Development Commands
- Open in Xcode: `open QuickTrim/QuickTrim.xcodeproj` and press Run for local builds.
- CLI build: `xcodebuild -project QuickTrim/QuickTrim.xcodeproj -scheme QuickTrim -configuration Debug build`.
- Regenerate icons: `./QuickTrim/generate_icons.sh` (requires `rsvg-convert` from `librsvg`).

## Coding Style & Naming Conventions
- SwiftUI code uses 4-space indentation and standard Swift brace style.
- Types and files use UpperCamelCase (e.g., `TimelineView.swift`).
- Views are colocated in `Views/`, services in `Services/`, and models in `Models/`.
- Keep UI strings short and user-facing; prefer `AppState` for shared state.
- Keep README shortcuts and supported formats in sync with `AppState` and the SwiftUI command/menu handlers.

## Testing Guidelines
- No automated test targets are present currently.
- If you add tests, place them in a new `QuickTrimTests/` target and use XCTest.
- Name test files `*Tests.swift` and keep test methods descriptive (e.g., `testExportCompletes`).

## Commit & Pull Request Guidelines
- Commit messages follow Conventional Commits (`feat:`, `fix:`, etc.).
- PRs should include a short summary, testing notes (e.g., “Ran app in Xcode”), and screenshots for UI changes.
- Link issues when applicable and call out any manual QA steps.

## Security & Configuration Tips
- Keep entitlements in `QuickTrim/QuickTrim/QuickTrim.entitlements` minimal and documented.
- Avoid hard-coding file system paths; use user-selected URLs and sandbox-safe APIs.
