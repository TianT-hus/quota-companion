import AppKit
import SwiftUI

/// Event names only: never log user text, endpoints, or credentials.
@MainActor enum OwnedDialogTrace {
    static private(set) var events: [String] = []
    static func record(_ event: String) {
        let line = "\(ProcessInfo.processInfo.systemUptime) \(event)"
        events.append(line); if events.count > 200 { events.removeFirst() }
        if ProcessInfo.processInfo.environment["QUOTA_DIALOG_TRACE"] == "1" { print(line) }
        if Bundle.main.object(forInfoDictionaryKey: "QuotaSecretaryPreview") as? Bool == true {
            let url = URL.temporaryDirectory.appendingPathComponent((Bundle.main.bundleIdentifier ?? "quota-qa") + "-dialogs.log")
            try? events.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

final class OwnedDialogPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func close() {
        if NSApp.modalWindow === self { NSApp.stopModal() }
        super.close()
    }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { OwnedDialogTrace.record("dialog.mouseDown key=\(isKeyWindow)") }
        super.sendEvent(event)
    }
}

/// Only windows explicitly owned by this app participate; system permission windows never do.
@MainActor final class OwnedDialogs {
    static let shared = OwnedDialogs()
    static let changed = Notification.Name("OwnedDialogs.changed")
    weak var managementWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var owners: [ObjectIdentifier: (child: NSWindow, parent: NSWindow, focus: NSResponder?)] = [:]
    private var positioning = false
    private var pendingModalStops: [NSWindow] = []
    func stopModal(for window: NSWindow) {
        guard NSApp.modalWindow === window else {
            if !pendingModalStops.contains(where: { $0 === window }) { pendingModalStops.append(window) }
            return
        }
        NSApp.stopModal()
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
    }
    func modalDidExit(_ window: NSWindow) {
        pendingModalStops.removeAll { $0 === window }
        // Discard can close the editor from inside its confirmation's action.
        // Its outer modal loop must be stopped after the inner loop unwinds.
        if let top = NSApp.modalWindow, pendingModalStops.contains(where: { $0 === top }) {
            pendingModalStops.removeAll { $0 === top }
            stopModal(for: top)
        }
    }
    func start() {
        guard observers.isEmpty else { return }
        SettingsInputFocus.start()
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reposition() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.release(window) }
        })
    }
    static func frame(size: NSSize, parent: NSRect, screen: NSRect) -> NSRect {
        var rect = NSRect(x: parent.midX-size.width/2, y: parent.midY-size.height/2, width: size.width, height: size.height)
        rect.origin.x = max(screen.minX, min(rect.minX, screen.maxX-size.width))
        rect.origin.y = max(screen.minY, min(rect.minY, screen.maxY-size.height))
        return rect
    }
    func hasChild(_ parent: NSWindow?) -> Bool { owners.values.contains { $0.parent === parent && $0.child.isVisible } }
    func track(_ child: NSWindow, parent: NSWindow?) {
        start()
        guard let parent, parent !== child else { return }
        if owners[ObjectIdentifier(child)] == nil {
            owners[ObjectIdentifier(child)] = (child, parent, parent.firstResponder)
            parent.addChildWindow(child, ordered: .above)
        }
        position(child, parent: parent)
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
    func release(_ window: NSWindow) {
        if let owned = owners.removeValue(forKey: ObjectIdentifier(window)) {
            owned.parent.removeChildWindow(window)
            if owned.parent.isVisible {
                owned.parent.makeKey()
                if let focus = owned.focus { owned.parent.makeFirstResponder(focus) }
            }
        }
        for owned in Array(owners.values) where owned.parent === window { owned.child.close(); release(owned.child) }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
    func reposition() {
        guard !positioning else { return }
        for owned in Array(owners.values) { position(owned.child, parent: owned.parent) }
    }
    private func position(_ child: NSWindow, parent: NSWindow) {
        guard !positioning, let screen = parent.screen ?? NSScreen.main else { return }
        positioning = true; defer { positioning = false }
        let parentRect = parent.contentView.map { parent.convertToScreen($0.convert($0.bounds, to: nil)) } ?? parent.frame
        let rect = Self.frame(size: child.frame.size, parent: parentRect, screen: screen.visibleFrame)
        if child.frame.origin != rect.origin { child.setFrameOrigin(rect.origin) }
    }
}

@MainActor final class DialogOwner: ObservableObject {
    weak var window: NSWindow?
}
struct DialogOwnerReader: NSViewRepresentable {
    let owner: DialogOwner
    func makeNSView(context: Context) -> OwnerAnchor { let v = OwnerAnchor(); v.owner = owner; return v }
    func updateNSView(_ view: OwnerAnchor, context: Context) { view.owner = owner; owner.window = view.window }
}
final class OwnerAnchor: NSView {
    weak var owner: DialogOwner?
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); owner?.window = window }
}
private struct OwnedDismissKey: EnvironmentKey { static let defaultValue: @MainActor () -> Void = {} }
private struct OwnedContentSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
extension EnvironmentValues {
    var ownedDismiss: @MainActor () -> Void { get { self[OwnedDismissKey.self] } set { self[OwnedDismissKey.self] = newValue } }
}

