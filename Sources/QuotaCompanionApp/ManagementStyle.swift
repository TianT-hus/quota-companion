import SwiftUI

enum ManagementStyle {
    static let ink = Color(white: 0.14)
    static let secondary = Color(white: 0.43)
    static let background = Color(white: 0.985)
    static let hover = Color(white: 0.93)
    static let selection = Color(red: 0.90, green: 0.94, blue: 1)
    static let selectionBorder = Color(red: 0.15, green: 0.43, blue: 0.83)
}

struct SidebarPill: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            let radius = rect.height / 2
            p.move(to: .init(x: rect.minX, y: rect.minY))
            p.addLine(to: .init(x: rect.maxX - radius, y: rect.minY))
            p.addArc(center: .init(x: rect.maxX - radius, y: rect.midY), radius: radius,
                     startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: .init(x: rect.minX, y: rect.maxY)); p.closeSubpath()
        }
    }
}

struct ManagementNavigationRow: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15, weight: selected ? .semibold : .regular)).frame(width: 20).foregroundStyle(selected ? ManagementStyle.selectionBorder : ManagementStyle.secondary)
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular)).foregroundStyle(selected ? ManagementStyle.selectionBorder : ManagementStyle.ink)
                Spacer(minLength: 0)
            }.padding(.leading, 20).padding(.trailing, 8).frame(height: 40)
                .background(selected ? ManagementStyle.selection : hovered ? ManagementStyle.hover : .clear, in: SidebarPill())
                .overlay(SidebarPill().stroke(selected ? ManagementStyle.selectionBorder : contrast == .increased && hovered ? ManagementStyle.secondary : .clear, lineWidth: contrast == .increased ? 2 : 1))
                .contentShape(SidebarPill())
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
