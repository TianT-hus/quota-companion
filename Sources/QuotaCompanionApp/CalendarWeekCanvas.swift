import AppKit
import SwiftUI
import QuotaCore

struct CalendarWeekCanvas: NSViewRepresentable {
    let dates: [Date]
    let blocks: [[ScheduleBlock]]
    let now: Date
    let selectedDate: Date
    let copy: Copybook
    let following: Bool
    let request: UUID
    let onBrowse: () -> Void
    let onSelectDate: (Date) -> Void
    let onOpen: (Date, ScheduleBlock?, Int) -> Void
    func makeNSView(context: Context) -> WeekTimelineView { WeekTimelineView() }
    func updateNSView(_ view: WeekTimelineView, context: Context) {
        let changed = view.request != request
        let minute = SecretaryData.minute(now)
        let ticked = view.grid.minute != minute
        view.request = request; view.scroll.onBrowse = onBrowse
        view.grid.onOpen = onOpen; view.header.onSelect = onSelectDate
        view.header.selectedDate = selectedDate; view.header.locale = copy.locale
        view.header.dates = dates; view.header.today = now
        view.grid.dates = dates; view.grid.today = now; view.grid.minute = minute
        view.grid.setBlocks(blocks)
        if changed || (following && ticked) { view.pendingMinute = following ? minute : 540 }
        view.needsLayout = true; view.grid.needsDisplay = true; view.header.needsDisplay = true
    }
}

final class WeekTimelineView: NSView {
    let scroll = WeekScrollView()
    let grid = WeekGridView()
    let header = WeekHeaderView()
    let axis = WeekAxisView()
    var request: UUID?
    var pendingMinute: Int?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.documentView = grid; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false; scroll.contentView.postsBoundsChangedNotifications = true
        addSubview(scroll); addSubview(header); addSubview(axis)
        NotificationCenter.default.addObserver(self, selector: #selector(sync), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func layout() {
        super.layout()
        scroll.frame = NSRect(x: 62, y: 36, width: max(0, bounds.width - 62), height: max(0, bounds.height - 36))
        header.frame = NSRect(x: 62, y: 0, width: scroll.contentSize.width, height: 36)
        axis.frame = NSRect(x: 0, y: 36, width: 62, height: scroll.contentSize.height)
        grid.columnWidth = max(88, scroll.contentSize.width / 7)
        grid.padding = scroll.contentSize.height / 2
        grid.frame = NSRect(x: 0, y: 0, width: grid.columnWidth * 7, height: 1728 + scroll.contentSize.height)
        grid.needsLayout = true
        if let minute = pendingMinute {
            scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: CGFloat(minute) * 1.2))
            scroll.reflectScrolledClipView(scroll.contentView); pendingMinute = nil
        }
        sync()
    }
    @objc private func sync() {
        header.offset = scroll.contentView.bounds.minX; header.columnWidth = grid.columnWidth
        axis.offset = scroll.contentView.bounds.minY; axis.padding = grid.padding
        axis.minute = grid.dates.contains(where: { Calendar.current.isDate($0, inSameDayAs: grid.today) }) ? grid.minute : nil
        header.needsLayout = true; header.needsDisplay = true; axis.needsDisplay = true
    }
}

final class WeekScrollView: NSScrollView {
    var onBrowse: (() -> Void)?
    override func scrollWheel(with event: NSEvent) { onBrowse?(); super.scrollWheel(with: event) }
    override func keyDown(with event: NSEvent) { onBrowse?(); super.keyDown(with: event) }
    override func reflectScrolledClipView(_ cView: NSClipView) {
        if let type = NSApp.currentEvent?.type, [.leftMouseDragged, .keyDown].contains(type) { onBrowse?() }
        super.reflectScrolledClipView(cView)
    }
}

private func weekText(_ value: String, rect: NSRect, size: CGFloat, color: NSColor, bold: Bool = false) {
    let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
    (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: color, .paragraphStyle: style])
}

final class WeekHeaderView: NSView {
    var dates: [Date] = [] { didSet { if dates != oldValue { rebuild() } } }
    var today = Date()
    var selectedDate = Date()
    var locale = Locale.current
    var offset: CGFloat = 0
    var columnWidth: CGFloat = 88
    var onSelect: ((Date) -> Void)?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer?.masksToBounds = true }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        for (i, _) in dates.enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(selectDate(_:)))
            button.tag = i; button.isBordered = false; addSubview(button)
        }
        needsLayout = true
    }
    @objc private func selectDate(_ sender: NSButton) { if dates.indices.contains(sender.tag) { onSelect?(dates[sender.tag]) } }
    override func layout() {
        super.layout()
        for case let button as NSButton in subviews {
            let date = dates[button.tag]
            button.frame = NSRect(x: CGFloat(button.tag) * columnWidth - offset, y: 0, width: columnWidth, height: 36)
            button.title = date.formatted(.dateTime.day().weekday(.abbreviated).locale(locale))
            button.font = .systemFont(ofSize: 12, weight: Calendar.current.isDate(date, inSameDayAs: selectedDate) ? .bold : .regular)
            button.contentTintColor = Calendar.current.isDate(date, inSameDayAs: today) ? .systemBlue : .labelColor
            button.setAccessibilityLabel(date.formatted(.dateTime.year().month().day().weekday().locale(locale)))
        }
    }
}

