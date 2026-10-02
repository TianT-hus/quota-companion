import AppKit
import QuotaCore
import SwiftUI

enum LiquidProgressStyle {
    case glass, compact
    var height: CGFloat { self == .compact ? 4 : 14 }
    var inset: CGFloat { self == .compact ? 0.5 : 1.5 }
}

struct LiquidProgressView: NSViewRepresentable {
    let remaining: Double
    let active: Bool
    let stale: Bool
    let appearance: BackgroundAppearance
    var palette: CompanionPalette = .water
    var customTint: QuotaCore.RGBColor? = nil
    var style: LiquidProgressStyle = .glass
    var highContrast = false
    var renderScale: CGFloat = 1
    func makeNSView(context: Context) -> LiquidProgressCanvas { LiquidProgressCanvas(frame: .zero, style: style) }
    func updateNSView(_ view: LiquidProgressCanvas, context: Context) {
        view.renderScale = renderScale
        view.update(remaining: remaining, active: active, stale: stale, appearance: appearance, palette: palette, customTint: customTint, highContrast: highContrast)
    }
    static func dismantleNSView(_ view: LiquidProgressCanvas, coordinator: Void) { view.stop() }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LiquidProgressCanvas) -> CGSize? {
        CGSize(width: proposal.width ?? 120, height: style.height * renderScale)
    }
}

/// Stable compositor-owned layers: countdown updates never restart the sweep.
final class LiquidProgressCanvas: NSView {
    let style: LiquidProgressStyle
    var renderScale: CGFloat = 1 { didSet { if renderScale != oldValue { invalidateIntrinsicContentSize(); needsLayout = true } } }
    let track = CAGradientLayer()
    let fill = CAGradientLayer()
    let shine = CAGradientLayer()
    let lip = CAGradientLayer()
    let rim = CALayer()
    private var fraction: CGFloat = 0
    private var wantsAnimation = false
    override var isOpaque: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: style.height * renderScale) }
    override convenience init(frame: NSRect) { self.init(frame: frame, style: .glass) }
    init(frame: NSRect, style: LiquidProgressStyle) {
        self.style = style
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(track); track.addSublayer(fill); fill.addSublayer(shine)
        fill.addSublayer(lip); layer?.addSublayer(rim)
        track.masksToBounds = true; fill.masksToBounds = true
        fill.startPoint = CGPoint(x: 0.5, y: 1); fill.endPoint = CGPoint(x: 0.5, y: 0)
        track.startPoint = CGPoint(x: 0.5, y: 1); track.endPoint = CGPoint(x: 0.5, y: 0)
        lip.colors = [NSColor.white.withAlphaComponent(0.8).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        lip.startPoint = CGPoint(x: 0.5, y: 1); lip.endPoint = CGPoint(x: 0.5, y: 0)
        rim.borderWidth = 0.8; rim.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        shine.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(0.5).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        shine.locations = [0, 0.5, 1]
        shine.startPoint = CGPoint(x: 0, y: 0.5); shine.endPoint = CGPoint(x: 1, y: 0.5)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func update(remaining: Double, active: Bool, stale: Bool, appearance: BackgroundAppearance, palette: CompanionPalette = .water, customTint: QuotaCore.RGBColor? = nil, highContrast: Bool = false) {
        fraction = remaining.isFinite ? CGFloat(min(100, max(0, remaining)) / 100) : 0
        wantsAnimation = active && !stale && fraction > 0
        func cg(_ c: QuotaCore.RGBColor) -> CGColor { NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1).cgColor }
        let edge = stale ? appearance.secondary : appearance.progressColor(remaining: remaining, palette: palette, customTint: customTint)
        let water = QuotaColorBand.forRemaining(remaining) == .healthy ? (customTint ?? (palette == .water ? QuotaCore.RGBColor(hex: 0x15C4EA) : palette.color)) : edge
        let main = stale ? edge.mixed(with: appearance.base, amount: 0.3) : water
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.colors = [cg(QuotaCore.RGBColor(hex: 0x8DA7C0)), cg(QuotaCore.RGBColor(hex: 0xC8DCEB))]
        track.borderWidth = 0.8; track.borderColor = cg(QuotaCore.RGBColor(hex: 0x7390AD))
        fill.colors = [cg(main.mixed(with: QuotaCore.RGBColor(hex: 0xF4FDFF), amount: 0.8)), cg(main), cg(main.mixed(with: edge, amount: 0.6))]
        fill.locations = [0, 0.45, 1]
        fill.borderWidth = 0.8; fill.borderColor = cg(edge)
        if style == .compact {
            track.colors = [cg(QuotaCore.RGBColor(hex: 0xD3EBF7)), cg(QuotaCore.RGBColor(hex: 0xEAF8FF))]
            track.borderWidth = (highContrast ? 0.75 : 0.5) * renderScale
            track.borderColor = cg(highContrast ? appearance.text : QuotaCore.RGBColor(hex: 0x8CACBF))
            fill.colors = [cg(main.mixed(with: QuotaCore.RGBColor(hex: 0xF4FDFF), amount: 0.25)), cg(main), cg(main.mixed(with: edge, amount: 0.15))]
            fill.borderWidth = 0
            rim.borderWidth = highContrast ? 0 : 0.5 * renderScale
        }
        CATransaction.commit()
        needsLayout = true; layoutSubtreeIfNeeded(); syncAnimation()
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.frame = bounds; track.cornerRadius = bounds.height / 2
        let inner = bounds.insetBy(dx: min(style.inset * renderScale, bounds.width / 2), dy: min(style.inset * renderScale, bounds.height / 2))
        fill.frame = CGRect(x: inner.minX, y: inner.minY, width: max(0, inner.width) * fraction, height: max(0, inner.height))
        fill.isHidden = fraction == 0
        fill.cornerRadius = max(0, inner.height / 2)
        let lipInset: CGFloat = style == .compact ? 0 : 1
        lip.frame = CGRect(x: lipInset, y: inner.height * 0.6, width: max(0, fill.bounds.width - 2 * lipInset), height: inner.height * 0.3)
        lip.cornerRadius = inner.height * 0.15
        let rimInset: CGFloat = (style == .compact ? 0.25 : 0.8) * renderScale
        rim.frame = bounds.insetBy(dx: rimInset, dy: rimInset); rim.cornerRadius = max(0, bounds.height / 2 - rimInset)
        shine.frame = CGRect(x: -bounds.width, y: 0, width: bounds.width, height: bounds.height / 2)
        CATransaction.commit()
        syncAnimation()
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); syncAnimation() }
    func stop() { shine.removeAnimation(forKey: "flow") }
    private func syncAnimation() {
        guard wantsAnimation, window != nil, bounds.width > 0 else { stop(); return }
        guard shine.animation(forKey: "flow") == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0; animation.toValue = bounds.width * 2
        animation.duration = 5; animation.repeatCount = .infinity
        animation.beginTime = CACurrentMediaTime()
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        shine.add(animation, forKey: "flow")
    }
}
