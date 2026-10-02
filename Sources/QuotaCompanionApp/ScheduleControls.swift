import AppKit
import SwiftUI
import QuotaCore

struct CalendarPillStyle: ButtonStyle {
    var circle = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13)).foregroundStyle(ManagementStyle.ink)
            .padding(.horizontal, circle ? 0 : 12).frame(width: circle ? 28 : nil, height: 28)
            .background(Color.gray.opacity(configuration.isPressed ? 0.22 : 0.12), in: Capsule())
            .contentShape(Capsule()).transaction { $0.animation = nil }
    }
}
struct CalendarFloatingStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(ManagementStyle.ink)
            .background(.regularMaterial, in: Circle())
            .background(Color.gray.opacity(configuration.isPressed ? 0.24 : 0.12), in: Circle())
            .overlay(Circle().strokeBorder(.gray.opacity(0.15)))
            .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
            .contentShape(Circle()).transaction { $0.animation = nil }
    }
}

enum ScheduleEventPalette {
    static let presets: [(hex: String, zh: String, en: String)] = [
        ("D8E8FA", "蓝色", "Blue"), ("DDEEDB", "绿色", "Green"),
        ("F6EBCB", "黄色", "Yellow"), ("F4DDCB", "橙色", "Orange"),
        ("E8DDF5", "紫色", "Purple"), ("F3DCE5", "粉色", "Pink"),
        ("F2F2F2", "灰色", "Gray")]
    static func color(_ hex: String?) -> NSColor {
        guard let hex, let value = UInt32(hex, radix: 16) else { return NSColor(white: 0.95, alpha: 1) }
        return NSColor(srgbRed: Double((value >> 16) & 255)/255, green: Double((value >> 8) & 255)/255, blue: Double(value & 255)/255, alpha: 1)
    }
}

/// Discrete native menus keep the hour/minute separately selectable, including 24:00.
struct ScheduleTimePicker: View {
    @Binding var minute: Int
    let allowsEndOfDay: Bool
    let label: String
    var body: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(0...(allowsEndOfDay ? 24 : 23), id: \.self) { hour in
                    Button(String(format: "%02d", hour)) { minute = hour == 24 ? 1440 : hour * 60 + minute % 60 }
                }
            } label: { Text(String(format: "%02d", minute / 60)).frame(width: 28, height: 28) }
                .accessibilityLabel(label + " · " + "HH").accessibilityValue(String(minute / 60))
            Text(":")
            Menu {
                ForEach(0...(minute == 1440 ? 0 : 59), id: \.self) { value in
                    Button(String(format: "%02d", value)) { minute = minute / 60 * 60 + value }
                }
            } label: { Text(String(format: "%02d", minute % 60)).frame(width: 28, height: 28) }
                .accessibilityLabel(label + " · " + "mm").accessibilityValue(String(minute % 60))
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .font(.system(size: 13).monospacedDigit()).padding(.horizontal, 5)
            .background(Color.gray.opacity(0.08), in: Capsule()).transaction { $0.animation = nil }
    }
}

/// No animated system focus halo; focus feedback is an immediate static border.
struct ImmediateScheduleTitleField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var requestFocus = false
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator; field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13); field.isBordered = false; field.drawsBackground = false
        field.focusRingType = .none; field.isEditable = true; field.isSelectable = true
        field.maximumNumberOfLines = 1; field.setAccessibilityLabel(placeholder)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self; field.placeholderString = placeholder
        if field.stringValue != text { field.stringValue = text }
        if requestFocus && !context.coordinator.focused {
            DispatchQueue.main.async { field.window?.makeFirstResponder(field); field.selectText(nil) }
        }
        context.coordinator.focused = requestFocus
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ImmediateScheduleTitleField
        var focused = false
        init(_ parent: ImmediateScheduleTitleField) { self.parent = parent }
        func controlTextDidChange(_ note: Notification) { if let field = note.object as? NSTextField { parent.text = field.stringValue } }
    }
}
