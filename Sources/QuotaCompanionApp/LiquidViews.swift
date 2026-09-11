import AppKit
import Combine
import QuotaCore
import SwiftUI

struct LiquidOrbView: View {
    let window: QuotaWindow?
    let state: QuotaDataState
    let source: QuotaDataSource
    let locale: Locale
    var size: CGFloat = 56

    var accessibility = CompanionAccessibility()
    @State private var wavePhase = 0.0

    private var remaining: Double { window?.remainingPercent ?? 0 }
    private var liquidColor: Color { CompanionTokens.liquidColor(for: remaining) }

    var body: some View {
        ZStack {
            if accessibility.reduceTransparency {
                Circle().fill(CompanionTokens.foam)
            } else {
                Circle().fill(.ultraThinMaterial)
            }
            Circle()
                .fill(
                    LinearGradient(
                        colors: [CompanionTokens.foam.opacity(0.72), CompanionTokens.waterGlass.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            WaveShape(level: remaining / 100, phase: wavePhase)
                .fill(
                    LinearGradient(
                        colors: [liquidColor.opacity(0.28), liquidColor.opacity(0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(Circle())
                .animation(accessibility.reduceMotion ? nil : .easeOut(duration: 0.35), value: remaining)

            // Reflections are static layers, not a continuous animation or shader.
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.78), .white.opacity(0.02)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.50, height: size * 0.17)
                .rotationEffect(.degrees(-26))
                .offset(x: -size * 0.12, y: -size * 0.32)
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.12), .white.opacity(0.65)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            Circle().strokeBorder(CompanionTokens.accent.opacity(accessibility.contrast == .increased ? 0.55 : 0.12), lineWidth: 0.5)

            VStack(spacing: -1) {
                Text("\(Int(remaining.rounded()))%")
                    .font(CompanionTokens.mono(size * 0.23, weight: .bold))
                    .contentTransition(.numericText())
                Text(window?.compactLabel(locale: locale) ?? "—")
                    .font(CompanionTokens.rounded(size * 0.14, weight: .semibold))
                    .opacity(0.8)
            }
            .foregroundStyle(CompanionTokens.ink)
            .shadow(color: .white.opacity(0.7), radius: 1)

            if source == .demo {
                Text("DEV")
                    .font(CompanionTokens.mono(6, weight: .bold))
                    .foregroundStyle(CompanionTokens.ink.opacity(0.64))
                    .offset(y: size * 0.34)
            }
        }
        .saturation(state == .live ? 1 : 0.35)
        .opacity(state == .unavailable ? 0.64 : 1)
        .frame(width: size, height: size)
        .clipShape(Circle())
        .onAppear(perform: runWave)
        .onChange(of: remaining) { _, _ in runWave() }
        .onHover { hovering in
            if hovering { runWave() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.map { "\($0.accessibleLabel(locale: locale)), \(Int($0.remainingPercent.rounded())) percent remaining" } ?? "Quota unavailable")
    }

    private func runWave() {
        guard !accessibility.reduceMotion else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) { wavePhase = 0 }
            return
        }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) { wavePhase = 0 }
        DispatchQueue.main.async {
            withAnimation(.linear(duration: 1.05)) { wavePhase = .pi * 2 }
        }
    }
}

private struct WaveShape: Shape {
    var level: Double
    var phase: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(level, phase) }
        set {
            level = newValue.first
            phase = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clamped = min(max(level, 0), 1)
        if clamped == 0 { return path }
        if clamped == 1 { return Path(rect) }
        let baseline = rect.maxY - rect.height * clamped
        let amplitude = max(1.4, rect.height * 0.035)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: baseline))
        let steps = max(Int(rect.width), 24)
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let x = rect.minX + rect.width * progress
            let y = baseline + sin(progress * .pi * 2.2 + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct MascotAssetView: View {
    let customPath: String?
    let stale: Bool
    let isVisible: Bool

    var accessibility = CompanionAccessibility()
    @State private var mascot = NSImage()
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if SpriteSheetDescriptor.grid(for: mascot) != nil {
                if isVisible && !accessibility.reduceMotion {
                    SpriteSheetPlaybackView(image: mascot)
                        .id(ObjectIdentifier(mascot))
                } else {
                    Image(nsImage: SpriteSheetDescriptor.firstFrame(from: mascot) ?? mascot)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                StaticMascotView(image: mascot, isAnimating: isVisible && !accessibility.reduceMotion)
                    .id(ObjectIdentifier(mascot))
            }
        }
        .saturation(stale ? 0.34 : 1)
        .shadow(color: CompanionTokens.waterDepth.opacity(0.16), radius: 3, y: 1)
        .onAppear(perform: loadMascot)
        .onChange(of: customPath) { _, _ in loadMascot() }
        .onDisappear { loadTask?.cancel() }
        .accessibilityLabel("Water companion")
    }

    private func loadMascot() {
        loadTask?.cancel()
        var candidates: [URL] = []
        if let packaged = Bundle.main.resourceURL?.appendingPathComponent("water-mascot.png") {
            candidates.append(packaged)
        }
        if let customPath {
            candidates.append(URL(fileURLWithPath: customPath))
        }

        loadTask = Task { @MainActor in
            for candidate in candidates {
                let bitmap = await MascotBitmapCache.shared.bitmap(at: candidate)
                guard !Task.isCancelled else { return }
                if let bitmap {
                    mascot = NSImage(cgImage: bitmap, size: NSSize(width: bitmap.width, height: bitmap.height))
                }
            }
        }
    }
}

/// An explicitly sized canvas avoids NSImageView's source-image intrinsic size.
struct StaticMascotView: NSViewRepresentable {
    let image: NSImage
    let isAnimating: Bool

