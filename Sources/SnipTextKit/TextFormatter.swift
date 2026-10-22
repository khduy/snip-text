import CoreGraphics

/// One piece of recognized text with its bounding box in normalized image
/// coordinates (0...1, origin at the bottom-left, as Vision reports it).
public struct OCRFragment: Sendable, Equatable {
    public var text: String
    public var box: CGRect

    public init(text: String, box: CGRect) {
        self.text = text
        self.box = box
    }
}

public enum LineBreakMode: String, CaseIterable, Sendable, Identifiable {
    /// Keep every visual line on its own line.
    case keepLines
    /// Join wrapped lines into paragraphs; blank line between paragraphs.
    case mergeParagraphs
    /// Keep lines and rebuild the leading spaces from where each line starts, for code.
    /// Assumes a monospaced font; Vision itself drops all leading whitespace.
    case preserveIndent

    public var id: String { rawValue }
}

public enum TextFormatter {
    /// A one-line preview for menus and toasts: whitespace runs (line breaks included)
    /// collapse to one space, and anything past `limit` characters becomes "…".
    public static func snippet(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return flat.count > limit ? flat.prefix(limit - 1) + "…" : flat
    }

    /// Turns raw fragments into text, ordered top-to-bottom then left-to-right.
    public static func format(_ fragments: [OCRFragment], mode: LineBreakMode) -> String {
        let groups = groupIntoLines(fragments)
        guard !groups.isEmpty else { return "" }

        switch mode {
        case .keepLines:
            return groups.map { joinWords($0).text }.joined(separator: "\n")
        case .mergeParagraphs:
            return mergeParagraphs(groups.map(joinWords))
        case .preserveIndent:
            return indentedLines(groups)
        }
    }

    /// Fragments whose vertical centers are close are treated as one visual line.
    /// Each line comes back ordered left to right, with whitespace-only fragments dropped.
    static func groupIntoLines(_ fragments: [OCRFragment]) -> [[OCRFragment]] {
        let sorted = fragments
            .map { OCRFragment(text: $0.text.trimmingCharacters(in: .whitespaces), box: $0.box) }
            .filter { !$0.text.isEmpty }
            .sorted { $0.box.midY > $1.box.midY }

        var groups: [[OCRFragment]] = []
        for fragment in sorted {
            if let last = groups.last?.last,
               abs(last.box.midY - fragment.box.midY) < min(last.box.height, fragment.box.height) * 0.5 {
                groups[groups.count - 1].append(fragment)
            } else {
                groups.append([fragment])
            }
        }
        return groups.map { $0.sorted { $0.box.minX < $1.box.minX } }
    }

    /// One line of prose. A gap wider than a few characters, as between table columns,
    /// becomes a tab so the columns stay apart when pasted.
    static func joinWords(_ parts: [OCRFragment]) -> OCRFragment {
        var text = parts[0].text
        for (previous, current) in zip(parts, parts.dropFirst()) {
            let charWidth = (characterWidth(previous) + characterWidth(current)) / 2
            let gap = current.box.minX - previous.box.maxX
            text += gap > charWidth * 3 ? "\t" : " "
            text += current.text
        }
        let box = parts.dropFirst().reduce(parts[0].box) { $0.union($1.box) }
        return OCRFragment(text: text, box: box)
    }

    /// Lines of code: every horizontal gap, leading ones included, becomes as many spaces as
    /// characters would fit in it, measured from the leftmost line.
    static func indentedLines(_ groups: [[OCRFragment]]) -> String {
        // The median, from fragments long enough to average out the box's padding.
        let fragments = Array(groups.joined())
        let samples = fragments.filter { $0.text.count >= 3 }
        let widths = (samples.isEmpty ? fragments : samples).map(characterWidth).sorted()
        let charWidth = widths[widths.count / 2]
        let left = groups.map { $0[0].box.minX }.min() ?? 0

        func spaces(_ width: CGFloat) -> String {
            guard charWidth > 0, width > 0 else { return "" }
            return String(repeating: " ", count: Int((width / charWidth).rounded()))
        }

        return groups.map { parts in
            var text = spaces(parts[0].box.minX - left) + parts[0].text
            for (previous, current) in zip(parts, parts.dropFirst()) {
                let gap = spaces(current.box.minX - previous.box.maxX)
                text += (gap.isEmpty ? " " : gap) + current.text
            }
            return text
        }.joined(separator: "\n")
    }

    static func mergeParagraphs(_ lines: [OCRFragment]) -> String {
        var result = lines[0].text
        for (previous, current) in zip(lines, lines.dropFirst()) {
            let gap = previous.box.minY - current.box.maxY
            let lineHeight = (previous.box.height + current.box.height) / 2

            if gap > lineHeight * 0.8 {
                result += "\n\n" + current.text
            } else if startsListItem(current.text) {
                result += "\n" + current.text
            } else if endsWithHyphenatedWord(result), current.text.first?.isLowercase == true {
                result.removeLast()
                result += current.text
            } else {
                result += " " + current.text
            }
        }
        return result
    }

    /// Average width of one character in the fragment, in the same units as its box.
    private static func characterWidth(_ fragment: OCRFragment) -> CGFloat {
        fragment.box.width / CGFloat(max(fragment.text.count, 1))
    }

    /// "• item", "- item", "1. item", "2) item": a new item, not the wrap of the line above.
    private static func startsListItem(_ text: String) -> Bool {
        text.prefixMatch(of: #/(?:[•◦▪▫●○■□‣⁃∙·*+–—-]|\d{1,3}[.)])\s/#) != nil
    }

    private static func endsWithHyphenatedWord(_ text: String) -> Bool {
        guard text.hasSuffix("-") else { return false }
        return text.dropLast().last?.isLetter == true
    }
}
