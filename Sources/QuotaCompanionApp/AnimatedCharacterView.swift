import AppKit
import QuartzCore
import SwiftUI
import QuotaCore

struct AnimatedCharacterView: NSViewRepresentable {
    let character: ImportedCharacter
    let tint: QuotaCore.RGBColor
    let remaining: Double?
    let pixelScale: Double
    var frequency: AnimationFrequency = .natural
    var customInterval: Double = 30
    let eligible: Bool
    var motions: [ImportedCharacter]? = nil
    func makeNSView(context: Context) -> CharacterAnimationCanvas { CharacterAnimationCanvas(frame: .zero) }
    func updateNSView(_ view: CharacterAnimationCanvas, context: Context) {
        view.configure(character: character, tint: tint, remaining: remaining, pixelScale: pixelScale, eligible: eligible, frequency: frequency, motions: motions, customInterval: customInterval)
    }
    static func dismantleNSView(_ view: CharacterAnimationCanvas, coordinator: ()) { view.stop() }
}

/// A single boundary timer starts/stops a 3-second discrete CA contents animation.
/// Quota updates only move the clipping plane; they never restart the action.
@MainActor final class CharacterAnimationCanvas: NSView {
    override var isFlipped: Bool { true }
    let baseLayer = CALayer(), fillLayer = CALayer(), detailLayer = CALayer()
    let fillClip = CALayer(), maskLayer = CALayer()
    private var timer: Timer?
    private var requested = false, sessionAvailable = true, displayAwake = true, computerAwake = true
    private var frequency: AnimationFrequency = .natural
    private var customInterval: Double = 30
    private func delay(afterAction: Bool) -> Double {
        frequency == .custom ? customInterval : frequency.delay(afterAction: afterAction, naturalDelay: Double.random(in: 25...40))
    }
    private var policy = CharacterDancePlayback()
    private var textures: [ImportedCharacter.Textures] = []
    private var keys: [NSNumber] = []
    private var textureKey = ""
    private var motionPool: [ImportedCharacter] = []
    private var motionTint = QuotaCore.RGBColor(hex: 0x72D5E8)
    private var motionScale: Double = 1
    private(set) var activeMotionID: String?
    private var animationStart: CFTimeInterval?
    private var fillTop = 40.0, fillBottom = 79.0, percent = 0.0
    private(set) var characterID = ""
    var isPlaying: Bool { animationStart != nil }
    var scheduledDeadline: TimeInterval? { policy.nextDeadline }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        layer?.addSublayer(baseLayer); layer?.addSublayer(fillClip); layer?.addSublayer(detailLayer)
        fillClip.masksToBounds = true; fillClip.addSublayer(fillLayer); fillLayer.mask = maskLayer
        for item in [baseLayer, fillLayer, detailLayer, maskLayer] {
            item.contentsGravity = .resize; item.magnificationFilter = .nearest; item.minificationFilter = .linear
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self, selector: #selector(lifecycle(_:)), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(windowChanged(_:)), name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        workspace.addObserver(self, selector: #selector(accessibilityChanged(_:)), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    deinit {
        // dismantleNSView / detaching the window cancels the timer on MainActor.
        // Its weak callback cannot retain this view if teardown happens first.
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateEligibility(reset: true) }
    @objc private func windowChanged(_ note: Notification) {
        guard let changed = note.object as? NSWindow, changed === window else { return }
        updateEligibility(reset: false)
    }
    @objc private func accessibilityChanged(_ note: Notification) { updateEligibility(reset: true) }
    @objc private func lifecycle(_ note: Notification) {
        switch note.name {
        case NSWorkspace.willSleepNotification: computerAwake = false
        case NSWorkspace.didWakeNotification: computerAwake = true
        case NSWorkspace.sessionDidResignActiveNotification: sessionAvailable = false
        case NSWorkspace.sessionDidBecomeActiveNotification: sessionAvailable = true
        case NSWorkspace.screensDidSleepNotification: displayAwake = false
        case NSWorkspace.screensDidWakeNotification: displayAwake = true
        default: break
        }
        updateEligibility(reset: true)
    }
    func configure(character: ImportedCharacter, tint: QuotaCore.RGBColor, remaining: Double?, pixelScale: Double, eligible: Bool, frequency: AnimationFrequency = .natural, motions: [ImportedCharacter]? = nil, customInterval: Double = 30) {
        let pool = (motions ?? (character.manifest.animation == nil ? [] : [character])).filter { $0.animationFrames.count == 8 }
        let changed = characterID != character.id || pool.map(\.id) != motionPool.map(\.id)
        let frequencyChanged = self.frequency != frequency || self.customInterval != customInterval
        self.customInterval = customInterval.isFinite ? min(3600, max(1, customInterval)) : 30
        self.frequency = frequency
        if changed { stop(); activeMotionID = nil; characterID = character.id }
        motionPool = pool
        requested = eligible && !pool.isEmpty
        fillTop = Double(character.manifest.fillTop); fillBottom = Double(character.manifest.fillBottom)
        percent = remaining.flatMap { $0.isFinite ? min(100, max(0, $0)) : nil } ?? 0
        let scale = pixelScale.isFinite ? min(4, max(1, pixelScale)) : 1
        motionTint = tint; motionScale = scale
        let key = "\(character.id)/\(tint.hexString)/\(Int((72*scale).rounded()))x\(Int((80*scale).rounded()))"
        if key != textureKey {
            textureKey = key
            let initial = pool.first
            textures = initial?.animationFrames.map { $0.textures(tint, pixelScale: scale) } ?? []
            keys = initial?.manifest.animation?.keyTimes.map(NSNumber.init(value:)) ?? []
            let rest = character.textures(tint, pixelScale: scale)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            baseLayer.contents = rest.base; fillLayer.contents = rest.fill
            maskLayer.contents = rest.mask; detailLayer.contents = rest.details
            CATransaction.commit()
            if let start = animationStart { animate(since: start) }
        }
        needsLayout = true; layoutSubtreeIfNeeded()
        updateEligibility(reset: changed || frequencyChanged)
    }
    private var eligible: Bool {
        requested && sessionAvailable && displayAwake && computerAwake && window?.isVisible == true &&
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !motionPool.isEmpty
    }
    private func updateEligibility(reset: Bool) {
        let now = CACurrentMediaTime(), delay = delay(afterAction: false)
        if reset { policy.resume(eligible: eligible, now: now, delay: delay) }
        else { policy.setEligible(eligible, now: now, delay: delay) }
        if frequency == .continuous && eligible { policy.tick(now: now, nextDelay: 0) }
        reconcile()
    }
    private func reconcile() {
        if case .dancing(let start) = policy.phase {
            if animationStart != start { animate(since: start) }
        } else { removeAnimations() }
        timer?.invalidate(); timer = nil
        if let deadline = policy.nextDeadline {
            let next = Timer(timeInterval: max(0.001, deadline - CACurrentMediaTime()), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.policy.setEligible(self.eligible, now: CACurrentMediaTime(), delay: self.delay(afterAction: false))
                    self.policy.tick(now: CACurrentMediaTime(), nextDelay: self.delay(afterAction: true))
                    self.reconcile()
                }
            }
            next.tolerance = 0.025
            timer = next; RunLoop.main.add(next, forMode: .common)
        }
    }
    private func animate(since start: CFTimeInterval) {
        if animationStart != start {
            activeMotionID = MotionChoice.next(motionPool.map(\.id), previous: activeMotionID)
        }
        guard let motion = motionPool.first(where: { $0.id == activeMotionID }) else { removeAnimations(); return }
        textures = motion.animationFrames.map { $0.textures(motionTint, pixelScale: motionScale) }
        keys = motion.manifest.animation?.keyTimes.map(NSNumber.init(value:)) ?? []
        guard textures.count == 8, keys.count == 9 else { removeAnimations(); return }
        animationStart = start
        for (target, images) in [(baseLayer, textures.map(\.base)), (fillLayer, textures.map(\.fill)),
                                  (maskLayer, textures.map(\.mask)), (detailLayer, textures.map(\.details))] {
            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = images + [images[7]]
            animation.keyTimes = keys; animation.calculationMode = .discrete
            animation.duration = 3; animation.beginTime = start
            animation.isRemovedOnCompletion = true
            target.add(animation, forKey: "bouquet-toss")
        }
    }
    private func removeAnimations() {
        for target in [baseLayer, fillLayer, maskLayer, detailLayer] { target.removeAnimation(forKey: "bouquet-toss") }
        animationStart = nil
    }
    func stop() {
        requested = false; timer?.invalidate(); timer = nil
        policy = CharacterDancePlayback(); removeAnimations()
    }
    /// Isolated test harness only; no public tool or production UI bypass.
    func playOnceForTesting() {
        let now = CACurrentMediaTime()
        policy.resume(eligible: eligible, now: now - 25, delay: 25)
        policy.tick(now: now, nextDelay: 25); reconcile()
    }
    func displayFrameForTesting(_ index: Int) {
        guard textures.indices.contains(index) else { return }
        stop(); let t = textures[index]
        CATransaction.begin(); CATransaction.setDisableActions(true)
        baseLayer.contents = t.base; fillLayer.contents = t.fill; maskLayer.contents = t.mask; detailLayer.contents = t.details
        CATransaction.commit()
    }
    override func layout() {
        super.layout()
        let width = bounds.width, height = bounds.height
        let filled = ((fillBottom-fillTop) * percent/100).rounded()
        let top = (fillBottom-filled)/80*height
        CATransaction.begin(); CATransaction.setDisableActions(true)
        baseLayer.frame = bounds; detailLayer.frame = bounds
        fillClip.frame = CGRect(x: 0, y: top, width: width, height: filled/80*height)
        fillLayer.frame = CGRect(x: 0, y: -top, width: width, height: height)
        maskLayer.frame = CGRect(origin: .zero, size: bounds.size)
        CATransaction.commit()
    }
}

enum MotionChoice {
    static func next(_ ids: [String], previous: String?, choose: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String? {
        guard !ids.isEmpty else { return nil }
        let candidates = ids.count > 1 ? ids.filter { $0 != previous } : ids
        return candidates[min(candidates.count-1, max(0, choose(candidates.count)))]
    }
}