    func makeNSView(context: Context) -> MascotCanvas { MascotCanvas(frame: .zero) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MascotCanvas, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 44, height: 40))
    }

    func updateNSView(_ view: MascotCanvas, context: Context) {
        view.setImage(image)
        view.setAnimating(isAnimating)
    }

    static func dismantleNSView(_ view: MascotCanvas, coordinator: Void) { view.setAnimating(false) }
}

final class MascotCanvas: NSView {
    let imageLayer = CALayer()
    private var imageIdentity: ObjectIdentifier?
    override var isOpaque: Bool { false }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)
        setAccessibilityLabel("Water companion")
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Even the largest breathing transform stays inside the allocated slot.
        imageLayer.frame = bounds.insetBy(dx: 2, dy: 2)
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }

    func setImage(_ image: NSImage) {
        guard imageIdentity != ObjectIdentifier(image) else { return }
        imageIdentity = ObjectIdentifier(image)
        imageLayer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        needsLayout = true
    }

    func setAnimating(_ enabled: Bool) {
        guard enabled else { imageLayer.removeAnimation(forKey: "companion.breathe"); return }
        guard imageLayer.animation(forKey: "companion.breathe") == nil else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 1.018
        let float = CABasicAnimation(keyPath: "transform.translation.y")
        float.fromValue = 0
        float.toValue = 1.0
        let group = CAAnimationGroup()
        group.animations = [scale, float]
        group.duration = 2.4
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        imageLayer.add(group, forKey: "companion.breathe")
    }
}

private struct SpriteSheetPlaybackView: View {
    let image: NSImage
    @State private var frameIndex = 0
    @State private var frames: [NSImage] = []
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        Image(nsImage: frames.indices.contains(frameIndex) ? frames[frameIndex] : (SpriteSheetDescriptor.firstFrame(from: image) ?? image))
            .resizable()
            .scaledToFit()
            .onAppear(perform: loadFrames)
            .onReceive(timer) { _ in
                guard !frames.isEmpty else { return }
                frameIndex = (frameIndex + 1) % frames.count
            }
    }

    private func loadFrames() {
        let columns = SpriteSheetDescriptor.grid(for: image)?.columns ?? 1
        frames = (0..<columns).compactMap {
            SpriteSheetDescriptor.frame(from: image, row: 0, column: $0)
        }
        frameIndex = 0
    }
}

enum SpriteSheetDescriptor {
    static func grid(for size: CGSize) -> (columns: Int, rows: Int)? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        if width == 1536, height == 2288 { return (8, 11) }
        if width == 1536, height == 1872 { return (8, 9) }
        return nil
    }

    static func firstFrame(from image: NSImage) -> NSImage? {
        frame(from: image, row: 0, column: 0)
    }

    static func grid(for image: NSImage) -> (columns: Int, rows: Int)? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return grid(for: CGSize(width: source.width, height: source.height))
    }

    static func frame(from image: NSImage, row: Int, column: Int) -> NSImage? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let grid = grid(for: CGSize(width: source.width, height: source.height)),
              row >= 0, row < grid.rows, column >= 0, column < grid.columns else { return nil }
        let cellWidth = source.width / grid.columns
        let cellHeight = source.height / grid.rows
        let rect = CGRect(
            x: column * cellWidth,
            y: source.height - ((row + 1) * cellHeight),
            width: cellWidth,
            height: cellHeight
        )
        guard let frame = source.cropping(to: rect) else { return nil }
        return NSImage(cgImage: frame, size: NSSize(width: cellWidth, height: cellHeight))
    }
}
