import Foundation
import Testing
@testable import QuotaCore

@Test func detachedControlsAndGapStayInHoverRegion() {
    let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    for scale in [1.0, 1.5, 2] {
        for count in [0, 1, 2, 3] {
            let pet = CGRect(x: 500, y: 400, width: 72 * scale, height: 80 * scale)
            let layout = PetPanelLayout(pet: pet, windowCount: count, screen: screen, scale: scale)
            #expect(layout.detail.midY == pet.midY)
            #expect(abs(Double(layout.detail.width) - 236 * scale) < 0.01)
            #expect(abs(Double(layout.detail.height) - (count > 1 ? 80 : 60) * scale) < 0.01)
            var interaction = PetInteraction()
            interaction.pointer(pet: true, region: true, now: 0); interaction.tick(now: 0.151)
            for (i, x) in [195.0, 204, 222].enumerated() {
                let point = CGPoint(x: layout.detail.minX + x * scale, y: pet.midY)
                #expect(layout.contains(point))
                interaction.pointer(pet: false, region: layout.contains(point), now: Double(i + 1))
                interaction.tick(now: Double(i + 1) + 0.4)
                #expect(interaction.mode == .hoverDetails)
            }
            interaction.pointer(pet: false, region: false, now: 5)
            interaction.tick(now: 5.301); #expect(interaction.mode == .petOnly)
        }
    }
}

@Test func detachedControlsAreIncludedWhenFlippingLeft() {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let pet = CGRect(x: 920, y: 300, width: 72, height: 80)
    let layout = PetPanelLayout(pet: pet, windowCount: 1, screen: screen)
    #expect(layout.direction == .left)
    #expect(layout.detail.maxX == pet.minX + 36)
    #expect(screen.contains(layout.detail))
    #expect(layout.contains(CGPoint(x: layout.detail.minX + 14, y: pet.midY)))
}
