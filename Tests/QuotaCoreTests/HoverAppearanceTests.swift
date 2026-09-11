import Foundation
import Testing
@testable import QuotaCore

@Test func clickNeverPinsAndExternalShowExpires() {
    var s = PetInteraction()
    s.pointer(pet: true, region: true, now: 0); s.click(now: 0)
    #expect(s.mode == .hoverDetails)
    s.pointer(pet: false, region: true, now: 1); s.tick(now: 5)
    #expect(s.mode == .hoverDetails)
    s.pointer(pet: false, region: false, now: 6); s.tick(now: 6.301)
    #expect(s.mode == .petOnly)
    s.showTemporary(now: 10); s.pointer(pet: false, region: false, now: 11)
    s.tick(now: 12.99); #expect(s.mode == .hoverDetails)
    s.tick(now: 13); #expect(s.mode == .petOnly)
    s.showTemporary(now: 20); s.pointer(pet: false, region: true, now: 21)
    s.pointer(pet: false, region: false, now: 22); s.tick(now: 22.301)
    #expect(s.mode == .petOnly)
    s.showPinned(); s.tick(now: 100); #expect(s.mode == .keyboardDetails)
    s.releaseKeyboard(now: 101); s.tick(now: 101.301); #expect(s.mode == .petOnly)
}

@Test func allSizesPreserveBodyOverlapAndCardHeight() {
    for size in CompanionSize.allCases {
        let s = size.scale
        let pet = CGRect(origin: CGPoint(x: 500, y: 300), size: size.petSize)
        let layout = PetPanelLayout(pet: pet, windowCount: 2, screen: CGRect(x: 0, y: 0, width: 2000, height: 1400), scale: s)
        #expect(layout.direction == .right)
        #expect(layout.detail.minX == pet.minX + 36 * s)
        #expect(layout.detail.height == pet.height)
        #expect(abs(Double(layout.pet.union(layout.detail).width) - 272 * s) < 0.01)
        #expect(abs(Double(layout.bridge.width) - 36 * s) < 0.01)
    }
}

@Test func paletteBordersAndAlertsStayReadable() {
    for dark in [false, true] {
        let a = BackgroundAppearances.standard[BackgroundAppearanceKey(dark: dark, highContrast: false, reduceTransparency: false)]
        for palette in CompanionPalette.allCases {
            #expect(a.progressColor(remaining: 79, palette: palette).contrast(with: a.track) >= 3)
            for low in [30.0, 15, 5] {
                #expect(a.progressColor(remaining: low, palette: palette) == a.progressColor(remaining: low))
            }
        }
    }
    for style in ChestTextStyle.allCases { #expect(style.text.contrast(with: style.outline) > 4.5) }
}
