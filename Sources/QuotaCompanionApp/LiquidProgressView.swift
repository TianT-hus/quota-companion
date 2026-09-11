import AppKit
import QuotaCore
import SwiftUI

struct LiquidProgressView: NSViewRepresentable {
    let remaining: Double
    let active: Bool
    let stale: Bool
    let appearance: BackgroundAppearance
    var palette: CompanionPalette = .water
    var customTint: QuotaCore.RGBColor? = nil
    func makeNSView(context: Context) -> LiquidProgressCanvas { LiquidProgressCanvas(frame: .zero) }
    func updateNSView(_ view: LiquidProgressCanvas, context: Context) {
        view.update(remaining: remaining, active: active, stale: stale, appearance: appearance, palette: palette, customTint: customTint)
    }
    static func dismantleNSView(_ view: LiquidProgressCanvas, coordinator: Void) { view.stop() }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LiquidProgressCanvas) -> CGSize? {
        CGSize(width: proposal.width ?? 120, height: 14)
    }
}

/// Stable compositor-owned layers: countdown updates never restart the sweep.
final class LiquidProgressCanvas: NSView {
    let track = CAGradientLayer()
    let fill = CAGradientLayer()
    let shine = CAGradientLayer()
    let lip = CAGradientLayer()
    let rim = CALayer()
    private var fraction: CGFloat = 0
    private var wantsAnimation = false
    override var isOpaque: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 14) }
    override init(frame: NSRect) {
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
    func update(remaining: Double, active: Bool, stale: Bool, appearance: BackgroundAppearance, palette: CompanionPalette = .water, customTint: QuotaCore.RGBColor? = nil) {
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
        CATransaction.commit()
        needsLayout = true; layoutSubtreeIfNeeded(); syncAnimation()
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.frame = bounds; track.cornerRadius = bounds.height / 2
        let inner = bounds.insetBy(dx: 1.5, dy: 1.5)
        fill.frame = CGRect(x: inner.minX, y: inner.minY, width: max(0, inner.width) * fraction, height: max(0, inner.height))
        fill.isHidden = fraction == 0
        fill.cornerRadius = max(0, inner.height / 2)
        lip.frame = CGRect(x: 1, y: inner.height * 0.6, width: max(0, fill.bounds.width - 2), height: inner.height * 0.3)
        lip.cornerRadius = inner.height * 0.15
        rim.frame = bounds.insetBy(dx: 0.8, dy: 0.8); rim.cornerRadius = max(0, bounds.height / 2 - 0.8)
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
