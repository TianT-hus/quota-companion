import AppKit
import Testing
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor struct TimeSegmentInputTests {
    @Test func typingPasteReplacementAndDeletion() {
        for text in ["", "0", "09", "23", "24", "99"] { #expect(TimeSegmentInput.accepts(text)) }
        for text in ["100", "12345", "1\n", "\n", "12:30", " 9", "九", "１２", "-1", "1.5"] { #expect(!TimeSegmentInput.accepts(text)) }
        #expect(TimeSegmentInput.accepts("12", range: NSRange(location: 0, length: 2), replacement: "09"))
        #expect(!TimeSegmentInput.accepts("12", range: NSRange(location: 2, length: 0), replacement: "3"))
        #expect(!TimeSegmentInput.accepts("12", range: NSRange(location: 0, length: 2), replacement: "123"))
        #expect(TimeSegmentInput.accepts("12", range: NSRange(location: 0, length: 2), replacement: ""))
        #expect(!TimeSegmentInput.accepts("12", range: NSRange(location: 3, length: 1), replacement: ""))
    }
    @Test func fieldEditorRejectsInvalidAndMarkedInput() {
        let editor = SegmentFieldEditor()
        editor.string = "12"
        #expect(!editor.shouldChangeText(in: NSRange(location: 2, length: 0), replacementString: "3"))
        #expect(!editor.shouldChangeText(in: NSRange(location: 0, length: 2), replacementString: "\n"))
        editor.setMarkedText("中文", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: 0, length: 2))
        #expect(editor.string == "12")
        editor.insertText("345", replacementRange: NSRange(location: 0, length: 2))
        #expect(editor.string == "12")
        editor.insertText("1\n2", replacementRange: NSRange(location: 0, length: 2))
        #expect(editor.string == "12")
        editor.insertText("09", replacementRange: NSRange(location: 0, length: 2))
        #expect(editor.string == "09")
        let formatter = TimeSegmentFormatter()
        #expect(!formatter.isPartialStringValid("123", newEditingString: nil, errorDescription: nil))
        #expect(formatter.isPartialStringValid("", newEditingString: nil, errorDescription: nil))
    }
}
