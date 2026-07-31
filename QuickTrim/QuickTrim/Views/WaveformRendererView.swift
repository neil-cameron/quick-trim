//
//  WaveformRendererView.swift
//  QuickTrim
//
//  Logic-style waveform rendering: a continuous filled min/max peak outline
//  with a brighter RMS core and a thin center line, drawn per-pixel from the
//  WaveformData peak cache at any zoom level.
//

import SwiftUI

/// Layout constants for the waveform strip shown under video thumbnails.
enum VideoWaveformLayout {
    /// One third of the original 126pt filmstrip area.
    static let stripHeight: CGFloat = 42
}

/// A horizontal span of waveform to draw: a source-time range mapped onto an
/// x range, with its display state. Preview mode concatenates several
/// segments; binned regions and played/unplayed splits also become segments.
struct WaveformSegment {
    let timeStart: Double
    let timeEnd: Double
    let xStart: CGFloat
    let xEnd: CGFloat
    var isBinned: Bool = false
    var isDimmed: Bool = false   // e.g. unplayed portion in the player view
}

extension WaveformSegment {
    /// Segments for a linear timeline (time 0...duration mapped to 0...width),
    /// split wherever the binned state changes, and optionally at a playhead
    /// time (before the playhead = full brightness, after = dimmed).
    static func linearTimeline(
        duration: Double,
        width: CGFloat,
        regions: [Region],
        dimAfter playheadTime: Double? = nil
    ) -> [WaveformSegment] {
        guard duration > 0, width > 0 else { return [] }

        var boundaries: Set<Double> = [0, duration]
        for region in regions where region.isBinned {
            boundaries.insert(min(max(region.startTime, 0), duration))
            boundaries.insert(min(max(region.endTime, 0), duration))
        }
        if let playheadTime, playheadTime > 0, playheadTime < duration {
            boundaries.insert(playheadTime)
        }

        let sorted = boundaries.sorted()
        var segments: [WaveformSegment] = []

        for (start, end) in zip(sorted, sorted.dropFirst()) where end > start {
            let mid = (start + end) / 2
            let isBinned = regions.contains {
                $0.isBinned && mid >= $0.startTime && mid < $0.endTime
            }
            let isDimmed = playheadTime.map { mid > $0 } ?? false
            segments.append(WaveformSegment(
                timeStart: start,
                timeEnd: end,
                xStart: CGFloat(start / duration) * width,
                xEnd: CGFloat(end / duration) * width,
                isBinned: isBinned,
                isDimmed: isDimmed
            ))
        }
        return segments
    }

    /// Segments for preview mode: kept regions laid out contiguously.
    static func previewTimeline(
        keptRegions: [Region],
        width: CGFloat
    ) -> [WaveformSegment] {
        let totalDuration = keptRegions.reduce(0) { $0 + $1.duration }
        guard totalDuration > 0, width > 0 else { return [] }

        var segments: [WaveformSegment] = []
        var elapsed: Double = 0
        for region in keptRegions {
            let xStart = CGFloat(elapsed / totalDuration) * width
            elapsed += region.duration
            let xEnd = CGFloat(elapsed / totalDuration) * width
            segments.append(WaveformSegment(
                timeStart: region.startTime,
                timeEnd: region.endTime,
                xStart: xStart,
                xEnd: xEnd
            ))
        }
        return segments
    }
}

/// Vertical fill targets for peak normalization per display surface.
enum WaveformFill {
    /// Timeline strips: loudest peak nearly fills the strip.
    static let timeline: Float = 0.95
    /// Player view: gentler boost so the big waveform keeps some headroom.
    static let player: Float = 0.65
}

/// Canvas that renders WaveformData as a Logic-style continuous shape.
struct WaveformCanvasView: View {
    let data: WaveformData
    let segments: [WaveformSegment]
    var targetFill: Float = WaveformFill.timeline

    var body: some View {
        // No .drawingGroup() here: it rasterizes the whole canvas into one
        // Metal texture, and a zoomed timeline can exceed the GPU's maximum
        // texture size (16384px), which blanks the strip entirely.
        Canvas { context, size in
            let gain = data.normalizationGain(targetFill: targetFill)
            for segment in segments {
                WaveformRenderer.draw(segment: segment, data: data, in: &context, height: size.height, gain: gain)
            }
        }
    }
}

enum WaveformRenderer {

    struct Palette {
        let peak: Color
        let rms: Color
        let centerLine: Color

        static func palette(isBinned: Bool, isDimmed: Bool) -> Palette {
            let base: Color = isBinned ? .red : .green
            let dim: Double = isDimmed ? 0.45 : 1.0
            return Palette(
                peak: base.opacity(0.45 * dim),
                rms: base.opacity(0.95 * dim),
                centerLine: base.opacity(0.8 * dim)
            )
        }
    }

    /// Per-pixel column aggregated (or interpolated) levels.
    private struct ColumnLevels {
        var mins: [Float]
        var maxs: [Float]
        var rms: [Float]
    }

