import Foundation
import Testing
@testable import QuotaCore

struct CustomAppearanceTests {
    @Test func colorInputs() {
        for hex in ["#000000", "ffffff", "#72d5e8", " 94A3B8 "] { #expect(RGBColor(hexString: hex) != nil) }
        for hex in ["#FFF", "#00000000", "#GG0000", "12345", "１２３４５６", "-00001"] { #expect(RGBColor(hexString: hex) == nil) }
        #expect(RGBColor(hexString: "72d5e8")?.hexString == "#72D5E8")
        #expect(RGBColor.rgbStrings(["114", "213", "232"])?.hexString == "#72D5E8")
        #expect(RGBColor.rgbStrings(["256", "0", "0"]) == nil)
        #expect(RGBColor.rgbStrings(["-1", "0", "0"]) == nil)
        #expect(RGBColor.rgbStrings(["0.5", "0", "0"]) == nil)
    }
    @Test func presetLifecycleAndIndependentSelection() throws {
        var settings = CustomAppearance()
        var preset = ColorPreset(name: "Rose", hex: "#FF8899")
        settings.save(preset)
        settings.quotaHex = preset.hex; settings.quotaPresetID = preset.id
        settings.progressHex = "#123456"; settings.progressFollowsQuota = false
        preset.hex = "#ABCDEF"; settings.save(preset)
        #expect(settings.colors.count == 1 && settings.quotaHex == "#ABCDEF")
        #expect(settings.progressHex == "#123456")
        settings.removeColor(preset.id)
        #expect(settings.colors.isEmpty && settings.quotaPresetID == nil && settings.quotaHex == "#ABCDEF")
        settings.progressFollowsQuota = true; settings.progressFollowsQuota = false
        #expect(settings.progressHex == "#123456")
        let text = TextPreset(name: "Gold", text: "#FFE5A3", outline: "#10233C")
        settings.save(text); settings.chest = text; settings.removeText(text.id)
        #expect(settings.chest == text && settings.textPresets.isEmpty)
        #expect(try JSONDecoder().decode(CustomAppearance.self, from: JSONEncoder().encode(settings)) == settings)
    }
    @Test func framingNeverExposesEdgesAndScalesUniformly() {
        for image in [CGSize(width: 100, height: 1000), CGSize(width: 1000, height: 100), CGSize(width: 300, height: 300)] {
            for height in [56.0, 80] {
                for x in [0.0, 0.5, 1] {
                    for y in [0.0, 0.5, 1] {
                        for zoom in [1.0, 2, 4] {
                            let framing = BackgroundComposition(x: x, y: y, zoom: zoom)
                            let rect = framing.imageRect(image: image, viewport: CGSize(width: 200, height: height))
                            #expect(rect.minX <= 0.0001 && rect.minY <= 0.0001)
                            #expect(rect.maxX >= 199.9999 && rect.maxY >= height - 0.0001)
                            let large = framing.imageRect(image: image, viewport: CGSize(width: 400, height: height*2))
                            #expect(abs(large.minX - rect.minX*2) < 0.0001 && abs(large.width - rect.width*2) < 0.0001)
                        }
                    }
                }
            }
        }
    }
    @Test func readabilityBoundsAndAlertPrecedence() {
        for opacity in stride(from: 0.0, through: 1, by: 0.1) {
            let protection = BackgroundReadability.protection(opacity: opacity, solid: false)
            let darkest = RGBColor(hex: 0xBBD1E2).mixed(with: RGBColor(0,0,0), amount: opacity)
                .mixed(with: RGBColor(1,1,1), amount: protection).mixed(with: RGBColor(hex: 0x587894), amount: 0.2)
            #expect(RGBColor(hex: 0x344B63).contrast(with: darkest) >= 4.5)
        }
        let a = BackgroundAppearances.standard[BackgroundAppearanceKey(dark: false, highContrast: false, reduceTransparency: false)]
        for value in [30.0, 15, 5, 0] {
            #expect(a.progressColor(remaining: value, customTint: RGBColor(hex: 0xFF00FF)) == a.progressColor(remaining: value))
        }
        for color in [RGBColor(0,0,0), RGBColor(1,1,1), RGBColor(hex: 0xFF00FF)] {
            #expect(a.progressColor(remaining: 79, customTint: color).contrast(with: a.track) >= 3)
        }
    }
}
