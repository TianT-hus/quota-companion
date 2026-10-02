import Testing
@testable import QuotaCore

struct CharacterDancePlaybackTests {
    @Test func waitsWithinRangeAndTossesOnce() {
        var s = CharacterDancePlayback()
        s.setEligible(true, now: 0, delay: 25)
        #expect(s.nextDeadline == 25)
        s.tick(now: 24.999, nextDelay: 40)
        #expect(s.frame(at: 24.999) == 0)
        s.tick(now: 25, nextDelay: 40)
        #expect(s.phase == .dancing(since: 25))
        for index in 0..<24 { #expect(s.frame(at: 25 + Double(index) / 8) == CharacterDancePlayback.tossSequence[index]) }
        #expect(s.frame(at: 28) == 0)
        s.tick(now: 28, nextDelay: 40)
        #expect(s.phase == .waiting(until: 68))
    }
    @Test func interactionStopsImmediatelyAndLeavingStartsFreshWait() {
        var s = CharacterDancePlayback()
        s.setEligible(true, now: 0, delay: 25); s.tick(now: 25, nextDelay: 25)
        #expect(s.frame(at: 25.5) == 1)
        s.setEligible(false, now: 25.5, delay: 25)
        #expect(s.frame(at: 25.5) == 0 && s.nextDeadline == nil)
        s.setEligible(true, now: 30, delay: 35)
        #expect(s.phase == .waiting(until: 65))
    }
    @Test func quotaUpdatesDoNotRestartSchedule() {
        var s = CharacterDancePlayback()
        s.setEligible(true, now: 0, delay: 25)
        s.setEligible(true, now: 10, delay: 40)
        #expect(s.nextDeadline == 25)
        s.tick(now: 25, nextDelay: 30)
        s.setEligible(true, now: 26, delay: 40)
        #expect(s.phase == .dancing(since: 25))
    }
    @Test func resumeAndLateCallbacksDoNotCatchUp() {
        var s = CharacterDancePlayback()
        s.setEligible(true, now: 0, delay: 25)
        s.tick(now: 200, nextDelay: 30)
        #expect(s.phase == .waiting(until: 230))
        s.resume(eligible: true, now: 300, delay: 25)
        #expect(s.phase == .waiting(until: 325))
        s.resume(eligible: false, now: 400, delay: 25)
        #expect(s.phase == .suspended)
    }
    @Test func invalidDelayAndTimeAreSafe() {
        for (delay, deadline) in [(-10.0, 0.0), (100, 100), (9999, 3600), (.nan, 30), (.infinity, 30)] {
            var s = CharacterDancePlayback()
            s.setEligible(true, now: 0, delay: delay)
            #expect(s.nextDeadline == deadline)
            s.tick(now: .nan, nextDelay: 25)
            #expect(s.phase == .suspended && s.frame(at: .infinity) == 0)
        }
    }
    @Test func configurableStartToStartFrequencyAndContinuous() {
        for frequency in [AnimationFrequency.once, .twice, .four] {
            var state = CharacterDancePlayback()
            let period = frequency.period!
            state.resume(eligible: true, now: 0, delay: frequency.delay(afterAction: false, naturalDelay: 30))
            for index in 1...8 {
                let start = Double(index) * period
                state.tick(now: start, nextDelay: frequency.delay(afterAction: true, naturalDelay: 30))
                #expect(state.phase == .dancing(since: start))
                state.tick(now: start + 3, nextDelay: frequency.delay(afterAction: true, naturalDelay: 30))
                #expect(state.nextDeadline == start + period)
            }
        }
        var state = CharacterDancePlayback()
        state.resume(eligible: true, now: 0, delay: 0)
        for time in stride(from: 0.0, through: 30.0, by: 3) {
            state.tick(now: time, nextDelay: 0); #expect(state.phase == .dancing(since: time))
        }
        state.setEligible(false, now: 31, delay: 0)
        #expect(state.phase == .suspended && state.nextDeadline == nil)
        #expect(AnimationFrequency.natural.delay(afterAction: true, naturalDelay: 40) == 40)
    }
}
