import Foundation

public enum PetPresentation: String, Sendable { case petOnly, hoverDetails, keyboardDetails }

/// Pure, monotonic-clock state machine. Transient interaction is never persisted.
public struct PetInteraction: Equatable, Sendable {
    public private(set) var mode: PetPresentation = .petOnly
    public private(set) var insidePet = false
    public private(set) var insideRegion = false
    public private(set) var suppressed = false
    public private(set) var dragging = false
    public private(set) var holds = 0
    public private(set) var openAt: Double?
    public private(set) var closeAt: Double?
    public init() {}
    public mutating func pointer(pet: Bool, region: Bool, now: Double) {
        if !pet { suppressed = false }
        if pet && !insidePet && !suppressed && !dragging && mode == .petOnly { openAt = now + 0.15 }
        insidePet = pet; insideRegion = region
        if !pet { openAt = nil }
        if region || holds > 0 || dragging { closeAt = nil }
        else if mode == .hoverDetails && closeAt == nil { closeAt = now + 0.3 }
    }
    public mutating func tick(now: Double) {
        guard !dragging, holds == 0 else { return }
        if let deadline = openAt, now >= deadline, insidePet, !suppressed {
            mode = .hoverDetails; openAt = nil
        }
        if let deadline = closeAt, now >= deadline, !insideRegion {
            mode = .petOnly; closeAt = nil
        }
    }
    public mutating func showPinned() { mode = .keyboardDetails; openAt = nil; closeAt = nil }
    public mutating func showTemporary(now: Double) {
        mode = .hoverDetails; openAt = nil; closeAt = insideRegion ? nil : now + 3
    }
    public mutating func releaseKeyboard(now: Double) {
        guard mode == .keyboardDetails else { return }
        mode = .hoverDetails; closeAt = insideRegion ? nil : now + 0.3
    }
    public mutating func close() { mode = .petOnly; suppressed = insidePet; openAt = nil; closeAt = nil }
    public mutating func click(now: Double = ProcessInfo.processInfo.systemUptime) {
        mode = .hoverDetails; openAt = nil; closeAt = insideRegion ? nil : now + 0.3
    }
    public mutating func togglePin(now: Double) {
        if mode == .keyboardDetails {
            mode = .hoverDetails
            closeAt = insideRegion ? nil : now + 0.3
        } else { showPinned() }
    }
    public mutating func beginDrag() {
        dragging = true; openAt = nil; closeAt = nil
        mode = .petOnly
    }
    public mutating func endDrag() { dragging = false; suppressed = true; openAt = nil }
    public mutating func hold(_ active: Bool, now: Double) {
        holds = max(0, holds + (active ? 1 : -1))
        if holds > 0 { closeAt = nil; openAt = nil }
        else if mode == .hoverDetails && !insideRegion { closeAt = now + 0.3 }
    }
}

public enum DetailDirection: String, CaseIterable, Sendable { case right, left, above, below }
/// One source of truth for the glass card and its detached controls (unscaled points).
public struct GlassDetailMetrics: Equatable, Sendable {
    public let cardHeight: Double
    public let cardWidth = 200.0
    public let controlWidth = 28.0
    public let controlGap = 8.0
    public init(windowCount: Int) { cardHeight = windowCount > 1 ? 80 : 56 }
    public var size: CGSize { CGSize(width: cardWidth + controlGap + controlWidth, height: max(cardHeight, 60)) }
}
public struct PetPanelLayout: Equatable, Sendable {
    public static let petSize = CGSize(width: 72, height: 80)
    public static let detailSize = GlassDetailMetrics(windowCount: 2).size
    public let pet: CGRect
    public let detail: CGRect
    public let direction: DetailDirection
    public let bridge: CGRect
    public init(pet: CGRect, windowCount: Int, screen: CGRect, scale: Double = 1, detailSize: CGSize? = nil) {
        let overlap = 36 * scale, gap = 8 * scale
        self.pet = pet
        let base = detailSize ?? GlassDetailMetrics(windowCount: windowCount).size
        let ideal = CGSize(width: base.width * scale, height: base.height * scale)
        let spaces: [(DetailDirection, CGRect)] = [
            (.right, CGRect(x: pet.maxX - overlap, y: screen.minY, width: max(0, screen.maxX - pet.maxX + overlap), height: screen.height)),
            (.left, CGRect(x: screen.minX, y: screen.minY, width: max(0, pet.minX - screen.minX + overlap), height: screen.height)),
            (.above, CGRect(x: screen.minX, y: pet.maxY + gap, width: screen.width, height: max(0, screen.maxY - pet.maxY - gap))),
            (.below, CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: max(0, pet.minY - screen.minY - gap)))
        ]
        let chosen = spaces.first { $0.1.width >= ideal.width && $0.1.height >= ideal.height }
            ?? spaces.max { $0.1.width * $0.1.height < $1.1.width * $1.1.height }!
        direction = chosen.0
        let size = CGSize(width: min(ideal.width, chosen.1.width), height: min(ideal.height, chosen.1.height))
        let origin: CGPoint = switch direction {
        case .right: CGPoint(x: pet.maxX - overlap, y: pet.midY - size.height / 2)
        case .left: CGPoint(x: pet.minX - size.width + overlap, y: pet.midY - size.height / 2)
        case .above: CGPoint(x: pet.midX - size.width / 2, y: pet.maxY + gap)
        case .below: CGPoint(x: pet.midX - size.width / 2, y: pet.minY - size.height - gap)
        }
        detail = PanelGeometry.constrained(CGRect(origin: origin, size: size), to: chosen.1)
        switch direction {
        case .right, .left:
            bridge = pet.intersection(detail)
        case .above, .below:
            bridge = CGRect(x: max(pet.minX, detail.minX), y: min(pet.maxY, detail.maxY),
                            width: max(0, min(pet.maxX, detail.maxX) - max(pet.minX, detail.minX)), height: gap)
        }
    }
    public func contains(_ point: CGPoint) -> Bool { pet.contains(point) || detail.contains(point) || bridge.contains(point) }
}

public enum PixelCatGeometry {
    public static let rows = 36
    public static func filledRows(remaining: Double?) -> Int {
        guard let remaining, remaining.isFinite else { return 0 }
        return Int((Double(rows) * min(100, max(0, remaining)) / 100).rounded())
    }
}
