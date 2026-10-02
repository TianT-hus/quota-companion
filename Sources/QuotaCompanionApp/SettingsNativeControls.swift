import AppKit
import SwiftUI

@MainActor func focusSettingsControl(named name: String, in window: NSWindow?) {
    func find(_ node: NSView) -> NSControl? {
        if let control = node as? NSControl, control.isEnabled,
           (control.identifier?.rawValue == name || control.cell?.accessibilityLabel() == name) { return control }
        return node.subviews.lazy.compactMap(find).first
    }
    // Accessibility actions can operate the settings window while it is not key.
    // Resolve the exact named target in this application's windows in that case.
    for candidate in window.map({ [$0] }) ?? NSApp.windows {
        if let root = candidate.contentView, let target = find(root) {
            candidate.makeFirstResponder(target); return
        }
    }
}

/// A native disclosure target can regain keyboard focus even when full keyboard access is off.
struct SettingsDisclosureButton: NSViewRepresentable {
    let title: String
    let identifier: String
    let expanded: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> SettingsDisclosureControl {
        let button = SettingsDisclosureControl()
        button.isBordered = false; button.imagePosition = .imageOnly
        button.target = context.coordinator; button.action = #selector(Coordinator.activate(_:))
        return button
    }
    func updateNSView(_ button: SettingsDisclosureControl, context: Context) {
        context.coordinator.parent = self
        button.isEnabled = enabled; button.identifier = .init(identifier)
        button.image = NSImage(systemSymbolName: expanded ? "chevron.up" : "chevron.down", accessibilityDescription: nil)
        button.cell?.setAccessibilityLabel(title); button.setAccessibilityIdentifier(identifier)
        button.setAccessibilityValue(expanded ? "expanded" : "collapsed")
    }
    @MainActor final class Coordinator: NSObject {
        var parent: SettingsDisclosureButton
        init(_ parent: SettingsDisclosureButton) { self.parent = parent }
        @objc func activate(_ button: NSButton) {
            guard button.isEnabled else { return }
            button.window?.makeFirstResponder(button); parent.action()
        }
    }
}
final class SettingsDisclosureControl: NSButton {
    override var acceptsFirstResponder: Bool { isEnabled }
    override func mouseDown(with event: NSEvent) {
        SettingsInputFocus.setKeyboard(false); super.mouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        SettingsInputFocus.setKeyboard(true)
        if event.keyCode == 48 { moveSettingsControlFocus(from: self, backwards: event.modifierFlags.contains(.shift)) }
        else { super.keyDown(with: event) }
    }
}

