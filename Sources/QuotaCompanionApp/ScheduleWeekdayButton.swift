import AppKit
import SwiftUI

struct ScheduleWeekdayButton: NSViewRepresentable {
    let title: String
    @Binding var isOn: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> WeekdayNativeButton {
        let button = WeekdayNativeButton()
        button.setButtonType(.toggle); button.isBordered = false; button.focusRingType = .none
        button.target = context.coordinator; button.action = #selector(Coordinator.toggle(_:))
        return button
    }
    func updateNSView(_ button: WeekdayNativeButton, context: Context) {
        context.coordinator.parent = self
        button.title = title; button.state = isOn ? .on : .off
        button.setAccessibilityLabel(title); button.needsDisplay = true
    }
    final class Coordinator: NSObject {
        var parent: ScheduleWeekdayButton
        init(_ parent: ScheduleWeekdayButton) { self.parent = parent }
        @objc func toggle(_ sender: NSButton) {
            sender.window?.makeFirstResponder(sender)
            parent.isOn = sender.state == .on
        }
    }
}
final class WeekdayNativeButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48, let root = window?.contentView {
            func buttons(in view: NSView) -> [WeekdayNativeButton] {
                (view as? WeekdayNativeButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
            }
            let row = buttons(in: root).sorted { $0.convert($0.bounds, to: root).minX < $1.convert($1.bounds, to: root).minX }
            if let index = row.firstIndex(where: { $0 === self }) {
                let next = index + (event.modifierFlags.contains(.shift) ? -1 : 1)
                if row.indices.contains(next) { window?.makeFirstResponder(row[next]); return }
            }
        }
        super.keyDown(with: event)
    }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return super.resignFirstResponder() }
    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        (selected ? NSColor(ManagementStyle.selection) : NSColor(white: 0.89, alpha: 1)).setFill(); shape.fill()
        let high = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast || effectiveAppearance.name == .accessibilityHighContrastAqua
        if selected { NSColor(ManagementStyle.selectionBorder).setStroke(); shape.lineWidth = high ? 2 : 1; shape.stroke() }
        let text = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .regular), .foregroundColor: NSColor(ManagementStyle.ink)])
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2))
        if window?.firstResponder === self {
            NSColor(ManagementStyle.ink).setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
            focus.lineWidth = 1; focus.setLineDash([2, 2], count: 2, phase: 0); focus.stroke()
        }
    }
}
