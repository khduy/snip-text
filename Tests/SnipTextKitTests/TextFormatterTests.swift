import CoreGraphics
import Testing
@testable import SnipTextKit

/// Builds a fragment on a 0...1 canvas; `row` 0 is the top line.
private func line(_ text: String, row: Double, x: Double = 0.05, width: Double = 0.8,
                  height: Double = 0.04, spacing: Double = 0.05) -> OCRFragment {
    let top = 0.95 - row * spacing
    return OCRFragment(text: text, box: CGRect(x: x, y: top - height, width: width, height: height))
}

@Suite struct TextFormatterTests {
    @Test func keepsLinesInReadingOrder() {
        let fragments = [line("second", row: 1), line("first", row: 0), line("third", row: 2)]
        #expect(TextFormatter.format(fragments, mode: .keepLines) == "first\nsecond\nthird")
    }

    @Test func joinsFragmentsOnSameLineLeftToRight() {
        let fragments = [
            line("world", row: 0, x: 0.5, width: 0.3),
            line("Hello", row: 0, x: 0.05, width: 0.3),
        ]
        #expect(TextFormatter.format(fragments, mode: .keepLines) == "Hello world")
    }

    @Test func mergesWrappedLinesIntoParagraph() {
        let fragments = [line("Xin chào các", row: 0), line("bạn thân mến", row: 1)]
        #expect(TextFormatter.format(fragments, mode: .mergeParagraphs) == "Xin chào các bạn thân mến")
    }

    @Test func splitsParagraphsOnLargeGap() {
        let fragments = [line("Đoạn một", row: 0), line("Đoạn hai", row: 2.5)]
        #expect(TextFormatter.format(fragments, mode: .mergeParagraphs) == "Đoạn một\n\nĐoạn hai")
    }

    @Test func removesHyphenationWhenMerging() {
        let fragments = [line("recog-", row: 0), line("nition works", row: 1)]
        #expect(TextFormatter.format(fragments, mode: .mergeParagraphs) == "recognition works")
    }

    @Test func keepsHyphenBeforeCapitalOrNumber() {
        let fragments = [line("COVID-", row: 0), line("19 era", row: 1)]
        #expect(TextFormatter.format(fragments, mode: .mergeParagraphs) == "COVID- 19 era")
    }

    @Test func emptyInputGivesEmptyString() {
        #expect(TextFormatter.format([], mode: .mergeParagraphs) == "")
        #expect(TextFormatter.format([line("   ", row: 0)], mode: .keepLines) == "")
    }
}
