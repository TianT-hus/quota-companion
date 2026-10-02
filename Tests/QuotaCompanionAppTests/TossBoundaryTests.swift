import AppKit
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@Suite @MainActor struct TossBoundaryTests {
    private func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width*image.height*4)
        bytes.withUnsafeMutableBytes {
            let context = CGContext(data: $0.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width*4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
    @Test func correctedLayersHaveNoForeignSkirtAndKeepFlight() throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_TOSS_CHARACTER"],
              let previous = ProcessInfo.processInfo.environment["QUOTA_TOSS_ORIGINAL"] else { return }
        let clean = try ImportedCharacter(id: "clean", prepared: CharacterPackageStore.prepare(folder: URL(fileURLWithPath: path)))
        let old = try ImportedCharacter(id: "old", prepared: CharacterPackageStore.prepare(folder: URL(fileURLWithPath: previous)))
        #expect(clean.manifest.animation == old.manifest.animation)
        #expect(clean.manifest.label == old.manifest.label)
        #expect(rgba(clean.base) == rgba(old.base))
        let w = 288, h = 320
        var changed = 0
        for (frame, pair) in zip(clean.animationFrames, old.animationFrames).enumerated() {
            let (a,b) = pair
            let layers = [(rgba(a.base),rgba(b.base)),(rgba(a.fillMask),rgba(b.fillMask)),(rgba(a.details),rgba(b.details))]
            for (after,before) in layers {
                for p in 0..<w*h where Array(after[p*4..<p*4+4]) != Array(before[p*4..<p*4+4]) {
                    changed += 1
                    #expect(p/w >= 240 && (p%w < 28 || p%w > w-28))
                    #expect(after[p*4+3] == 0)
                    #expect([1,2,5].contains(frame))
                }
            }
            let base = layers[0].0, mask = layers[1].0, detail = layers[2].0
            for p in 0..<w*h where base[p*4+3] == 0 {
                #expect(mask[p*4+3] == 0 && detail[p*4+3] == 0)
            }
        }
        #expect(changed > 0)
        print("Reviewed boundary cleanup: \(changed) layer-pixels changed, flight/face/rest unchanged")
    }
}
