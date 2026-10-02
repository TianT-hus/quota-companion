import AppKit
import SwiftUI
import QuotaCore

/// View-only navigation; never stored in schedule data.
struct TimelinePosition {
    var date: Date
    var following = true
    mutating func browse(_ date: Date) { self.date = date; following = false }
    mutating func shiftDay(_ delta: Int, calendar: Calendar = .current) {
        if let next = calendar.date(byAdding: .day, value: delta, to: date) { browse(next) }
    }
    mutating func resume(_ now: Date) { date = now; following = true }
    mutating func tick(_ now: Date) { if following { date = now } }
}

struct CalendarDayView: View {
    @ObservedObject var secretary: SecretaryModel
    let copy: Copybook
    private var position: TimelinePosition {
        get { secretary.calendarPosition }
        nonmutating set { secretary.calendarPosition = newValue }
    }
    @State private var categories = false
    @State private var now = Date()
    @State private var request = UUID()
    private var today: Bool { Calendar.current.isDate(position.date, inSameDayAs: now) }
    private var key: String { SecretaryData.dayKey(position.date) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Button(copy.text("分类", "Categories")) { categories = true }
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                        Text(headerTitle).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                        Button(copy.text("回到现在", "Back to now")) { position.resume(now); request = UUID() }
                            .font(.system(size: 11)).buttonStyle(CalendarPillStyle())
                            .opacity(position.following ? 0 : 1).disabled(position.following)
                            .allowsHitTesting(!position.following).accessibilityHidden(position.following)
                    }
                    Text(position.date.formatted(.dateTime.weekday(.wide).locale(copy.locale))).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel(copy.text("前一天", "Previous day")).buttonStyle(CalendarPillStyle(circle: true))
                Button(copy.text("今天", "Today")) { position.resume(now); request = UUID() }.buttonStyle(CalendarPillStyle())
                Button { shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel(copy.text("后一天", "Next day")).buttonStyle(CalendarPillStyle(circle: true))
            }
            TimelineCanvas(blocks: secretary.calendarBlocks(on: position.date), currentMinute: today ? SecretaryData.minute(now) : nil,
                           following: position.following, request: request,
                           onBrowse: { position.following = false }, onOpen: open)
                .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 6))
                .help(secretary.data.exceptions[key] != nil ? copy.text("当天已有单独安排", "This day has a separate schedule") : copy.text("单击事项编辑 · 双击空白新增", "Click to edit · Double-click empty space to add"))
                .overlay(alignment: .bottomTrailing) {
                    Button { open(nil, minute: today ? SecretaryData.minute(now) : 540) } label: {
                        Image(systemName: "plus").font(.system(size: 20, weight: .medium)).frame(width: 46, height: 46)
                    }.buttonStyle(CalendarFloatingStyle()).accessibilityLabel(copy.text("新增日程", "New event"))
                        .padding(18)
                }
        }
        .ownedSheet(isPresented: $categories) { ScheduleCategoryManager(secretary: secretary, copy: copy) }
        .task {
            update()
            while !Task.isCancelled {
                let delay = 60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
                do { try await Task.sleep(for: .seconds(delay)) } catch { break }
                update()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in update() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in update() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in update() }
        .onChange(of: secretary.editor) { _, editor in if editor != nil { position.following = false } }
    }
    private func update() { now = Date(); if secretary.editor == nil { position.tick(now) } }
    private var headerTitle: String {
        return position.date.formatted(.dateTime.year().month().day().locale(copy.locale))
    }
    private func shift(_ delta: Int) { position.shiftDay(delta); request = UUID() }
    private func open(_ block: ScheduleBlock?, minute: Int) { position.following = false; secretary.editEvent(on: position.date, block: block, minute: minute) }
}

struct TimelineCanvas: NSViewRepresentable {
    let blocks: [ScheduleBlock]
    let currentMinute: Int?
    let following: Bool
    let request: UUID
    let onBrowse: () -> Void
    let onOpen: (ScheduleBlock?, Int) -> Void
    func makeNSView(context: Context) -> CalendarScrollView { CalendarScrollView() }
    func updateNSView(_ view: CalendarScrollView, context: Context) {
        view.onBrowse = onBrowse; view.canvas.onOpen = onOpen
        let changed = view.request != request
        let minuteChanged = view.canvas.currentMinute != currentMinute
        view.canvas.blocks = blocks; view.canvas.currentMinute = currentMinute
        view.request = request
        view.needsLayout = true
        if changed || (following && minuteChanged) {
            view.pendingMinute = currentMinute.flatMap { following ? $0 : nil } ?? blocks.first?.start ?? 540
        }
        view.canvas.needsDisplay = true
    }
}