/// The anchor belongs to the initiating view, so nested presentations automatically acquire
/// the current editor, not a transient desktop-pet/key window.
private struct OwnedPresentation<Presented: View>: NSViewRepresentable {
    let presented: Bool
    let content: () -> Presented
    let dismiss: @MainActor () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ anchor: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.revision += 1
        let revision = coordinator.revision
        if !presented { coordinator.close(); return }
        let root = AnyView(content().environment(\.ownedDismiss, {
            // End the modal session in the button's event, not in a later SwiftUI
            // transaction. This also prevents an invisible modal from eating clicks.
            coordinator.close(); dismiss()
        }).environment(\.colorScheme, .light).font(.system(size: 13)).tint(ManagementStyle.selectionBorder))
        DispatchQueue.main.async { [weak anchor, weak coordinator] in
            guard let anchor, let parent = anchor.window, let coordinator, coordinator.revision == revision else { return }
            coordinator.present(root, parent: parent)
        }
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.close() }
    @MainActor final class Coordinator {
        var revision = 0
        var panel: NSPanel?
        private var host: NSHostingController<AnyView>?
        private var runningModal = false
        private var closing = false
        func present(_ root: AnyView, parent: NSWindow) {
            // Measure SwiftUI's ideal content outside AppKit's constraint-update cycle.
            // preferredContentSize tracking can recursively invalidate constraints when
            // an editor includes GeometryReader / animated preview content.
            let measured = AnyView(root.fixedSize().background(GeometryReader { proxy in
                Color.clear.preference(key: OwnedContentSizeKey.self, value: proxy.size)
            }).onPreferenceChange(OwnedContentSizeKey.self) { [weak self] size in
                DispatchQueue.main.async { self?.resize(to: size) }
            })
            if let host { host.rootView = measured; return }
            let panel = OwnedDialogPanel(contentRect: .init(x:0,y:0,width:420,height:240), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
            panel.isMovable = false; panel.worksWhenModal = true
            panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = false
            let host = NSHostingController(rootView: measured)
            host.sizingOptions = []
            self.panel = panel; self.host = host; panel.contentViewController = host
            resize(to: host.sizeThatFits(in: CGSize(width: 420, height: 240)))
            OwnedDialogs.shared.track(panel, parent: parent)
            panel.makeKeyAndOrderFront(nil)
            OwnedDialogTrace.record("dialog.open key=\(panel.isKeyWindow)")
            OwnedDialogs.shared.reposition()
            // A Swift Testing renderer has no application event loop. Geometry remains
            // testable there; modal event delivery is verified in the running candidate.
            guard NSApp.isRunning else { return }
            // Do not nest runModal inside a main-queue dispatch block: that would hold
            // the queue and delay SwiftUI updates/dismissal until another event arrives.
            RunLoop.main.perform(inModes: [.common]) { [weak self, weak panel] in
                MainActor.assumeIsolated {
                guard let self, let panel, self.panel === panel else { return }
                self.runningModal = true
                OwnedDialogTrace.record("dialog.modal.enter")
                NSApp.runModal(for: panel)
                OwnedDialogTrace.record("dialog.modal.exit")
                OwnedDialogs.shared.modalDidExit(panel)
                self.runningModal = false
                self.close()
                }
            }
        }
        func resize(to size: CGSize) {
            guard let panel else { return }
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
            let current = panel.contentView?.bounds.size ?? .zero
            if abs(size.width-current.width) > 0.5 || abs(size.height-current.height) > 0.5 { panel.setContentSize(size) }
            OwnedDialogs.shared.reposition()
        }
        func close() {
            guard !closing, let panel else { return }
            closing = true
            OwnedDialogTrace.record("dialog.close.request running=\(runningModal) top=\(NSApp.modalWindow === panel)")
            if runningModal { OwnedDialogs.shared.stopModal(for: panel) }
            OwnedDialogTrace.record("dialog.close")
            OwnedDialogs.shared.release(panel); panel.orderOut(nil); panel.close()
            self.panel = nil; host = nil; closing = false
        }
    }
}

