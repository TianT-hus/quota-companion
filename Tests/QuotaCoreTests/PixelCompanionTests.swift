import Foundation
import Testing
@testable import QuotaCore

struct PixelCompanionTests {
    @Test func fillBoundaries() {
        #expect([100.0, 30, 15, 5, 0].map { PixelCatGeometry.filledRows(remaining: $0) } == [36, 11, 5, 2, 0])
        #expect(PixelCatGeometry.filledRows(remaining: nil) == 0)
        #expect(PixelCatGeometry.filledRows(remaining: .nan) == 0)
        #expect(PixelCatGeometry.filledRows(remaining: -1) == 0)
        #expect(PixelCatGeometry.filledRows(remaining: 101) == 36)
    }
    @Test func hoverDelayAndGapGrace() {
        var s = PetInteraction()
        s.pointer(pet: true, region: true, now: 0)
        s.tick(now: 0.149); #expect(s.mode == .petOnly)
        s.tick(now: 0.15); #expect(s.mode == .hoverDetails)
        s.pointer(pet: false, region: true, now: 0.2)
        s.tick(now: 2); #expect(s.mode == .hoverDetails)
        s.pointer(pet: false, region: false, now: 3)
        s.tick(now: 3.29); #expect(s.mode == .hoverDetails)
        s.pointer(pet: false, region: true, now: 3.295)
        s.tick(now: 4); #expect(s.mode == .hoverDetails)
        s.pointer(pet: false, region: false, now: 5)
        s.tick(now: 5.31); #expect(s.mode == .petOnly)
    }
    @Test func fastPassAndManualSuppression() {
        var s = PetInteraction()
        s.pointer(pet: true, region: true, now: 0)
        s.pointer(pet: false, region: false, now: 0.1)
        s.tick(now: 1); #expect(s.mode == .petOnly)
        s.pointer(pet: true, region: true, now: 2); s.click()
        #expect(s.mode == .hoverDetails)
        s.close(); s.tick(now: 3); #expect(s.mode == .petOnly && s.suppressed)
        s.pointer(pet: true, region: true, now: 4); s.tick(now: 5); #expect(s.mode == .petOnly)
        s.pointer(pet: false, region: false, now: 6)
        s.pointer(pet: true, region: true, now: 7); s.tick(now: 7.2)
        #expect(s.mode == .hoverDetails)
    }
    @Test func dragAndMenuHold() {
        var s = PetInteraction()
        s.pointer(pet: true, region: true, now: 0); s.tick(now: 0.2)
        s.beginDrag(); #expect(s.mode == .petOnly && s.openAt == nil)
        s.endDrag(); #expect(s.suppressed)
        s.showPinned(); s.beginDrag(); #expect(s.mode == .petOnly)
        s.endDrag(); s.showTemporary(now: 1)
        s.hold(true, now: 2); s.pointer(pet: false, region: false, now: 2)
        s.tick(now: 20); #expect(s.mode == .hoverDetails)
        s.hold(false, now: 21); s.tick(now: 21.31); #expect(s.mode == .petOnly)
        #expect(PointerIntent.classify(delta: CGSize(width: 4, height: 0)) == .drag)
        #expect(PointerIntent.classify(delta: CGSize(width: 3.9, height: 0)) == .click)
    }
    @Test func directionsAndConstrainedLayouts() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let pet = CGRect(x: 400, y: 300, width: 72, height: 80)
        let right = PetPanelLayout(pet: pet, windowCount: 1, screen: screen)
        #expect(right.direction == .right && right.detail.size == GlassDetailMetrics(windowCount: 1).size)
        #expect(right.detail.midY == pet.midY)
        #expect(right.contains(CGPoint(x: pet.maxX + 4, y: pet.midY)))
        let left = PetPanelLayout(pet: CGRect(x: 920, y: 300, width: 72, height: 80), windowCount: 2, screen: screen)
        #expect(left.direction == .left && left.detail.height == 80)
        let narrow = CGRect(x: 0, y: 0, width: 250, height: 800)
        #expect(PetPanelLayout(pet: CGRect(x: 100, y: 300, width: 72, height: 80), windowCount: 1, screen: narrow).direction == .above)
        #expect(PetPanelLayout(pet: CGRect(x: 100, y: 700, width: 72, height: 80), windowCount: 1, screen: narrow).direction == .below)
        let tiny = CGRect(x: 0, y: 0, width: 220, height: 180)
        let constrained = PetPanelLayout(pet: CGRect(x: 74, y: 50, width: 72, height: 80), windowCount: 2, screen: tiny)
        #expect(tiny.contains(constrained.detail))
        #expect(constrained.pet.intersection(constrained.detail).width <= 36)
    }
}
