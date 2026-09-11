import AppKit
import Combine
import OSLog
import QuotaCore
import SwiftUI

private final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    var pointerChanged: (() -> Void)?
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { pointerChanged?() }
    override func mouseExited(with event: NSEvent) { pointerChanged?() }
}

@MainActor
final class PanelController: NSObject {
    private static let logger = Logger(subsystem: "dev.quota-companion.mac", category: "Panel")
    private let model: CompanionModel
    private let pet: NSPanel
    private let detail: NSPanel
    private let petView: FirstMouseHostingView<PetRootView>
    private let detailView: FirstMouseHostingView<CompanionRootView>
    private let positionDefaults: UserDefaults
    private var subscriptions = Set<AnyCancellable>()
    private var mouseMonitor: Any?
    private var visibilityTimer: Timer?
    private var hoverTimer: Timer?
    private var requestedVisible = false
    private var placed = false
    private var downPoint: CGPoint?
    private var downOrigin: CGPoint = .zero
    private var generation = 0
    private(set) var layoutMilliseconds = 0.0
    private(set) var layout: PetPanelLayout?
    var nativeWindow: NSWindow { pet }
    var detailWindow: NSWindow { detail }
    private var petSize: CGSize { model.companionSize.petSize }

    init(model: CompanionModel, positionDefaults: UserDefaults = .standard, monitorsSystem: Bool = true) {
        self.model = model; self.positionDefaults = positionDefaults
        pet = CompanionPanel(contentRect: CGRect(origin: .zero, size: PetPanelLayout.petSize),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        detail = CompanionPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 80),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        petView = FirstMouseHostingView(rootView: PetRootView(model: model))
        detailView = FirstMouseHostingView(rootView: CompanionRootView(model: model))
        super.init()
        configure(pet, view: petView, radius: 0)
        configure(detail, view: detailView, radius: 0)
        pet.title = "Quota Pixel Cat"; detail.title = "Quota Details"
        petView.pointerChanged = { [weak self] in self?.samplePointer() }
        detailView.pointerChanged = { [weak self] in self?.samplePointer() }
        model.setPresentationHandler { [weak self] _ in self?.present() }
        model.$companionSize.removeDuplicates().dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let screen = self.screenForPet() else { return }
                self.setFrame(PanelGeometry.resizedFrame(from: self.pet.frame, to: self.petSize, in: screen.visibleFrame), panel: self.pet)
                self.positionDefaults.set(NSStringFromPoint(self.pet.frame.origin), forKey: self.positionKey(screen))
                self.present()
            }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: detail).sink { [weak self] _ in
            DispatchQueue.main.async { self?.model.updateInteraction { $0.releaseKeyboard(now: ProcessInfo.processInfo.systemUptime) } }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification, object: detail).sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pet.order(.above, relativeTo: self.detail.windowNumber)
            }
        }.store(in: &subscriptions)
        model.$snapshot.map { $0.windows.count }.removeDuplicates().dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.positionDetails() }
        }.store(in: &subscriptions)
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.model.holdInteraction(name == NSMenu.didBeginTrackingNotification)
                    self?.samplePointer()
                }
            }.store(in: &subscriptions)
        }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.restorePosition(); self.positionDetails()
            }
        }.store(in: &subscriptions)
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.pointerEvent(event)
        }
        if monitorsSystem {
            visibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshVisibility() }
            }
        }
    }

    private func configure(_ panel: NSPanel, view: NSView, radius: CGFloat) {
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenNone]
        panel.isMovableByWindowBackground = false; panel.acceptsMouseMovedEvents = true
        panel.minSize = CGSize(width: 1, height: 1); panel.maxSize = CGSize(width: 10000, height: 10000)
        if let hosting = view as? FirstMouseHostingView<PetRootView> { hosting.sizingOptions = [] }
        if let hosting = view as? FirstMouseHostingView<CompanionRootView> { hosting.sizingOptions = [] }
        view.frame = CGRect(origin: .zero, size: panel.frame.size)
        view.autoresizingMask = [.width, .height]; view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor; view.layer?.isOpaque = false
        view.layer?.cornerRadius = radius; view.layer?.cornerCurve = .continuous; view.layer?.masksToBounds = true
        panel.contentView = view
    }

    func show() {
        requestedVisible = true
        if !placed { restorePosition(); placed = true }
        refreshVisibility(); present()
    }
    func hide() {
        requestedVisible = false; model.setCompanionVisible(false)
        hoverTimer?.invalidate(); hoverTimer = nil
        pet.orderOut(nil); detail.orderOut(nil)
    }
    func close() {
        hide(); visibilityTimer?.invalidate()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil; subscriptions.removeAll()
    }

    private func present() {
        generation += 1
        let token = generation
        positionDetails()
        guard requestedVisible && model.isCompanionVisible else { detail.orderOut(nil); return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        detailView.layer?.removeAllAnimations()
        if model.isExpanded {
            let alreadyVisible = detail.isVisible
            detail.alphaValue = alreadyVisible || reduce ? 1 : 0
            detail.orderFrontRegardless()
            if model.isPinned { detail.makeKey(); detail.makeFirstResponder(detailView) }
            pet.order(.above, relativeTo: detail.windowNumber)
            if !reduce {
                NSAnimationContext.runAnimationGroup { context in context.duration = 0.16; detail.animator().alphaValue = 1 }
            }
        } else if detail.isVisible && !reduce {
            NSAnimationContext.runAnimationGroup { context in context.duration = 0.16; detail.animator().alphaValue = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                guard let self, token == self.generation, !self.model.isExpanded else { return }
                self.detail.orderOut(nil)
                self.recordDiagnostics()
            }
        } else { detail.orderOut(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, token == self.generation, let layout = self.layout else { return }
            if self.pet.frame.size != self.petSize || self.petView.bounds.size != self.petSize ||
                self.detail.frame != layout.detail || self.detailView.bounds.size != layout.detail.size {
                self.setFrame(CGRect(origin: self.pet.frame.origin, size: self.petSize), panel: self.pet)
                self.positionDetails()
                Self.logger.error("Corrected dual-panel geometry")
            }
        }
        ensureHoverTimer()
        recordDiagnostics()
    }

    private func setFrame(_ frame: CGRect, panel: NSPanel) {
        panel.setFrame(frame, display: false, animate: false)
        panel.contentView?.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView?.needsLayout = true; panel.contentView?.layoutSubtreeIfNeeded()
        panel.contentView?.needsDisplay = true; panel.displayIfNeeded()
    }
    private func positionDetails() {
        let started = ProcessInfo.processInfo.systemUptime
        guard let screen = screenForPet() else { return }
        let next = PetPanelLayout(pet: pet.frame, windowCount: model.snapshot.windows.count, screen: screen.visibleFrame, scale: model.companionSize.scale)
        detailView.layer?.cornerRadius = 0
        layout = next
        if model.detailDirection != next.direction { model.detailDirection = next.direction }
        if detail.frame != next.detail || detailView.bounds.size != next.detail.size { setFrame(next.detail, panel: detail) }
        layoutMilliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1000
        recordDiagnostics()
    }

    private func recordDiagnostics() {
        func frame(_ r: CGRect) -> [String: Double] { ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height] }
        let fields: [String: Any] = ["mode": model.interaction.mode.rawValue, "sequence": generation,
            "pet": frame(pet.frame), "detail": frame(detail.frame), "detailVisible": detail.isVisible,
            "layoutMilliseconds": layoutMilliseconds, "hoverDelayMilliseconds": 150]
        if let data = try? JSONSerialization.data(withJSONObject: fields) { model.recordPresentation(data) }
    }

    private func samplePointer() {
        guard requestedVisible && model.isCompanionVisible else { return }
        let point = NSEvent.mouseLocation
        let onPet = pet.frame.contains(point)
        let inRegion = onPet || (model.isExpanded && (layout?.contains(point) ?? false))
        let now = ProcessInfo.processInfo.systemUptime
        model.updateInteraction { state in state.pointer(pet: onPet, region: inRegion, now: now); state.tick(now: now) }
        ensureHoverTimer()
    }
    private func ensureHoverTimer() {
        let state = model.interaction
        let needed = requestedVisible && model.isCompanionVisible && !state.dragging &&
            (state.openAt != nil || state.closeAt != nil || state.mode == .hoverDetails)
        if !needed { hoverTimer?.invalidate(); hoverTimer = nil; return }
        guard hoverTimer == nil else { return }
        // Runs only during hover interaction. Collapsed idle has no sampling timer.
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.samplePointer() }
        }
    }

    private func pointerEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown, event.windowNumber == pet.windowNumber || event.windowNumber == detail.windowNumber {
            if event.keyCode == 53 { model.collapse(); return nil }
            if event.keyCode == 36 || event.keyCode == 49, event.windowNumber == pet.windowNumber { model.showKeyboardDetails(); return nil }
        }
        guard event.windowNumber == pet.windowNumber else { return event }
        switch event.type {
        case .leftMouseDown:
            downPoint = NSEvent.mouseLocation; downOrigin = pet.frame.origin
            return nil
        case .leftMouseDragged:
            guard let start = downPoint else { return event }
            let point = NSEvent.mouseLocation
            let delta = CGSize(width: point.x - start.x, height: point.y - start.y)
            if !model.interaction.dragging && PointerIntent.classify(delta: delta) == .drag { model.updateInteraction { $0.beginDrag() }; ensureHoverTimer() }
            if model.interaction.dragging {
                pet.setFrameOrigin(CGPoint(x: downOrigin.x + delta.width, y: downOrigin.y + delta.height)); positionDetails()
            }
            return nil
        case .leftMouseUp:
            guard downPoint != nil else { return event }
            downPoint = nil
            if model.interaction.dragging {
                if let screen = screenForPet() {
                    setFrame(PanelGeometry.snappedFrame(pet.frame, in: screen.visibleFrame), panel: pet)
                    positionDefaults.set(NSStringFromPoint(pet.frame.origin), forKey: positionKey(screen))
                }
                positionDetails(); model.updateInteraction { $0.endDrag() }
            } else { model.toggleExpanded() }
            return nil
        default: return event
        }
    }

    private func screenForPet() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(CGPoint(x: pet.frame.midX, y: pet.frame.midY)) } ?? NSScreen.main
    }
    private func positionKey(_ screen: NSScreen, legacy: Bool = false) -> String {
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return "\(legacy ? "panelOrigin" : "pixelPetOrigin").\(id?.uint32Value ?? 0)"
    }
    private func restorePosition() {
        guard let screen = screenForPet() ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let target: CGRect
        if let saved = positionDefaults.string(forKey: positionKey(screen)) {
            target = CGRect(origin: NSPointFromString(saved), size: petSize)
        } else if let old = positionDefaults.string(forKey: positionKey(screen, legacy: true)) {
            target = PanelGeometry.resizedFrame(from: CGRect(origin: NSPointFromString(old), size: CGSize(width: 56, height: 56)), to: petSize, in: visible)
        } else {
            target = CGRect(x: visible.maxX - petSize.width - 24, y: visible.minY + 24, width: petSize.width, height: petSize.height)
        }
        let safe = target.origin.x.isFinite && target.origin.y.isFinite ? target : CGRect(origin: visible.origin, size: petSize)
        setFrame(PanelGeometry.constrained(safe, to: visible), panel: pet)
        positionDefaults.set(NSStringFromPoint(pet.frame.origin), forKey: positionKey(screen))
    }

    private func refreshVisibility() {
        let sharingIDs: Set<String> = ["com.apple.ScreenSharing", "com.apple.screensharing.agent", "com.apple.RemoteDesktop.agent"]
        let sharing = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier.map(sharingIDs.contains) ?? false }
        let visible = requestedVisible && !sharing
        if !visible {
            model.setCompanionVisible(false); pet.orderOut(nil); detail.orderOut(nil)
            hoverTimer?.invalidate(); hoverTimer = nil
        } else if !pet.isVisible {
            model.setCompanionVisible(true); pet.orderFrontRegardless(); present()
        } else {
            model.setCompanionVisible(pet.isOnActiveSpace)
        }
    }
}