// A native checkbox supplies Space, Tab, enabled state and accessibility semantics;
// only its drawing is replaced. No invisible duplicate toggle or hit-test overlay.
@MainActor func moveSettingsControlFocus(from control: NSControl, backwards: Bool) {
    guard let window = control.window, let root = window.contentView else { return }
    func descendants(_ v: NSView) -> [NSControl] {
        guard !v.isHidden, v.alphaValue > 0 else { return [] }
        if let c = v as? NSControl, (c.isEnabled || c is SpeechStatusButton), !c.isHidden, c.acceptsFirstResponder { return [c] }
        return v.subviews.flatMap(descendants)
    }
    let controls = descendants(root).sorted {
        let a = $0.convert($0.bounds, to: nil), b = $1.convert($1.bounds, to: nil)
        return abs(a.midY-b.midY) > 3 ? a.midY > b.midY : a.minX < b.minX
    }
    guard let i = controls.firstIndex(where: { $0 === control }), controls.count > 1 else { return }
    let next = controls[(i + (backwards ? controls.count-1 : 1)) % controls.count]
    next.scrollToVisible(next.bounds); window.makeFirstResponder(next)
}
final class SettingsCapsuleSwitch: NSButton {
    static func interpolatedFraction(from start: CGFloat, to end: CGFloat, elapsed: TimeInterval) -> CGFloat {
        let t = min(1, max(0, elapsed / 0.16))
        return start + (end-start) * (t * t * (3 - 2*t))
    }
    private var motionTask: Task<Void, Never>?
    private var targetOn: Bool?
    private(set) var onFraction: CGFloat = 0
    func present(_ on: Bool, animated: Bool) {
        guard targetOn != on else { return }
        let wasInitialized = targetOn != nil
        targetOn = on; motionTask?.cancel(); motionTask = nil
        let end: CGFloat = on ? 1 : 0
        guard wasInitialized, animated, window != nil else { onFraction = end; needsDisplay = true; return }
        let start = onFraction, began = ProcessInfo.processInfo.systemUptime
        motionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard let self else { return }
                let t = min(1, (ProcessInfo.processInfo.systemUptime - began) / 0.16)
                self.onFraction = Self.interpolatedFraction(from: start, to: end, elapsed: ProcessInfo.processInfo.systemUptime - began); self.needsDisplay = true
                if t >= 1 { self.motionTask = nil; return }
            }
        }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { motionTask?.cancel(); motionTask = nil; onFraction = state == .on ? 1 : 0 }
        super.viewWillMove(toWindow: newWindow)
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        // NSButton's checkbox-shaped focus mask otherwise overlaps our capsule.
        // The single keyboard focus outline is painted below, not removed.
        focusRingType = .none
    }
    required init?(coder: NSCoder) { super.init(coder: coder); focusRingType = .none }
    var highContrast = false
    override var acceptsFirstResponder: Bool { isEnabled }
    override func mouseDown(with event: NSEvent) { guard isEnabled else { return }; window?.makeFirstResponder(self); super.mouseDown(with: event) }
    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        if event.keyCode == 48 { moveSettingsControlFocus(from: self, backwards: event.modifierFlags.contains(.shift)) }
        else if event.keyCode == 49 { performClick(nil) } else { super.keyDown(with: event) }
    }
    override var intrinsicContentSize: NSSize { NSSize(width: 40, height: 24) }
    override func draw(_ rect: NSRect) {
        let t = onFraction
        let blue = NSColor(srgbRed: 38/255, green: 110/255, blue: 212/255, alpha: 1)
        let gray = NSColor(srgbRed: 226/255, green: 229/255, blue: 227/255, alpha: 1)
        let color = gray.blended(withFraction: t, of: blue) ?? gray
        color.withAlphaComponent(isEnabled ? 1 : 0.4).setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12); path.fill()
        let contrast = highContrast || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        NSColor.gray.withAlphaComponent((contrast ? 1 : 1-t) * (isEnabled ? 1 : 0.4)).setStroke()
        path.lineWidth = contrast ? 2 : 1; path.stroke()
        let dot = NSColor(srgbRed: 119/255, green: 125/255, blue: 121/255, alpha: 1).blended(withFraction: t, of: .white) ?? .white
        dot.withAlphaComponent(isEnabled ? 1 : 0.5).setFill()
        let diameter = 12 + 6*t, center = 11 + 17*t
        NSBezierPath(ovalIn: NSRect(x: center-diameter/2, y: (24-diameter)/2, width: diameter, height: diameter)).fill()
        if isEnabled, SettingsInputFocus.keyboard, window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke(); path.lineWidth = 2; path.stroke()
        }
    }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return super.resignFirstResponder() }
}
final class SettingsPercentSlider: NSSlider {
    var integerSteps = true
    private(set) var mouseTracking = false
    override var acceptsFirstResponder: Bool { isEnabled }
    override func becomeFirstResponder() -> Bool {
        focusRingType = mouseTracking || !SettingsInputFocus.keyboard ? .none : .default
        needsDisplay = true
        return super.becomeFirstResponder()
    }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        SettingsInputFocus.setKeyboard(false)
        mouseTracking = true; focusRingType = .none
        defer { mouseTracking = false; focusRingType = .none; needsDisplay = true }
        window?.makeFirstResponder(self); super.mouseDown(with: event)
        if integerSteps { doubleValue = doubleValue.rounded() }
        if let action { sendAction(action, to: target) }
    }
    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        SettingsInputFocus.setKeyboard(true)
        focusRingType = .default; needsDisplay = true
        if event.keyCode == 48 { moveSettingsControlFocus(from: self, backwards: event.modifierFlags.contains(.shift)) }
        else if [123,124,125,126].contains(event.keyCode) {
            let step = integerSteps ? 1 : (maxValue-minValue)/100
            doubleValue = min(maxValue, max(minValue, (integerSteps ? doubleValue.rounded() : doubleValue) + ([123,125].contains(event.keyCode) ? -step : step)))
            if let action { sendAction(action, to: target) }
        } else { super.keyDown(with: event) }
    }
}
struct SettingsSizeSlider: NSViewRepresentable {
    @Binding var percent: Double
    let title: String
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> SettingsPercentSlider {
        let v = SettingsPercentSlider(); v.trackFillColor = NSColor(srgbRed: 38/255, green: 110/255, blue: 212/255, alpha: 1); v.minValue = 0; v.maxValue = 100; v.isContinuous = true
        v.target = context.coordinator; v.action = #selector(Coordinator.changed(_:)); return v
    }
    func updateNSView(_ v: SettingsPercentSlider, context: Context) {
        context.coordinator.parent = self; if !v.mouseTracking { v.doubleValue = percent }; v.isEnabled = enabled; v.cell?.setAccessibilityLabel(title)
        v.setAccessibilityValueDescription("\(Int(percent.rounded()))%")
    }
    @MainActor class Coordinator: NSObject {
        var parent: SettingsSizeSlider
        init(_ parent: SettingsSizeSlider) { self.parent = parent }
        @objc func changed(_ v: NSSlider) { v.doubleValue = v.doubleValue.rounded(); parent.percent = v.doubleValue }
    }
}
struct SettingsAdjustmentSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let title: String
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> SettingsPercentSlider {
        let view = SettingsPercentSlider(); view.trackFillColor = NSColor(srgbRed: 38/255, green: 110/255, blue: 212/255, alpha: 1); view.integerSteps = false
        view.isContinuous = true; view.target = context.coordinator; view.action = #selector(Coordinator.changed(_:))
        return view
    }
    func updateNSView(_ view: SettingsPercentSlider, context: Context) {
        context.coordinator.parent = self; view.minValue = range.lowerBound; view.maxValue = range.upperBound
        if !view.mouseTracking { view.doubleValue = value }; view.isEnabled = enabled; view.cell?.setAccessibilityLabel(title)
    }
    @MainActor final class Coordinator: NSObject {
        var parent: SettingsAdjustmentSlider
        init(_ parent: SettingsAdjustmentSlider) { self.parent = parent }
        @objc func changed(_ view: NSSlider) { parent.value = view.doubleValue }
    }
}
struct SettingsNativeSwitch: NSViewRepresentable {
    let title: String
    @Binding var isOn: Bool
    var highContrast: Bool
    @Environment(\.isEnabled) var enabled
    var accessibility = CompanionAccessibility()
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> SettingsCapsuleSwitch {
        let v = SettingsCapsuleSwitch(); v.setButtonType(.switch); v.title = ""; v.isBordered = false
        v.target = context.coordinator; v.action = #selector(Coordinator.change(_:)); return v
    }
    func updateNSView(_ v: SettingsCapsuleSwitch, context: Context) {
        context.coordinator.parent = self; v.state = isOn ? .on : .off; v.isEnabled = enabled
        v.present(isOn, animated: !accessibility.reduceMotion)
        v.highContrast = highContrast; v.cell?.setAccessibilityLabel(title); v.toolTip = title; v.needsDisplay = true
    }
    @MainActor class Coordinator: NSObject {
        var parent: SettingsNativeSwitch
        init(_ parent: SettingsNativeSwitch) { self.parent = parent }
        @objc func change(_ sender: NSButton) {
            parent.isOn = sender.state == .on
            // A confirmation or failed write may reject the proposed state.
            sender.state = parent.isOn ? .on : .off
            (sender as? SettingsCapsuleSwitch)?.present(parent.isOn, animated: !parent.accessibility.reduceMotion)
        }
    }
}
