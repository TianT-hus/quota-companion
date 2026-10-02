import SwiftUI
import AppKit

enum SettingsControlMetrics {
    static let labelWidth: CGFloat = 140
    static let columnSpacing: CGFloat = 10
    static let controlWidth: CGFloat = 236
    static let height: CGFloat = 28
}

struct SettingsControlRow<Content: View>: View {
    @Environment(\.settingsPickerWidth) private var controlWidth
    let title: String
    let content: Content
    var trailing: Bool
    var expanding: Bool
    init(title: String, trailing: Bool = false, expanding: Bool = false, @ViewBuilder content: () -> Content) { self.title = title; self.trailing = trailing; self.expanding = expanding; self.content = content() }
    var body: some View {
        HStack(alignment: .center, spacing: SettingsControlMetrics.columnSpacing) {
            if trailing {
                Text(title).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                content.fixedSize(horizontal: true, vertical: false)
            } else {
                Text(title).fixedSize(horizontal: false, vertical: true)
                    .frame(width: SettingsControlMetrics.labelWidth, alignment: .leading)
                if expanding { content.frame(maxWidth: .infinity, alignment: .leading) }
                else { content.frame(width: controlWidth, alignment: .leading); Spacer(minLength: 0) }
            }
        }.frame(minHeight: SettingsControlMetrics.height, alignment: .leading)
    }
}

struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool
    private var accessibility = CompanionAccessibility()
    init(_ title: String, isOn: Binding<Bool>) { self.title = title; _isOn = isOn }
    var body: some View {
        SettingsControlRow(title: title, trailing: true) {
            SettingsNativeSwitch(title: title, isOn: $isOn, highContrast: accessibility.contrast == .increased)
                .frame(width: 40, height: 24, alignment: .leading)
        }
    }
}

private struct SettingsPickerWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 180 }
extension EnvironmentValues {
    var settingsPickerWidth: CGFloat { get { self[SettingsPickerWidthKey.self] } set { self[SettingsPickerWidthKey.self] = newValue } }
}
struct SettingsChoice<Value: Hashable> {
    let value: Value
    let title: String
    var group: String?
    init(_ value: Value, _ title: String, group: String? = nil) { self.value = value; self.title = title; self.group = group }
}
struct SettingsPicker<Selection: Hashable>: View {
    let title: String
    @Binding var selection: Selection
    let options: [SettingsChoice<Selection>]
    @Environment(\.settingsPickerWidth) private var width
    init(_ title: String, selection: Binding<Selection>, options: [SettingsChoice<Selection>]) {
        self.title = title; _selection = selection; self.options = options
    }
    var body: some View {
        SettingsControlRow(title: title, trailing: true) {
            NativeSettingsPicker(title: title, selection: $selection, options: options)
                .frame(width: width, height: SettingsControlMetrics.height)
        }
    }
    static func measuredWidth(_ titles: [String]) -> CGFloat {
        min(350, max(100, ceil(titles.map { ($0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width }.max() ?? 0) + 52))
    }
}

struct NativeSettingsPicker<Value: Hashable>: NSViewRepresentable {
    let title: String
    @Binding var selection: Value
    let options: [SettingsChoice<Value>]
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> SettingsPopUpButton {
        let view = SettingsPopUpButton(frame: .zero, pullsDown: false)
        view.target = context.coordinator; view.action = #selector(Coordinator.changed(_:))
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateNSView(_ view: SettingsPopUpButton, context: Context) {
        context.coordinator.parent = self
        let signature = options.map { ($0.group ?? "") + "|" + $0.title }
        if view.optionSignature != signature {
            view.optionSignature = signature; view.removeAllItems(); view.autoenablesItems = false
            var previousGroup: String?
            for (index, option) in options.enumerated() {
                if let group = option.group, group != previousGroup {
                    if previousGroup != nil { view.menu?.addItem(.separator()) }
                    let heading = NSMenuItem(title: group, action: nil, keyEquivalent: ""); heading.isEnabled = false; heading.tag = -1
                    view.menu?.addItem(heading); previousGroup = group
                }
                let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: ""); item.tag = index
                view.menu?.addItem(item)
            }
        }
        if let index = options.firstIndex(where: { $0.value == selection }) { view.selectItem(withTag: index) }
        view.isEnabled = enabled; view.toolTip = view.title
        view.cell?.setAccessibilityLabel(title); view.needsDisplay = true
    }
    @MainActor final class Coordinator: NSObject {
        var parent: NativeSettingsPicker
        init(_ parent: NativeSettingsPicker) { self.parent = parent }
        @objc func changed(_ sender: NSPopUpButton) {
            guard let index = sender.selectedItem?.tag, parent.options.indices.contains(index) else { return }
            parent.selection = parent.options[index].value
        }
    }
}

final class SettingsPopUpButton: NSPopUpButton {
    var optionSignature: [String] = []
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 28) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(isEnabled ? 0.08 : 0.04).setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6); path.fill()
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast || (SettingsInputFocus.keyboard && window?.firstResponder === self) {
            NSColor.keyboardFocusIndicatorColor.setStroke(); path.lineWidth = 1; path.stroke()
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor, .paragraphStyle: paragraph]
        (title as NSString).draw(in: NSRect(x: 24, y: (bounds.height - 17) / 2, width: max(0, bounds.width - 48), height: 17), withAttributes: attrs)
        let arrow = NSBezierPath(); let x = bounds.maxX - 14, y = bounds.midY
        arrow.move(to: NSPoint(x: x-3,y:y-2)); arrow.line(to:NSPoint(x:x,y:y-5)); arrow.line(to:NSPoint(x:x+3,y:y-2))
        arrow.move(to: NSPoint(x:x-3,y:y+2)); arrow.line(to:NSPoint(x:x,y:y+5)); arrow.line(to:NSPoint(x:x+3,y:y+2))
        NSColor.secondaryLabelColor.setStroke(); arrow.lineWidth = 1.2; arrow.stroke()
    }
}


enum SettingsCardStyle {
    static let pageBackground = Color(hex: 0xFAFAFA)
    static let body = Font.system(size: 13, weight: .regular, design: .default)
    static let heading = Font.system(size: 14, weight: .medium, design: .default)
}

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    private var accessibility = CompanionAccessibility()

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(SettingsCardStyle.heading).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) { content }
                .font(SettingsCardStyle.body)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 10).fill(Color.white)
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
                        .shadow(color: .black.opacity(0.10), radius: 2, x: 0, y: 1)
                }
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(accessibility.contrast == .increased ? ManagementStyle.ink : .clear, lineWidth: 1))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Rectangle().fill(Color(hex: 0xF0F0F0)).frame(height: 1).accessibilityHidden(true)
    }
}
