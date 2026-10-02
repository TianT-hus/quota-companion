import AppKit
import SwiftUI
import QuotaCore

struct BackgroundCropCanvas: NSViewRepresentable {
    let image: NSImage
    @Binding var composition: BackgroundComposition
    let doubleRow: Bool
    let label: String
    func makeNSView(context: Context) -> CropCanvas { CropCanvas(frame: .zero) }
    func updateNSView(_ view: CropCanvas, context: Context) {
        view.image = image; view.composition = composition; view.doubleRow = doubleRow
        view.changed = { composition = $0 }; view.setAccessibilityLabel(label); view.needsDisplay = true
    }
}

/// Event-driven drawing only; raw pixels remain visible during cropping.
final class CropCanvas: NSView {
    var image: NSImage?
    var composition = BackgroundComposition()
    var doubleRow = false
    var changed: ((BackgroundComposition) -> Void)?
    private var dragStart: CGPoint?
    private var initial = BackgroundComposition()
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var cropFrame: CGRect { CropGeometry.frame(in: bounds, doubleRow: doubleRow) }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityIdentifier("background.crop.canvas")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.08, green: 0.12, blue: 0.18, alpha: 1).setFill(); bounds.fill()
        guard let image else { return }
        let crop = cropFrame
        let radius = crop.width * CompactHoverMetrics.cornerRadius / CompactHoverMetrics.size.width
        let outline = NSBezierPath(cgPath: RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: crop).cgPath)
        NSColor(srgbRed: 0.86, green: 0.94, blue: 0.98, alpha: 1).setFill(); outline.fill()
        let rect = composition.imageRect(image: image.size, viewport: crop.size).offsetBy(dx: crop.minX, dy: crop.minY)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        let dim = NSBezierPath(rect: bounds); dim.append(outline); dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.58).setFill(); dim.fill()
        NSColor.white.setStroke(); outline.lineWidth = 1.5; outline.stroke()
        if dragStart != nil || window?.firstResponder === self {
            NSGraphicsContext.saveGraphicsState(); outline.addClip()
            let grid = NSBezierPath()
            for n in 1...2 {
                let t = CGFloat(n)/3
                grid.move(to: CGPoint(x: crop.minX+crop.width*t, y: crop.minY)); grid.line(to: CGPoint(x: crop.minX+crop.width*t, y: crop.maxY))
                grid.move(to: CGPoint(x: crop.minX, y: crop.minY+crop.height*t)); grid.line(to: CGPoint(x: crop.maxX, y: crop.minY+crop.height*t))
            }
            NSColor.white.withAlphaComponent(0.6).setStroke(); grid.lineWidth = 0.5; grid.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self); dragStart = convert(event.locationInWindow, from: nil); initial = composition; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let image else { return }
        let point = convert(event.locationInWindow, from: nil)
        update(CropGeometry.moved(initial, image: image.size, viewport: cropFrame.size, delta: CGSize(width: point.x-dragStart.x, height: point.y-dragStart.y)))
    }
    override func mouseUp(with event: NSEvent) { dragStart = nil; needsDisplay = true }
    override func magnify(with event: NSEvent) {
        guard let image else { return }
        window?.makeFirstResponder(self)
        update(CropGeometry.zoomed(composition, factor: 1+Double(event.magnification), minimum: BackgroundComposition.minimumZoom(image: image.size, viewport: CropGeometry.frame(in: bounds, doubleRow: doubleRow).size)))
    }
    override func keyDown(with event: NSEvent) {
        guard let image else { return }
        let step = event.modifierFlags.contains(.shift) ? 12.0 : 2.0
        let delta: CGSize
        switch event.keyCode {
        case 123: delta = CGSize(width: -step, height: 0)
        case 124: delta = CGSize(width: step, height: 0)
        case 125: delta = CGSize(width: 0, height: step)
        case 126: delta = CGSize(width: 0, height: -step)
        default: super.keyDown(with: event); return
        }
        update(CropGeometry.moved(composition, image: image.size, viewport: cropFrame.size, delta: delta))
    }
    private func update(_ value: BackgroundComposition) { composition = value; changed?(value); needsDisplay = true }
}
