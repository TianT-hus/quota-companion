import Foundation

public enum CropGeometry {
    public static func frame(in bounds: CGRect, doubleRow: Bool) -> CGRect {
        let ratio = 200.0 / (doubleRow ? 80.0 : 56.0)
        let width = max(1, min(bounds.width - 64, (bounds.height - 64) * ratio))
        return CGRect(x: bounds.midX-width/2, y: bounds.midY-width/ratio/2, width: width, height: width/ratio)
    }
    public static func moved(_ original: BackgroundComposition, image: CGSize, viewport: CGSize, delta: CGSize) -> BackgroundComposition {
        let rect = original.imageRect(image: image, viewport: viewport)
        guard rect.width > 0, rect.height > 0 else { return original }
        let dx = viewport.width-rect.width, dy = viewport.height-rect.height
        let left = min(max(0, dx), max(min(0, dx), rect.minX+delta.width))
        let top = min(max(0, dy), max(min(0, dy), rect.minY+delta.height))
        var next = original
        next.x = dx > 0 ? 1-left/dx : (viewport.width/2-left)/rect.width
        next.y = dy > 0 ? 1-top/dy : (viewport.height/2-top)/rect.height
        next.darkestPixelHex = nil
        return next
    }
    public static func zoomed(_ original: BackgroundComposition, factor: Double, minimum: Double = 1) -> BackgroundComposition {
        guard factor.isFinite, factor > 0 else { return original }
        var next = original
        next.zoom = min(4, max(minimum, original.zoom*factor)); next.darkestPixelHex = nil
        return next
    }
}
