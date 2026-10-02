import Foundation

/// Pure timing policy. The caller supplies monotonic time and schedules only
/// `nextDeadline`; Core Animation, not this model, will play discrete frames.
/// Bouquet toss: one action across 3 seconds, not three one-second loops.
public struct CharacterDancePlayback: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case suspended
        case waiting(until: TimeInterval)
        case dancing(since: TimeInterval)
    }
    public static let frameCount = 8
    public static let framesPerSecond = 8.0
    public static let duration: TimeInterval = 3
    public static let tossSequence = [0,0,0,1,1,1,2,2,3,3,3,4,4,4,5,5,5,6,6,6,7,7,7,7]
    public private(set) var phase: Phase = .suspended
    public init() {}

    public var nextDeadline: TimeInterval? {
        switch phase {
        case .suspended: nil
        case .waiting(let deadline): deadline
        case .dancing(let start): start + Self.duration
        }
    }
    /// `eligible` combines visibility, interaction, sleep/lock, reduced motion,
    /// user preference and valid animated resources. Repeated true observations
    /// (such as a quota refresh) do not reset an existing deadline or animation.
    public mutating func setEligible(_ eligible: Bool, now: TimeInterval, delay: TimeInterval) {
        guard now.isFinite else { phase = .suspended; return }
        guard eligible else { phase = .suspended; return }
        if phase == .suspended { wait(now: now, delay: delay) }
    }
    /// Call explicitly after resume; never play accumulated overdue actions.
    public mutating func resume(eligible: Bool, now: TimeInterval, delay: TimeInterval) {
        phase = .suspended
        setEligible(eligible, now: now, delay: delay)
    }
    public mutating func tick(now: TimeInterval, nextDelay: TimeInterval) {
        guard now.isFinite else { phase = .suspended; return }
        switch phase {
        case .waiting(let deadline) where now >= deadline:
            // A delayed callback after sleep/stall must not catch up a dance.
            if now - deadline > 1 { wait(now: now, delay: nextDelay) }
            else { phase = .dancing(since: now) }
        case .dancing(let start) where now >= start + Self.duration || now < start:
            if nextDelay == 0, now >= start, now - start < Self.duration + 1 { phase = .dancing(since: now) }
            else { wait(now: now, delay: nextDelay) }
        default: break
        }
    }
    public func frame(at now: TimeInterval) -> Int {
        guard case .dancing(let start) = phase, now.isFinite,
              now >= start, now < start + Self.duration else { return 0 }
        return Self.tossSequence[Int(((now - start) * Self.framesPerSecond).rounded(.down))]
    }
    private mutating func wait(now: TimeInterval, delay: TimeInterval) {
        let bounded = delay.isFinite ? min(3600, max(0, delay)) : 30
        phase = .waiting(until: now + bounded)
    }
}
