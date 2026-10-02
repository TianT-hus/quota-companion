import CoreGraphics

/// Logical points shared by the native window and its contents. Quota count
/// changes only the rows, never the hover panel's outer geometry.
enum CompactHoverMetrics {
    static let size = CGSize(width: 150, height: 80)
    static let cornerRadius: CGFloat = 12
    static let quotaHeight: CGFloat = 34
    static let scheduleHeight: CGFloat = 33
    static let progressHeight: CGFloat = 4
    static let controlSize: CGFloat = 14
    static let controlHitSize: CGFloat = 20
    static let overlapInset: CGFloat = 42
    static let edgeInset: CGFloat = 10
    static let verticalInset: CGFloat = 4
}
