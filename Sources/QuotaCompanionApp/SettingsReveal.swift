import AppKit
import SwiftUI

/// Height changes, not text scaling. The disappearing subtree is immediately inert.
struct SettingsReveal<Content: View>: View {
    let expanded: Bool
    let trigger: String
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content
    var accessibility = CompanionAccessibility()
    @State private var fraction: CGFloat
    @State private var retainedContent: Content?
    init(expanded: Bool, trigger: String, spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.expanded = expanded; self.trigger = trigger; self.spacing = spacing; self.content = content
        _fraction = State(initialValue: expanded ? 1 : 0)
        _retainedContent = State(initialValue: expanded ? content() : nil)
    }
    var body: some View {
        Group {
            if expanded || fraction > 0 {
                RevealLayout(fraction: fraction) {
                    VStack(alignment: .leading, spacing: spacing) {
                        if expanded { content() } else { retainedContent }
                    }
                }.clipped().opacity(fraction)
                    .allowsHitTesting(expanded).disabled(!expanded).accessibilityHidden(!expanded)
                    .background(CollapseFocusAnchor(trigger: trigger, expanded: expanded))
            }
        }
        .task(id: expanded) {
            if expanded { retainedContent = content() }
            let target: CGFloat = expanded ? 1 : 0, start = fraction
            guard !accessibility.reduceMotion else { fraction = target; return }
            guard start != target else { return }
            let clock = ContinuousClock(), began = clock.now
            // Explicit presentation progress also animates the parent's measured height.
            // A transition on an inserted Group can otherwise fade without relayout.
            while !Task.isCancelled {
                let elapsed = began.duration(to: clock.now).components
                let t = min(1, (Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18) / 0.18)
                fraction = start + (target - start) * (t * t * (3 - 2 * t))
                if t >= 1 { break }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
        }
    }
}
private struct RevealLayout: Layout {
    let fraction: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(.init(width: proposal.width, height: nil)) ?? .zero
        return .init(width: size.width, height: size.height * max(0, min(1, fraction)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: .init(width: bounds.width, height: nil))
    }
}

/// Keep focus out of a subtree when it is removed, including a field editor owned by NSTextField.
private struct CollapseFocusAnchor: NSViewRepresentable {
    let trigger: String
    let expanded: Bool
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        view.trigger = trigger
        if !expanded { view.returnFocusIfNeeded() }
    }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.returnFocusIfNeeded() }
    final class Anchor: NSView {
        var trigger = ""
        func returnFocusIfNeeded() {
            guard let window, let root = window.contentView else { return }
            var focus = window.firstResponder as? NSView
            if let editor = focus as? NSTextView, let field = editor.delegate as? NSView { focus = field }
            guard let focus, convert(bounds, to: nil).intersects(focus.convert(focus.bounds, to: nil)) else { return }
            func find(_ node: NSView) -> NSControl? {
                if let control = node as? NSControl, control.isEnabled,
                   (control.identifier?.rawValue == trigger || control.cell?.accessibilityLabel() == trigger) { return control }
                return node.subviews.lazy.compactMap(find).first
            }
            window.makeFirstResponder(find(root))
        }
    }
}