private struct OwnedAlertButtonStyle: PrimitiveButtonStyle {
    @Environment(\.ownedDismiss) private var dismiss
    @Environment(\.isEnabled) private var enabled
    @FocusState private var focused: Bool
    func makeBody(configuration: Configuration) -> some View {
        let activate = {
            guard enabled else { return }
            OwnedDialogTrace.record("dialog.confirm.action")
            dismiss()
            configuration.trigger()
        }
        // A primitive style must drive the original action, not create another
        // Button inside it. Nested button semantics lose AXPress in modal panels.
        configuration.label.frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(Color.primary.opacity(enabled ? 0.07 : 0.03), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused && SettingsInputFocus.keyboard ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(Rectangle()).onTapGesture(perform: activate)
            .focusable(enabled).focused($focused).focusEffectDisabled()
            .onKeyPress(.return) { activate(); return .handled }
            .onKeyPress(.space) { activate(); return .handled }
            .onKeyPress(.escape) { guard configuration.role == .cancel else { return .ignored }; activate(); return .handled }
            .accessibilityAddTraits(.isButton).accessibilityAction(.default, activate)
    }
}
extension View {
    func ownedSheet<C: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> C) -> some View {
        background(OwnedPresentation(presented: isPresented.wrappedValue, content: content, dismiss: { isPresented.wrappedValue = false }))
            .onChange(of: isPresented.wrappedValue) { before, after in if before && !after { onDismiss?() } }
    }
    func ownedSheet<Item: Identifiable, C: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> C) -> some View {
        ownedSheet(isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }), onDismiss: onDismiss) {
            if let value = item.wrappedValue { content(value) }
        }
    }
    func ownedAlert<A: View, M: View>(_ title: String, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> A, @ViewBuilder message: @escaping () -> M) -> some View {
        ownedSheet(isPresented: isPresented) {
            VStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width:64,height:64)
                Text(title).font(.system(size:15,weight:.semibold)).multilineTextAlignment(.center)
                message().font(.system(size:13)).fixedSize(horizontal:false,vertical:true)
                VStack(spacing: 8) { actions() }.buttonStyle(OwnedAlertButtonStyle())
            }.padding(24).frame(width: 380).fixedSize(horizontal:false,vertical:true)
        }
    }
    func ownedAlert<A: View>(_ title: String, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> A) -> some View {
        ownedAlert(title, isPresented: isPresented, actions: actions) { EmptyView() }
    }
}

@MainActor private final class AlertResponseTarget: NSObject {
    @objc func choose(_ sender: NSButton) { NSApp.stopModal(withCode: .init(rawValue: sender.tag)) }
}
extension NSAlert {
    @MainActor func runOwnedModal(parent: NSWindow? = nil) -> NSApplication.ModalResponse {
        // The explicit registered management window is a fallback for legacy model entrypoints,
        // never the unrelated NSApp.keyWindow.
        guard let owner = parent ?? OwnedDialogs.shared.managementWindow else { return .abort }
        layout()
        let target = AlertResponseTarget()
        for (index, button) in buttons.enumerated() {
            button.target = target; button.action = #selector(AlertResponseTarget.choose(_:))
            button.tag = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + index
        }
        OwnedDialogs.shared.track(window, parent: owner)
        window.makeKeyAndOrderFront(nil); OwnedDialogs.shared.reposition()
        defer { window.orderOut(nil); OwnedDialogs.shared.release(window) }
        return withExtendedLifetime(target) { NSApp.runModal(for: window) }
    }
}
extension NSSavePanel {
    @MainActor func beginOwned(parent: NSWindow? = nil, _ completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard let owner = parent ?? OwnedDialogs.shared.managementWindow else { completion(.cancel); return }
        OwnedDialogs.shared.track(self, parent: owner)
        begin { response in
            OwnedDialogs.shared.release(self)
            completion(response)
        }
        DispatchQueue.main.async { OwnedDialogs.shared.reposition() }
    }
    @MainActor func runOwnedModal(parent: NSWindow? = nil) -> NSApplication.ModalResponse {
        guard let owner = parent ?? OwnedDialogs.shared.managementWindow else { return .cancel }
        OwnedDialogs.shared.track(self, parent: owner)
        DispatchQueue.main.async { OwnedDialogs.shared.reposition() }
        defer { OwnedDialogs.shared.release(self) }
        return runModal()
    }
}
