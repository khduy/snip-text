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

    @Test func separatesTableColumnsWithTab() {
        let fragments = [
            line("Tên", row: 0, x: 0.05, width: 0.06), line("Giá", row: 0, x: 0.5, width: 0.06),
            line("Cà phê", row: 1, x: 0.05, width: 0.12), line("25.000", row: 1, x: 0.5, width: 0.12),
        ]
        #expect(TextFormatter.format(fragments, mode: .keepLines) == "Tên\tGiá\nCà phê\t25.000")
    }

    @Test func keepsListItemsOnTheirOwnLines() {
        let fragments = [
            line("Cần làm:", row: 0), line("• gọi điện", row: 1), line("• gửi báo giá cho", row: 2),
            line("khách hàng", row: 3), line("2. họp nhóm", row: 4), line("- dọn bàn", row: 5),
        ]
        #expect(TextFormatter.format(fragments, mode: .mergeParagraphs)
            == "Cần làm:\n• gọi điện\n• gửi báo giá cho khách hàng\n2. họp nhóm\n- dọn bàn")
    }

    @Test func rebuildsIndentationForCode() {
        // 0.02 per character: "func run() {" is 12 characters wide.
        let fragments = [
            line("func run() {", row: 0, x: 0.05, width: 0.24),
            line("let x = 1", row: 1, x: 0.13, width: 0.18),
            line("if x > 0 {", row: 2, x: 0.13, width: 0.20),
            line("go()", row: 3, x: 0.21, width: 0.08),
            line("// done", row: 3, x: 0.35, width: 0.14),
            line("}", row: 4, x: 0.13, width: 0.02),
            line("}", row: 5, x: 0.05, width: 0.02),
        ]
        #expect(TextFormatter.format(fragments, mode: .preserveIndent) == """
            func run() {
                let x = 1
                if x > 0 {
                    go()   // done
                }
            }
            """)
    }

    @Test func emptyInputGivesEmptyString() {
        #expect(TextFormatter.format([], mode: .mergeParagraphs) == "")
        #expect(TextFormatter.format([line("   ", row: 0)], mode: .keepLines) == "")
    }

    @Test func snippetFlattensWhitespace() {
        #expect(TextFormatter.snippet("  Hoá đơn\n\nsố   00123 ", limit: 40) == "Hoá đơn số 00123")
    }

    @Test func snippetTruncatesToLimit() {
        #expect(TextFormatter.snippet("abcdefghij", limit: 5) == "abcd…")
        #expect(TextFormatter.snippet("abcde", limit: 5) == "abcde")
    }

    @Test func snippetWithNonPositiveLimitIsEmpty() {
        #expect(TextFormatter.snippet("abc", limit: 0) == "")
        #expect(TextFormatter.snippet("abc", limit: -3) == "")
    }
}
