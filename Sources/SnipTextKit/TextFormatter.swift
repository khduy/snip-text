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
        let lines = groupIntoLines(fragments)
        guard !lines.isEmpty else { return "" }

        switch mode {
        case .keepLines:
            return lines.map(\.text).joined(separator: "\n")
        case .mergeParagraphs:
            return mergeParagraphs(lines)
        }
    }

    /// Fragments whose vertical centers are close are treated as one visual line.
    static func groupIntoLines(_ fragments: [OCRFragment]) -> [OCRFragment] {
        let sorted = fragments
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
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

        return groups.map { group in
            let ordered = group.sorted { $0.box.minX < $1.box.minX }
            let text = ordered.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            let box = ordered.dropFirst().reduce(ordered[0].box) { $0.union($1.box) }
            return OCRFragment(text: text, box: box)
        }
    }

    static func mergeParagraphs(_ lines: [OCRFragment]) -> String {
        var result = lines[0].text
        for (previous, current) in zip(lines, lines.dropFirst()) {
            let gap = previous.box.minY - current.box.maxY
            let lineHeight = (previous.box.height + current.box.height) / 2

            if gap > lineHeight * 0.8 {
                result += "\n\n" + current.text
            } else if endsWithHyphenatedWord(result), current.text.first?.isLowercase == true {
                result.removeLast()
                result += current.text
            } else {
                result += " " + current.text
            }
        }
        return result
    }

    private static func endsWithHyphenatedWord(_ text: String) -> Bool {
        guard text.hasSuffix("-") else { return false }
        return text.dropLast().last?.isLetter == true
    }
}