final class WeekAxisView: NSView {
    var offset: CGFloat = 0
    var padding: CGFloat = 0
    var minute: Int?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        bounds.clip()
        NSColor.white.setFill(); dirtyRect.intersection(bounds).fill()
        for hour in 0...24 {
            let y = padding + CGFloat(hour) * 72 - offset
            weekText(ScheduleBlock.time(hour * 60), rect: NSRect(x: 6, y: y - 7, width: 54, height: 17), size: 11, color: .secondaryLabelColor)
        }
        if let minute {
            let y = padding + CGFloat(minute) * 1.2 - offset
            let rect = NSRect(x: 2, y: y - 10, width: 55, height: 20)
            NSColor.systemRed.setFill(); NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            weekText(ScheduleBlock.time(minute), rect: rect.insetBy(dx: 5, dy: 2), size: 11, color: .white, bold: true)
        }
    }
}

final class WeekGridView: NSView {
    struct Occurrence { let date: Date; let column: Int; let block: ScheduleBlock; var id: String { SecretaryData.dayKey(date) + ":" + block.id.uuidString } }
    var dates: [Date] = []
    var today = Date()
    var minute = 0
    var columnWidth: CGFloat = 88
    var padding: CGFloat = 0
    var onOpen: ((Date, ScheduleBlock?, Int) -> Void)?
    private(set) var occurrences: [Occurrence] = []
    private var signature = ""
    private var buttons: [String: NSButton] = [:]
    override var isFlipped: Bool { true }
    func setBlocks(_ values: [[ScheduleBlock]]) {
        occurrences = dates.enumerated().flatMap { index, date in
            (values.indices.contains(index) ? values[index] : []).map { Occurrence(date: date, column: index, block: $0) }
        }
        let next = occurrences.map { $0.id + $0.block.title + $0.block.timeLabel }.joined(separator: "|")
        guard next != signature else { return }; signature = next
        buttons.values.forEach { $0.removeFromSuperview() }; buttons.removeAll()
        for occurrence in occurrences {
            let button = NSButton(title: "", target: self, action: #selector(openEvent(_:)))
            button.identifier = .init(occurrence.id); button.isBordered = false
            let description = SecretaryData.dayKey(occurrence.date) + " · " + occurrence.block.timeLabel + " · " + occurrence.block.title
            button.toolTip = description; button.setAccessibilityLabel(description)
            addSubview(button); buttons[occurrence.id] = button
        }
        needsLayout = true
    }
    func eventRect(_ occurrence: Occurrence) -> NSRect {
        NSRect(x: CGFloat(occurrence.column) * columnWidth + 2, y: padding + CGFloat(occurrence.block.start) * 1.2, width: columnWidth - 4, height: CGFloat(occurrence.block.end - occurrence.block.start) * 1.2)
    }
    override func layout() { super.layout(); for occurrence in occurrences { buttons[occurrence.id]?.frame = eventRect(occurrence) } }
    @objc private func openEvent(_ button: NSButton) {
        guard let occurrence = occurrences.first(where: { $0.id == button.identifier?.rawValue }) else { return }
        onOpen?(occurrence.date, occurrence.block, occurrence.block.start)
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let column = Int(point.x / columnWidth), minute = Int((point.y - padding) / 1.2)
        if event.clickCount == 2, dates.indices.contains(column), (0..<1440).contains(minute) { onOpen?(dates[column], nil, minute) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); dirtyRect.fill()
        NSColor.separatorColor.setStroke()
        let lines = NSBezierPath(); lines.lineWidth = 0.5
        for column in 0...7 { let x = CGFloat(column) * columnWidth; lines.move(to: NSPoint(x: x,y: 0)); lines.line(to: NSPoint(x: x,y: bounds.height)) }
        for hour in 0...24 { let y = padding + CGFloat(hour) * 72; lines.move(to: NSPoint(x: 0,y: y)); lines.line(to: NSPoint(x: bounds.width,y: y)) }; lines.stroke()
        for occurrence in occurrences {
            let rect = eventRect(occurrence); guard rect.intersects(dirtyRect) else { continue }
            let base = ScheduleEventPalette.color(occurrence.block.colorHex)
            let color = (base.blended(withFraction: 0.15, of: .white) ?? base).usingColorSpace(.sRGB) ?? .lightGray
            color.setFill(); NSBezierPath(roundedRect: rect, xRadius: min(4, rect.height / 3), yRadius: min(4, rect.height / 3)).fill()
            let dark = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent < 0.55
            let ink: NSColor = dark ? .white : .labelColor
            NSGraphicsContext.saveGraphicsState(); rect.clip()
            if rect.height >= 13 { weekText(occurrence.block.title, rect: NSRect(x: rect.minX + 5,y: rect.minY + 3,width: rect.width - 10,height: min(32, rect.height - 3)),size: 12,color: ink,bold: true) }
            if rect.height >= 55 { weekText(occurrence.block.timeLabel, rect: NSRect(x: rect.minX + 5,y: rect.minY + 36,width: rect.width - 10,height: 15),size: 11,color: ink) }
            NSGraphicsContext.restoreGraphicsState()
        }
        if let column = dates.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: today) }) {
            NSColor.systemRed.setStroke(); let path = NSBezierPath(); path.lineWidth = 2
            let y = padding + CGFloat(minute) * 1.2
            path.move(to: NSPoint(x: CGFloat(column) * columnWidth, y: y)); path.line(to: NSPoint(x: CGFloat(column+1) * columnWidth,y: y)); path.stroke()
        }
    }
}
