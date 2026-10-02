import AppKit
import SwiftUI

/// Attachments occupy one UTF-16 character; cursor movement and deletion stay atomic.
final class SpeechTokenAttachment: NSTextAttachment {
    let token: SpeechToken
    @MainActor init(_ token: SpeechToken, title: String) {
        self.token = token
        super.init(data: nil, ofType: nil)
        attachmentCell = SpeechTokenCell(title: title)
    }
    required init?(coder: NSCoder) { return nil }
}

final class SpeechTokenCell: NSTextAttachmentCell {
    let label: String
    init(title: String) { label = title; super.init(textCell: title); setAccessibilityLabel(title) }
    required init(coder: NSCoder) { label = ""; super.init(coder: coder) }
    override func cellSize() -> NSSize {
        let size = (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)])
        return NSSize(width: ceil(size.width) + 14, height: 23)
    }
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -5) }
    override func draw(withFrame frame: NSRect, in controlView: NSView?) {
        NSColor(srgbRed: 0.89, green: 0.94, blue: 1, alpha: 1).setFill()
        let path = NSBezierPath(roundedRect: frame.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
        path.fill()
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast { NSColor.labelColor.setStroke(); path.lineWidth = 1; path.stroke() }
        (label as NSString).draw(in: frame.insetBy(dx: 7, dy: 3), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
    }
}

enum SpeechInlineDocument {
    static let pasteboardType = NSPasteboard.PasteboardType("dev.quota-companion.speech-pieces-v2")
    @MainActor static func attributed(_ pieces: [SpeechPiece], copy: Copybook) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for piece in pieces {
            if let token = piece.token { result.append(NSAttributedString(attachment: SpeechTokenAttachment(token, title: token.title(copy)))) }
            else { result.append(NSAttributedString(string: piece.text)) }
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4
        result.addAttributes([.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph], range: NSRange(location: 0, length: result.length))
        return result
    }
    static func pieces(_ text: NSAttributedString) -> [SpeechPiece] {
        var result: [SpeechPiece] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { attachment, range, _ in
            if let token = attachment as? SpeechTokenAttachment { result.append(.value(token.token)) }
            else { result.append(.words((text.string as NSString).substring(with: range))) }
        }
        return SpeechTemplate(kind: .schedule, pieces: result).normalizedPieces
    }
    static func sameContent(_ a: [SpeechPiece], _ b: [SpeechPiece]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.token == $1.token && $0.text == $1.text }
    }
}

@MainActor final class SpeechInlineActions: ObservableObject {
    weak var editor: SpeechInlineTextView?
    func insert(_ token: SpeechToken) { editor?.insertToken(token) }
}

final class SpeechInlineTextView: NSTextView {
    var copybook = Copybook(language: .system)
    var allowedTokens: [SpeechToken] = []
    private func beginAtomicEdit() -> Bool {
        breakUndoCoalescing()
        let automatic = undoManager?.groupsByEvent ?? true
        if automatic, undoManager?.groupingLevel == 1 { undoManager?.endUndoGrouping() }
        undoManager?.groupsByEvent = false
        undoManager?.beginUndoGrouping()
        return automatic
    }
    private func endAtomicEdit(_ automatic: Bool) {
        breakUndoCoalescing()
        undoManager?.endUndoGrouping()
        undoManager?.groupsByEvent = automatic
    }
    func insertToken(_ token: SpeechToken) {
        guard allowedTokens.contains(token) else { return }
        // Finish an IME composition before inserting an atomic attachment.
        if hasMarkedText() { inputContext?.discardMarkedText(); unmarkText() }
        window?.makeFirstResponder(self)
        let automatic = beginAtomicEdit()
        insertText(SpeechInlineDocument.attributed([.value(token)], copy: copybook), replacementRange: selectedRange())
        endAtomicEdit(automatic)
    }
    override func copy(_ sender: Any?) {
        guard selectedRange().length > 0 else { return }
        let pieces = SpeechInlineDocument.pieces(attributedSubstring(forProposedRange: selectedRange(), actualRange: nil) ?? NSAttributedString())
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(pieces.map { $0.token.map { "【\($0.title(copybook))】" } ?? $0.text }.joined(), forType: .string)
        if let data = try? JSONEncoder().encode(pieces) { board.setData(data, forType: SpeechInlineDocument.pasteboardType) }
    }
    override func cut(_ sender: Any?) { copy(sender); if selectedRange().length > 0 { insertText("", replacementRange: selectedRange()) } }
    override func paste(_ sender: Any?) {
        let automatic = beginAtomicEdit()
        defer { endAtomicEdit(automatic) }
        let board = NSPasteboard.general
        if let data = board.data(forType: SpeechInlineDocument.pasteboardType), data.count <= 100_000,
           let pieces = try? JSONDecoder().decode([SpeechPiece].self, from: data) {
            let compatible = pieces.map { piece in
                if let token = piece.token, !allowedTokens.contains(token) { return SpeechPiece.words("【\(token.title(copybook))】") }
                return piece
            }
            insertText(SpeechInlineDocument.attributed(compatible, copy: copybook), replacementRange: selectedRange())
        } else if let text = board.string(forType: .string) { insertText(text, replacementRange: selectedRange()) }
    }
}

struct SpeechInlineEditor: NSViewRepresentable {
    @Binding var template: SpeechTemplate
    let copy: Copybook
    let actions: SpeechInlineActions
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let text = SpeechInlineTextView(frame: .init(x: 0, y: 0, width: 450, height: 112))
        text.isRichText = true; text.importsGraphics = false; text.allowsUndo = true
        text.isAutomaticQuoteSubstitutionEnabled = false; text.isAutomaticTextReplacementEnabled = false
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.textContainerInset = .init(width: 8, height: 8)
        text.font = .systemFont(ofSize: 13); text.delegate = context.coordinator
        text.setAccessibilityLabel(copy.text("播报文案，文字与信息块", "Announcement text and fields"))
        text.setAccessibilityIdentifier("speech.template.inline")
        scroll.documentView = text; actions.editor = text
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let text = scroll.documentView as? SpeechInlineTextView else { return }
        actions.editor = text; text.copybook = copy; text.allowedTokens = template.availableTokens
        guard !text.hasMarkedText(), !SpeechInlineDocument.sameContent(SpeechInlineDocument.pieces(text.attributedString()), template.normalizedPieces) else { return }
        text.textStorage?.setAttributedString(SpeechInlineDocument.attributed(template.normalizedPieces, copy: copy))
        text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0))
        text.undoManager?.removeAllActions()
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SpeechInlineEditor
        init(_ parent: SpeechInlineEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? SpeechInlineTextView, !text.hasMarkedText() else { return }
            parent.template.pieces = SpeechInlineDocument.pieces(text.attributedString())
        }
    }
}
