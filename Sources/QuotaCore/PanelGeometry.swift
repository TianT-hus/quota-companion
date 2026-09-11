import CoreGraphics
import Foundation

public enum CompanionPresentation: String, Codable, Sendable, CaseIterable {
    case collapsed
    case expanded

    public var size: CGSize {
        CompanionLayout(presentation: self, windowCount: 1).size
    }
}

/// One source of truth for the native window, hosting view and clipping outline.
/// Layout is transient; existing saved origins and quota snapshots stay unchanged.
public struct CompanionLayout: Equatable, Sendable {
    public let presentation: CompanionPresentation
    public let size: CGSize
    public let idealSize: CGSize
    public var cornerRadius: CGFloat {
        presentation == .collapsed ? min(size.width, size.height) / 2 : 24
    }

    public init(presentation: CompanionPresentation, windowCount: Int, availableSize: CGSize? = nil) {
        self.presentation = presentation
        idealSize = presentation == .collapsed
            ? CGSize(width: 56, height: 56)
            : CGSize(width: 240, height: 156 + 48 * CGFloat(max(1, windowCount) - 1))
        if let availableSize {
            size = CGSize(width: min(idealSize.width, max(1, availableSize.width)),
                          height: min(idealSize.height, max(1, availableSize.height)))
        } else {
            size = idealSize
        }
    }

    public func matches(_ actual: CGSize, tolerance: CGFloat = 0.5) -> Bool {
        actual.width.isFinite && actual.height.isFinite &&
            abs(actual.width - size.width) <= tolerance && abs(actual.height - size.height) <= tolerance
    }
}

public struct PanelEdgeAnchor: Equatable, Sendable {
    public enum Horizontal: Sendable { case leading, trailing }
    public enum Vertical: Sendable { case bottom, top }

    public let horizontal: Horizontal
    public let vertical: Vertical

    public init(horizontal: Horizontal, vertical: Vertical) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

public enum PointerIntent: Equatable, Sendable {
    case click
    case drag

    public static func classify(delta: CGSize, threshold: CGFloat = 4) -> Self {
        hypot(delta.width, delta.height) >= threshold ? .drag : .click
    }
}

public enum PanelGeometry {
    public static func restoredFrame(savedCollapsedOrigin: CGPoint, layout: CompanionLayout, in visibleFrame: CGRect) -> CGRect {
        let collapsed = constrained(CGRect(origin: savedCollapsedOrigin, size: CompanionPresentation.collapsed.size), to: visibleFrame)
        return resizedFrame(from: collapsed, to: layout.size, in: visibleFrame)
    }

    public static func nearestAnchor(for frame: CGRect, in visibleFrame: CGRect) -> PanelEdgeAnchor {
        let horizontal: PanelEdgeAnchor.Horizontal =
            abs(frame.minX - visibleFrame.minX) <= abs(visibleFrame.maxX - frame.maxX) ? .leading : .trailing
        let vertical: PanelEdgeAnchor.Vertical =
            abs(frame.minY - visibleFrame.minY) <= abs(visibleFrame.maxY - frame.maxY) ? .bottom : .top
        return PanelEdgeAnchor(horizontal: horizontal, vertical: vertical)
    }

    public static func resizedFrame(
        from current: CGRect,
        to size: CGSize,
        in visibleFrame: CGRect,
        preserving anchor: PanelEdgeAnchor? = nil
    ) -> CGRect {
        let anchor = anchor ?? nearestAnchor(for: current, in: visibleFrame)
        let x = anchor.horizontal == .trailing ? current.maxX - size.width : current.minX
        let y = anchor.vertical == .top ? current.maxY - size.height : current.minY
        return constrained(CGRect(origin: CGPoint(x: x, y: y), size: size), to: visibleFrame)
    }

    public static func snappedFrame(
        _ frame: CGRect,
        in visibleFrame: CGRect,
        threshold: CGFloat = 48,
        margin: CGFloat = 14
    ) -> CGRect {
        var result = constrained(frame, to: visibleFrame)
        let leftDistance = abs(result.minX - visibleFrame.minX)
        let rightDistance = abs(visibleFrame.maxX - result.maxX)
        let bottomDistance = abs(result.minY - visibleFrame.minY)
        let topDistance = abs(visibleFrame.maxY - result.maxY)

        if min(leftDistance, rightDistance) < threshold {
            result.origin.x = leftDistance <= rightDistance
                ? visibleFrame.minX + margin
                : visibleFrame.maxX - result.width - margin
        }
        if min(bottomDistance, topDistance) < threshold {
            result.origin.y = bottomDistance <= topDistance
                ? visibleFrame.minY + margin
                : visibleFrame.maxY - result.height - margin
        }
        return constrained(result, to: visibleFrame)
    }

    public static func constrained(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        var result = frame
        result.size.width = min(result.width, visibleFrame.width)
        result.size.height = min(result.height, visibleFrame.height)
        result.origin.x = min(max(result.minX, visibleFrame.minX), visibleFrame.maxX - result.width)
        result.origin.y = min(max(result.minY, visibleFrame.minY), visibleFrame.maxY - result.height)
        return result
    }

    public static func matches(_ actual: CGSize, presentation: CompanionPresentation, tolerance: CGFloat = 0.5) -> Bool {
        abs(actual.width - presentation.size.width) <= tolerance &&
            abs(actual.height - presentation.size.height) <= tolerance
    }
}