    static func draw(
        segment: WaveformSegment,
        data: WaveformData,
        in context: inout GraphicsContext,
        height: CGFloat,
        gain: CGFloat = 1
    ) {
        let widthPx = segment.xEnd - segment.xStart
        guard widthPx >= 1, data.bucketCount > 0, data.duration > 0 else { return }

        let columnCount = Int(widthPx.rounded(.up))
        let levels = columnLevels(segment: segment, data: data, columnCount: columnCount)

        let midY = height / 2
        let amplitude = midY * 0.95 * gain
        let palette = Palette.palette(isBinned: segment.isBinned, isDimmed: segment.isDimmed)

        // Outer min/max peak shape
        let peakPath = filledShape(
            xStart: segment.xStart,
            tops: levels.maxs,
            bottoms: levels.mins,
            midY: midY,
            amplitude: amplitude
        )
        context.fill(peakPath, with: .color(palette.peak))

        // Inner RMS core (symmetric around the center line)
        let rmsPath = filledShape(
            xStart: segment.xStart,
            tops: levels.rms,
            bottoms: levels.rms.map { -$0 },
            midY: midY,
            amplitude: amplitude
        )
        context.fill(rmsPath, with: .color(palette.rms))

        // Thin center line so silence reads as a line, like Logic
        let centerLine = Path(CGRect(
            x: segment.xStart,
            y: midY - 0.5,
            width: widthPx,
            height: 1
        ))
        context.fill(centerLine, with: .color(palette.centerLine))
    }

    /// Aggregate (zoomed out) or interpolate (zoomed in) the peak cache into
    /// one min/max/RMS triple per pixel column.
    private static func columnLevels(
        segment: WaveformSegment,
        data: WaveformData,
        columnCount: Int
    ) -> ColumnLevels {
        var mins = [Float](repeating: 0, count: columnCount)
        var maxs = [Float](repeating: 0, count: columnCount)
        var rms = [Float](repeating: 0, count: columnCount)

        let bucketsPerSecond = data.bucketsPerSecond
        let segmentDuration = segment.timeEnd - segment.timeStart
        let widthPx = Double(segment.xEnd - segment.xStart)
        let lastBucket = data.bucketCount - 1

        for column in 0..<columnCount {
            let t0 = segment.timeStart + segmentDuration * (Double(column) / widthPx)
            let t1 = segment.timeStart + segmentDuration * (Double(column + 1) / widthPx)
            let b0 = t0 * bucketsPerSecond
            let b1 = t1 * bucketsPerSecond

            if b1 - b0 >= 1 {
                // Multiple buckets per pixel: aggregate
                let start = max(0, min(Int(b0), lastBucket))
                let end = max(start + 1, min(Int(b1.rounded(.up)), data.bucketCount))
                var minV: Float = 0
                var maxV: Float = 0
                var sumSquares: Double = 0
                for bucket in start..<end {
                    minV = min(minV, data.minSamples[bucket])
                    maxV = max(maxV, data.maxSamples[bucket])
                    let r = Double(data.rmsSamples[bucket])
                    sumSquares += r * r
                }
                mins[column] = minV
                maxs[column] = maxV
                rms[column] = Float(sqrt(sumSquares / Double(end - start)))
            } else {
                // Zoomed beyond cache resolution: interpolate between buckets
                let position = (b0 + b1) / 2 - 0.5
                let lower = max(0, min(Int(position.rounded(.down)), lastBucket))
                let upper = min(lower + 1, lastBucket)
                let fraction = Float(max(0, min(position - Double(lower), 1)))
                mins[column] = data.minSamples[lower] * (1 - fraction) + data.minSamples[upper] * fraction
                maxs[column] = data.maxSamples[lower] * (1 - fraction) + data.maxSamples[upper] * fraction
                rms[column] = data.rmsSamples[lower] * (1 - fraction) + data.rmsSamples[upper] * fraction
            }
        }

        return ColumnLevels(mins: mins, maxs: maxs, rms: rms)
    }

    /// Closed shape: top edge left-to-right, bottom edge right-to-left.
    private static func filledShape(
        xStart: CGFloat,
        tops: [Float],
        bottoms: [Float],
        midY: CGFloat,
        amplitude: CGFloat
    ) -> Path {
        var path = Path()
        guard !tops.isEmpty else { return path }

        var topPoints: [CGPoint] = []
        var bottomPoints: [CGPoint] = []
        topPoints.reserveCapacity(tops.count)
        bottomPoints.reserveCapacity(bottoms.count)

        for column in 0..<tops.count {
            let x = xStart + CGFloat(column) + 0.5
            topPoints.append(CGPoint(x: x, y: midY - CGFloat(tops[column]) * amplitude))
            bottomPoints.append(CGPoint(x: x, y: midY - CGFloat(bottoms[column]) * amplitude))
        }

        // Note: Path.addLines starts a new subpath, so trace the outline
        // point-by-point to keep it one closed shape.
        path.move(to: topPoints[0])
        for point in topPoints.dropFirst() {
            path.addLine(to: point)
        }
        for point in bottomPoints.reversed() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}
