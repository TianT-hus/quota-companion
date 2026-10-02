import AppKit
import SwiftUI

struct SegmentedScheduleTime: View {
    @Binding var hour: String
    @Binding var minute: String
    let label: String
    let focus: Int
    let hourFocus: Int
    var endTime = false
    var body: some View {
        HStack(spacing: 0) {
            TimeSegment(text: $hour, label: label + " · HH", focus: focus, token: hourFocus, maximum: endTime ? 24 : 23)
            Text(":")
            TimeSegment(text: $minute, label: label + " · mm", focus: focus, token: hourFocus + 1, maximum: 59)
        }.frame(width: 70, height: 28).padding(.horizontal, 5)
            .background(Color.gray.opacity(0.08), in: Capsule())
    }
    static func value(_ hour: String, _ minute: String, end: Bool) -> Int? {
        guard !hour.isEmpty, !minute.isEmpty, hour.count <= 2, minute.count <= 2,
              (hour + minute).utf8.allSatisfy({ (48...57).contains($0) }),
              let h = Int(hour), let m = Int(minute), (0...59).contains(m),
              (0...23).contains(h) || (end && h == 24 && m == 0) else { return nil }
        return h * 60 + m
    }
}
enum TimeSegmentInput {
    static func accepts(_ value: String) -> Bool {
        value.utf8.count <= 2 && value.utf8.allSatisfy { (48...57).contains($0) }
    }
    static func accepts(_ text: String, range: NSRange, replacement: String) -> Bool {
        guard let range = Range(range, in: text) else { return false }
        return accepts(text.replacingCharacters(in: range, with: replacement))
    }
}
final class TimeSegmentFormatter: Formatter {
    override func string(for obj: Any?) -> String? { obj as? String }
    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        guard TimeSegmentInput.accepts(string) else { return false }
        obj?.pointee = string as NSString; return true
    }
    override func isPartialStringValid(_ partialString: String, newEditingString: AutoreleasingUnsafeMutablePointer<NSString?>?, errorDescription: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        TimeSegmentInput.accepts(partialString)
    }
}
final class SegmentFieldEditor: NSTextView {
    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let replacementString, TimeSegmentInput.accepts(string, range: affectedCharRange, replacement: replacementString) else { return false }
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let value = (string as? NSAttributedString)?.string ?? (string as? String ?? "")
        let range = replacementRange.location == NSNotFound ? self.selectedRange() : replacementRange
        guard TimeSegmentInput.accepts(self.string, range: range, replacement: value) else { NSSound.beep(); return }
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }
    override func mouseDown(with event: NSEvent) { super.mouseDown(with: event); selectAll(nil) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 124 { insertTab(nil); return }
        if event.keyCode == 123 { insertBacktab(nil); return }
        super.keyDown(with: event)
    }
}
private final class SegmentCell: NSTextFieldCell {
    private lazy var editor: NSTextView = {
        let view = SegmentFieldEditor(); view.isFieldEditor = true; return view
    }()
    override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
}
private final class SegmentTextField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        selectText(nil)
    }
}
private struct TimeSegment: NSViewRepresentable {
    @Binding var text: String
    let label: String
    let focus: Int
    let token: Int
    let maximum: Int
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = SegmentTextField(string: text)
        field.cell = SegmentCell(textCell: text)
        field.formatter = TimeSegmentFormatter()
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.isEditable = true; field.isSelectable = true
        field.delegate = context.coordinator; field.isBordered = false; field.drawsBackground = false
        field.focusRingType = .none; field.alignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.setAccessibilityLabel(label)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if focus == token && context.coordinator.lastFocus != focus {
            context.coordinator.lastFocus = focus
            DispatchQueue.main.async { field.window?.makeFirstResponder(field); field.selectText(nil) }
        } else if focus != token { context.coordinator.lastFocus = -1 }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TimeSegment
        var lastFocus = -1
        init(_ parent: TimeSegment) { self.parent = parent }
        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: field.stringValue.utf16.count)
        }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            if let value = Int(parent.text), (0...parent.maximum).contains(value), parent.text.count <= 2 {
                parent.text = String(format: "%02d", value)
            }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if ["moveLeft:", "moveBackward:"].contains(NSStringFromSelector(selector)) { control.window?.selectPreviousKeyView(control); return true }
            if ["moveRight:", "moveForward:"].contains(NSStringFromSelector(selector)) { control.window?.selectNextKeyView(control); return true }
            if selector == #selector(NSResponder.moveUp(_:)) || selector == #selector(NSResponder.moveDown(_:)) {
                guard let n = Int(parent.text), (0...parent.maximum).contains(n) else { return true }
                let next = n + (selector == #selector(NSResponder.moveUp(_:)) ? 1 : -1)
                guard (0...parent.maximum).contains(next) else { return true }
                parent.text = String(format: "%02d", next); control.stringValue = parent.text
                textView.string = parent.text; textView.selectAll(nil); return true
            }
            return false
        }
    }
}
