import AppKit

/// Only button/slider focus decoration follows input modality; editing focus and
/// first responders are preserved. The next keyboard navigation restores rings.
@MainActor enum SettingsInputFocus {
    private(set) static var keyboard = true
    private static var monitor: Any?
    static func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { event in
            MainActor.assumeIsolated {
                if event.type == .leftMouseDown { setKeyboard(false) }
                else if [48, 49, 123, 124, 125, 126].contains(event.keyCode) { setKeyboard(true) }
            }
            return event
        }
    }
    static func setKeyboard(_ value: Bool) {
        keyboard = value
        func refresh(_ view: NSView) {
            if view is NSButton || view is NSSlider {
                view.focusRingType = view is SettingsCapsuleSwitch || view is SpeechStatusButton ? .none : (value ? .default : .none)
                view.needsDisplay = true
            }
            for child in view.subviews { refresh(child) }
        }
        for window in NSApp.windows { if let root = window.contentView { refresh(root) } }
    }
}
