//
//  CropOverlayView.swift
//  QuickTrim
//
//  Crop overlay with drag handles and controls panel
//

import SwiftUI
import AVKit
import AppKit

// MARK: - Handle Positions

enum CropHandlePosition: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
    case top, bottom, left, right
}

// MARK: - Crop Overlay

struct CropOverlayView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        GeometryReader { geometry in
            let viewSize = geometry.size
            let videoSize = appState.videoNativeSize
            let videoRect = Self.videoDisplayRect(viewSize: viewSize, videoSize: videoSize)
            let scale = videoSize.width > 0 ? videoRect.width / videoSize.width : 1

            let cropRect = CGRect(
                x: videoRect.minX + CGFloat(appState.cropLeft) * scale,
                y: videoRect.minY + CGFloat(appState.cropTop) * scale,
                width: max(1, (videoSize.width - CGFloat(appState.cropLeft + appState.cropRight)) * scale),
                height: max(1, (videoSize.height - CGFloat(appState.cropTop + appState.cropBottom)) * scale)
            )

            ZStack {
                // Dimmed area outside crop
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: viewSize))
                    path.addRect(cropRect)
                }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                // Crop border
                Rectangle()
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)
                    .allowsHitTesting(false)

                // Rule of thirds grid
                Canvas { context, _ in
                    let color = Color.white.opacity(0.2)
                    for i in 1...2 {
                        let x = cropRect.minX + cropRect.width * CGFloat(i) / 3
                        var vPath = Path()
                        vPath.move(to: CGPoint(x: x, y: cropRect.minY))
                        vPath.addLine(to: CGPoint(x: x, y: cropRect.maxY))
                        context.stroke(vPath, with: .color(color), lineWidth: 0.5)

                        let y = cropRect.minY + cropRect.height * CGFloat(i) / 3
                        var hPath = Path()
                        hPath.move(to: CGPoint(x: cropRect.minX, y: y))
                        hPath.addLine(to: CGPoint(x: cropRect.maxX, y: y))
                        context.stroke(hPath, with: .color(color), lineWidth: 0.5)
                    }
                }
                .allowsHitTesting(false)

                // Drag handles
                ForEach(CropHandlePosition.allCases, id: \.self) { position in
                    CropHandleView(
                        position: position,
                        handleCenter: Self.handleCenter(for: position, in: cropRect),
                        pixelScale: scale
                    )
                }
            }
        }
    }

    static func videoDisplayRect(viewSize: CGSize, videoSize: CGSize) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0 else { return .zero }
        let videoAspect = videoSize.width / videoSize.height
        let viewAspect = viewSize.width / viewSize.height

        if videoAspect > viewAspect {
            let w = viewSize.width
            let h = w / videoAspect
            return CGRect(x: 0, y: (viewSize.height - h) / 2, width: w, height: h)
        } else {
            let h = viewSize.height
            let w = h * videoAspect
            return CGRect(x: (viewSize.width - w) / 2, y: 0, width: w, height: h)
        }
    }

    static func handleCenter(for position: CropHandlePosition, in rect: CGRect) -> CGPoint {
        switch position {
        case .topLeft:     return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:    return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .top:         return CGPoint(x: rect.midX, y: rect.minY)
        case .bottom:      return CGPoint(x: rect.midX, y: rect.maxY)
        case .left:        return CGPoint(x: rect.minX, y: rect.midY)
        case .right:       return CGPoint(x: rect.maxX, y: rect.midY)
        }
    }
}

// MARK: - Individual Crop Handle

struct CropHandleView: View {
    @EnvironmentObject var appState: AppState
    let position: CropHandlePosition
    let handleCenter: CGPoint
    let pixelScale: CGFloat

    @State private var dragStart: (left: Int, top: Int, right: Int, bottom: Int)?

    private let baseHitSize: CGFloat = 32
    private let minCropSize: Int = 16

    /// Top-edge handles get a taller hit zone extending downward so they
    /// don't conflict with the window title bar.
    private var isTopEdge: Bool {
        position == .top || position == .topLeft || position == .topRight
    }

    private var frameWidth: CGFloat { baseHitSize }
    private var frameHeight: CGFloat { isTopEdge ? baseHitSize + 24 : baseHitSize }

    /// How far to shift the position downward (so extra hit area is below the crop edge).
    private var positionOffsetY: CGFloat { isTopEdge ? 12 : 0 }

