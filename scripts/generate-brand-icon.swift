import AppKit
import SwiftUI

struct BrandIcon: View {
    var body: some View {
        GeometryReader { g in
            let s = g.size.width
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.90, green: 0.96, blue: 1), Color(red: 0.66, green: 0.81, blue: 0.93)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().fill(Color(red: 1, green: 0.955, blue: 0.82))
                    .frame(width: s * 0.47, height: s * 0.47).offset(x: -s * 0.115, y: -s * 0.04)
                // Crescent drawn as one vector outline, not a cutout filled with background color.
                Path { p in
                    p.move(to: CGPoint(x: s * 0.69, y: s * 0.23))
                    p.addCurve(to: CGPoint(x: s * 0.76, y: s * 0.78), control1: CGPoint(x: s * 0.98, y: s * 0.40), control2: CGPoint(x: s * 0.94, y: s * 0.68))
                    p.addCurve(to: CGPoint(x: s * 0.40, y: s * 0.70), control1: CGPoint(x: s * 0.60, y: s * 0.90), control2: CGPoint(x: s * 0.44, y: s * 0.80))
                    p.addCurve(to: CGPoint(x: s * 0.69, y: s * 0.23), control1: CGPoint(x: s * 0.73, y: s * 0.77), control2: CGPoint(x: s * 0.85, y: s * 0.44))
                    p.closeSubpath()
                }.fill(Color(red: 0.38, green: 0.64, blue: 0.85))
                RoundedRectangle(cornerRadius: s * 0.225).strokeBorder(.white.opacity(0.65), lineWidth: max(0.5, s / 180))
            }
        }.aspectRatio(1, contentMode: .fit)
    }
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try MainActor.assumeIsolated {
    for size in [16, 32, 128, 256, 512] {
        for factor in [1, 2] {
            let renderer = ImageRenderer(content: BrandIcon().frame(width: CGFloat(size), height: CGFloat(size)))
            renderer.scale = CGFloat(factor)
            guard let cg = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                fatalError("Icon render failed")
            }
            let suffix = factor == 2 ? "@2x" : ""
            try data.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"), options: .atomic)
        }
    }
}