final class CalendarScrollView: NSScrollView {
    let canvas = CalendarCanvasView()
    var request: UUID?
    var pendingMinute: Int?
    var onBrowse: (() -> Void)?
    private var programmatic = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        hasVerticalScroller = true; drawsBackground = false; documentView = canvas
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged), name: NSView.boundsDidChangeNotification, object: contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(userScroll), name: NSScrollView.willStartLiveScrollNotification, object: self)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    @objc private func boundsChanged() {
        guard !programmatic, let type = NSApp.currentEvent?.type, [.scrollWheel, .leftMouseDragged, .keyDown].contains(type) else { return }
        onBrowse?()
    }
    @objc private func userScroll() { onBrowse?() }
    override func layout() {
        programmatic = true
        super.layout()
        let height = contentSize.height
        canvas.padding = height / 2
        canvas.frame = NSRect(x: 0, y: 0, width: contentSize.width, height: 1728 + height)
        if let minute = pendingMinute, height > 0 {
            contentView.scroll(to: NSPoint(x: 0, y: CGFloat(minute) * 1.2))
            reflectScrolledClipView(contentView); pendingMinute = nil
        }
        programmatic = false
    }
    override func scrollWheel(with event: NSEvent) { onBrowse?(); super.scrollWheel(with: event) }
}

final class CalendarCanvasView: NSView {
    var blocks: [ScheduleBlock] = [] { didSet { if blocks != oldValue { rebuildButtons() } } }
    var currentMinute: Int?
    var padding: CGFloat = 0
    var onOpen: ((ScheduleBlock?, Int) -> Void)?
    private var buttons: [UUID: NSButton] = [:]
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        for block in blocks { buttons[block.id]?.frame = eventRect(block) }
    }
    func eventRect(_ block: ScheduleBlock) -> NSRect {
        NSRect(x: 66, y: padding + CGFloat(block.start) * 1.2, width: max(0, bounds.width - 78), height: CGFloat(block.end - block.start) * 1.2)
    }
    private func rebuildButtons() {
        for button in buttons.values { button.removeFromSuperview() }; buttons.removeAll()
        for block in blocks {
            let button = NSButton(title: "", target: self, action: #selector(selectEvent(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(block.id.uuidString)
            button.isBordered = false; button.setAccessibilityLabel(block.title + ", " + block.timeLabel)
            button.toolTip = block.title + " · " + block.timeLabel
            addSubview(button); buttons[block.id] = button
        }
        needsLayout = true
    }
    @objc private func selectEvent(_ sender: NSButton) {
        if let block = blocks.first(where: { $0.id.uuidString == sender.identifier?.rawValue }) { onOpen?(block, block.start) }
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let minute = Int((point.y - padding) / 1.2)
        if event.clickCount == 2 && (0..<1440).contains(minute) { onOpen?(nil, minute) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); dirtyRect.fill()
        let ink = NSColor(white: 0.16, alpha: 1), gray = NSColor(white: 0.48, alpha: 1)
        func text(_ value: String, at point: NSPoint, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
            (value as NSString).draw(at: point, withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight), .foregroundColor: color])
        }
        for hour in 0...24 {
            let y = padding + CGFloat(hour) * 72
            NSColor(white: 0.9, alpha: 1).setStroke()
            let line = NSBezierPath(); line.move(to: NSPoint(x: 62, y: y)); line.line(to: NSPoint(x: bounds.width, y: y)); line.lineWidth = 0.5; line.stroke()
            text(ScheduleBlock.time(hour * 60), at: NSPoint(x: 10, y: y - 7), size: 11, color: gray)
        }
        for block in blocks {
            let rect = eventRect(block)
            NSGraphicsContext.saveGraphicsState(); rect.clip()
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: min(5, rect.height / 3), yRadius: min(5, rect.height / 3))
            let base = ScheduleEventPalette.color(block.colorHex)
            let tint = base.blended(withFraction: 0.15, of: .white) ?? base
            tint.setFill(); path.fill()
            if rect.height < 11 { NSColor(white: 0.55, alpha: 1).setFill(); rect.fill() }
            if let m = currentMinute, block.start <= m && m < block.end { ink.setStroke(); path.lineWidth = 1; path.stroke() }
            var labelY = rect.minY + (rect.height >= 40 ? 7 : 0)
            if let minute = currentMinute, rect.height >= 65 {
                let lineY = padding + CGFloat(minute) * 1.2
                if (labelY - 2 ... labelY + 34).contains(lineY), lineY + 40 < rect.maxY { labelY = lineY + 6 }
            }
            let rgb = tint.usingColorSpace(.sRGB) ?? tint
            let dark = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent < 0.55
            if rect.height >= 11 { text(block.title, at: NSPoint(x: rect.minX + 9, y: labelY), size: rect.height < 16 ? 10 : 12, color: dark ? .white : ink, weight: .medium) }
            if rect.height >= 40 { text(block.timeLabel, at: NSPoint(x: rect.minX + 9, y: labelY + 17), size: 11, color: dark ? NSColor(white: 0.95, alpha: 1) : gray) }
            NSGraphicsContext.restoreGraphicsState()
        }
        if let minute = currentMinute {
            let y = padding + CGFloat(minute) * 1.2
            NSColor.systemRed.setFill(); NSColor.systemRed.setStroke()
            let line = NSBezierPath(); line.move(to: NSPoint(x: 40, y: y)); line.line(to: NSPoint(x: bounds.width, y: y)); line.lineWidth = 2; line.stroke()
            NSBezierPath(roundedRect: NSRect(x: 2, y: y - 10, width: 54, height: 20), xRadius: 10, yRadius: 10).fill()
            text(ScheduleBlock.time(minute), at: NSPoint(x: 9, y: y - 7), size: 11, color: .white, weight: .semibold)
        }
    }
}