    var body: some View {
        Canvas { context, size in
            // Draw visual at the correct spot; compensate for the position offset
            let centerX = size.width / 2
            let centerY = isTopEdge ? size.height / 2 - positionOffsetY : size.height / 2
            let center = CGPoint(x: centerX, y: centerY)
            let armLength: CGFloat = 14
            let lineWidth: CGFloat = 2.5

            var path = Path()
            switch position {
            case .topLeft:
                path.move(to: CGPoint(x: center.x, y: center.y + armLength))
                path.addLine(to: center)
                path.addLine(to: CGPoint(x: center.x + armLength, y: center.y))
            case .topRight:
                path.move(to: CGPoint(x: center.x - armLength, y: center.y))
                path.addLine(to: center)
                path.addLine(to: CGPoint(x: center.x, y: center.y + armLength))
            case .bottomLeft:
                path.move(to: CGPoint(x: center.x, y: center.y - armLength))
                path.addLine(to: center)
                path.addLine(to: CGPoint(x: center.x + armLength, y: center.y))
            case .bottomRight:
                path.move(to: CGPoint(x: center.x - armLength, y: center.y))
                path.addLine(to: center)
                path.addLine(to: CGPoint(x: center.x, y: center.y - armLength))
            case .top, .bottom:
                path.move(to: CGPoint(x: center.x - armLength, y: center.y))
                path.addLine(to: CGPoint(x: center.x + armLength, y: center.y))
            case .left, .right:
                path.move(to: CGPoint(x: center.x, y: center.y - armLength))
                path.addLine(to: CGPoint(x: center.x, y: center.y + armLength))
            }

            let shadowStyle = StrokeStyle(lineWidth: lineWidth + 2, lineCap: .round, lineJoin: .round)
            let mainStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            context.stroke(path, with: .color(.black.opacity(0.6)), style: shadowStyle)
            context.stroke(path, with: .color(.white), style: mainStyle)
        }
        .frame(width: frameWidth, height: frameHeight)
        .contentShape(Rectangle())
        .position(x: handleCenter.x, y: handleCenter.y + positionOffsetY)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if dragStart == nil {
                        dragStart = (appState.cropLeft, appState.cropTop, appState.cropRight, appState.cropBottom)
                    }
                    guard let start = dragStart else { return }
                    applyDrag(translation: value.translation, start: start)
                }
                .onEnded { _ in
                    dragStart = nil
                }
        )
        .onHover { hovering in
            if hovering {
                cursorForPosition.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var cursorForPosition: NSCursor {
        switch position {
        case .topLeft, .bottomRight, .topRight, .bottomLeft:
            return .crosshair
        case .top, .bottom:
            return .resizeUpDown
        case .left, .right:
            return .resizeLeftRight
        }
    }

    private func applyDrag(translation: CGSize, start: (left: Int, top: Int, right: Int, bottom: Int)) {
        let dx = Int(translation.width / pixelScale)
        let dy = Int(translation.height / pixelScale)
        let maxW = Int(appState.videoNativeSize.width)
        let maxH = Int(appState.videoNativeSize.height)

        switch position {
        case .left, .topLeft, .bottomLeft:
            appState.cropLeft = clamp(start.left + dx, 0, maxW - start.right - minCropSize)
        default: break
        }
        switch position {
        case .right, .topRight, .bottomRight:
            appState.cropRight = clamp(start.right - dx, 0, maxW - start.left - minCropSize)
        default: break
        }
        switch position {
        case .top, .topLeft, .topRight:
            appState.cropTop = clamp(start.top + dy, 0, maxH - start.bottom - minCropSize)
        default: break
        }
        switch position {
        case .bottom, .bottomLeft, .bottomRight:
            appState.cropBottom = clamp(start.bottom - dy, 0, maxH - start.top - minCropSize)
        default: break
        }
    }

    private func clamp(_ value: Int, _ lo: Int, _ hi: Int) -> Int {
        Swift.min(Swift.max(value, lo), hi)
    }
}

// MARK: - Cropped Video Display (non-crop-mode)

struct CroppedVideoView: View {
    let player: AVPlayer
    @EnvironmentObject var appState: AppState

    var body: some View {
        GeometryReader { geometry in
            let layout = cropLayout(viewSize: geometry.size)

            ZStack {
                AVPlayerContainerView(player: player)
                    .frame(width: layout.videoFrame.width, height: layout.videoFrame.height)
                    .offset(x: layout.offset.width, y: layout.offset.height)
            }
            .frame(width: layout.clipFrame.width, height: layout.clipFrame.height)
            .clipped()
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func cropLayout(viewSize: CGSize) -> (videoFrame: CGSize, clipFrame: CGSize, offset: CGSize) {
        let videoSize = appState.videoNativeSize
        let croppedW = max(1, videoSize.width - CGFloat(appState.cropLeft + appState.cropRight))
        let croppedH = max(1, videoSize.height - CGFloat(appState.cropTop + appState.cropBottom))

        let croppedAspect = croppedW / croppedH
        let viewAspect = viewSize.width / viewSize.height

        let scale = croppedAspect > viewAspect
            ? viewSize.width / croppedW
            : viewSize.height / croppedH

        let scaledVideoW = videoSize.width * scale
        let scaledVideoH = videoSize.height * scale
        let scaledCropW = croppedW * scale
        let scaledCropH = croppedH * scale

        let offsetX = (scaledVideoW / 2) - (CGFloat(appState.cropLeft) * scale + scaledCropW / 2)
        let offsetY = (scaledVideoH / 2) - (CGFloat(appState.cropTop) * scale + scaledCropH / 2)

        return (
            videoFrame: CGSize(width: scaledVideoW, height: scaledVideoH),
            clipFrame: CGSize(width: scaledCropW, height: scaledCropH),
            offset: CGSize(width: offsetX, height: offsetY)
        )
    }
}

// MARK: - Crop Controls Panel

struct CropControlsPanel: View {
    @EnvironmentObject var appState: AppState

    private let minCropSize: Int = 16

    private var maxW: Int { Int(appState.videoNativeSize.width) }
    private var maxH: Int { Int(appState.videoNativeSize.height) }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 16) {
                cropField("Left", value: $appState.cropLeft,
                          max: maxW - appState.cropRight - minCropSize)
                cropField("Top", value: $appState.cropTop,
                          max: maxH - appState.cropBottom - minCropSize)

                Spacer()

                // Output dimensions
                Text("\(Int(appState.croppedSize.width)) \u{00D7} \(Int(appState.croppedSize.height))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                cropField("Right", value: $appState.cropRight,
                          max: maxW - appState.cropLeft - minCropSize)
                cropField("Bottom", value: $appState.cropBottom,
                          max: maxH - appState.cropTop - minCropSize)

                Spacer()

                Button("Reset") {
                    appState.resetCrop()
                }
                .controlSize(.small)
                .disabled(!appState.hasCrop)

                Button("Done") {
                    appState.isCropModeActive = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func cropField(_ label: String, value: Binding<Int>, max: Int) -> some View {
        let safeMax = Swift.max(0, max)
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .frame(width: 48, alignment: .trailing)

            Slider(
                value: Binding<Double>(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Swift.min(safeMax, Swift.max(0, Int($0))) }
                ),
                in: 0...Double(Swift.max(1, safeMax))
            )
            .frame(width: 100)

            CropNumberField(value: value, min: 0, max: safeMax)
                .frame(width: 55, height: 20)
        }
    }
}

// MARK: - Crop Number Field (NSViewRepresentable)

/// An editable integer field that supports click-to-select, Enter to commit,
/// Up/Down arrow to step by 1, Shift+Up/Down to step by 10, and clamping.
struct CropNumberField: NSViewRepresentable {
    @Binding var value: Int
    let min: Int
    let max: Int

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.alignment = .right
        field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        field.integerValue = value
        field.cell?.isScrollable = true
        field.cell?.wraps = false

        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.generatesDecimalNumbers = false
        field.formatter = formatter

        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.min = min
        context.coordinator.max = max

        // Don't update while user is typing
        if let editor = nsView.currentEditor(),
           nsView.window?.firstResponder === editor {
            return
        }
        nsView.integerValue = value
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, min: min, max: max)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var value: Binding<Int>
        var min: Int
        var max: Int

        init(value: Binding<Int>, min: Int, max: Int) {
            self.value = value
            self.min = min
            self.max = max
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            DispatchQueue.main.async {
                field.currentEditor()?.selectAll(nil)
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            commitValue(in: field)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let field = control as? NSTextField else { return false }

            // Up arrow: +1, Shift+Up arrow: +10
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                stepValue(by: 1, in: field)
                return true
            }
            if commandSelector == #selector(NSResponder.moveUpAndModifySelection(_:)) {
                stepValue(by: 10, in: field)
                return true
            }
            // Down arrow: -1, Shift+Down arrow: -10
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                stepValue(by: -1, in: field)
                return true
            }
            if commandSelector == #selector(NSResponder.moveDownAndModifySelection(_:)) {
                stepValue(by: -10, in: field)
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                commitValue(in: field)
                field.window?.makeFirstResponder(nil)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                field.integerValue = value.wrappedValue
                field.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }

        private func commitValue(in field: NSTextField) {
            let clamped = Swift.min(max, Swift.max(min, field.integerValue))
            value.wrappedValue = clamped
            field.integerValue = clamped
        }

        private func stepValue(by delta: Int, in field: NSTextField) {
            let current = field.integerValue
            let newValue = Swift.min(max, Swift.max(min, current + delta))
            value.wrappedValue = newValue
            field.integerValue = newValue
            DispatchQueue.main.async {
                field.currentEditor()?.selectAll(nil)
            }
        }
    }
}
