import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Deterministic, synthetic fixtures only. Never reads a user's photos.
let destinationDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
func save(_ name: String, width: Int, height: Int, draw: (CGContext) -> Void) throws {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(context)
    let url = destinationDirectory.appendingPathComponent(name + ".png")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Fixture encoding failed") }
    print(url.path)
}
try save("vivid-landscape", width: 1200, height: 700) { context in
    let colors = [CGColor(red: 0.13, green: 0.05, blue: 0.4, alpha: 1),
                  CGColor(red: 1, green: 0.2, blue: 0.4, alpha: 1),
                  CGColor(red: 1, green: 0.75, blue: 0.1, alpha: 1)]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.6, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 700), end: CGPoint(x: 1200, y: 0), options: [])
    context.setFillColor(CGColor(red: 1, green: 0.9, blue: 0.7, alpha: 1))
    context.fillEllipse(in: CGRect(x: 830, y: 330, width: 190, height: 190))
    context.setFillColor(CGColor(red: 0.03, green: 0.12, blue: 0.32, alpha: 1))
    context.move(to: .zero); context.addLine(to: CGPoint(x: 280, y: 350)); context.addLine(to: CGPoint(x: 500, y: 140))
    context.addLine(to: CGPoint(x: 780, y: 270)); context.addLine(to: CGPoint(x: 1200, y: 0)); context.closePath(); context.fillPath()
}
try save("busy-texture", width: 700, height: 1200) { context in
    for y in stride(from: 0, to: 1200, by: 8) { for x in stride(from: 0, to: 700, by: 8) {
        context.setFillColor((x/8 + y/8).isMultiple(of: 2) ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: x, y: y, width: 8, height: 8))
    } }
}
try save("sprite-v2", width: 1536, height: 2288) { context in
    for row in 0..<11 { for column in 0..<8 {
        let rect = CGRect(x: column * 192 + 28, y: row * 208 + 32, width: 136, height: 144)
        context.setFillColor(CGColor(red: 0.3, green: 0.78, blue: 0.94, alpha: 1))
        context.fillEllipse(in: rect)
        context.setFillColor(CGColor(gray: 0.08, alpha: 1))
        for offset in [40, 85] { context.fillEllipse(in: CGRect(x: rect.minX + CGFloat(offset), y: rect.midY, width: 12, height: 12)) }
    } }
}
