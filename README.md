# QuickTrim

QuickTrim is a lightweight macOS app for fast, region-based trimming of video and audio files. It lets you split media into regions, “bin” (exclude) sections you don’t want, preview the kept sequence, and export a trimmed file without round‑tripping through a full editor.

## What it does
- Drop a media file or open one from Finder.
- Mark trim points to split the timeline into regions.
- Bin regions you want removed; kept regions export in order.
- Preview the export timeline.
- Export video or audio with a simple save dialog and progress overlay.

## How to use
1. Launch the app and drop a video/audio file.
2. Scrub to a point and press `M` to split (create regions).
3. Bin regions via the trash icon in the Regions list.
4. Toggle Preview mode to hear/see only kept regions.
5. Click Export and choose a destination.

## Useful shortcuts
- Play/Pause: `Space`
- Mark trim point: `M`
- Step 1 frame: `←` / `→`
- Step 10 frames: `Shift` + `←` / `→`
- Step 1 second: `⌘` + `Shift` + `←` / `→`
- Go to start: `Home`
- Bin left/right of playhead: `⌘[` / `⌘]`
- Toggle Preview: `⌘⌥P`
- Toggle Skimming: `⌘⌥S`
- Zoom: `⌘+` / `⌘-`
- Export: `⌘⇧E`

## Supported formats
- Open: common video (`.mov`, `.mp4`, `.m4v`, `.avi`) and audio (`.mp3`, `.m4a`, `.aiff`, `.wav`).
- Export: video outputs match the source type when possible; audio exports as `.m4a`, `.aiff`, or `.wav` (MP3 sources export to M4A).