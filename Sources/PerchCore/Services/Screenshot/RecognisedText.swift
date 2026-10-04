import CoreGraphics
import Foundation

/// One line Vision recognised, and where it sat in the image.
///
/// `boundingBox` is in Vision's own space: normalised to 0…1 and with the
/// origin at the bottom left, so a larger `midY` is higher on the screen.
public struct RecognisedLine: Equatable, Sendable {
    public var text: String
    public var boundingBox: CGRect
    public var confidence: Float

    public init(text: String, boundingBox: CGRect, confidence: Float) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

/// Turns Vision's lines back into text somebody can paste (TC-SCR-008).
///
/// Vision returns lines in no promised order and knows nothing about
/// paragraphs, so the order and the breaks are decided here, where they can
/// be tested without an image.
public enum RecognisedText {

    /// Below this a line is more likely a texture than a word. Vision finds
    /// letters in icons and gradients at low confidence, and pasting those
    /// is worse than pasting nothing.
    public static let minimumConfidence: Float = 0.3

    /// A gap this many times the usual line spacing is a paragraph break
    /// rather than the next line.
    static let paragraphGap: CGFloat = 1.6

    public static func assemble(_ lines: [RecognisedLine]) -> String {
        let usable = lines.filter {
            $0.confidence >= minimumConfidence
                && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !usable.isEmpty else { return "" }

        let ordered = usable.sorted(by: readsBefore)
        let gaps = zip(ordered, ordered.dropFirst()).map { gap(between: $0, and: $1) }
        let usual = median(gaps.filter { $0 > 0 })

        var text = ordered[0].text.trimmingCharacters(in: .whitespaces)
        for (previous, line) in zip(ordered, ordered.dropFirst()) {
            // With no usual gap to compare against — two lines, or lines
            // that overlap — everything is one paragraph.
            let isBreak = usual > 0 && gap(between: previous, and: line) > usual * paragraphGap
            text += isBreak ? "\n\n" : "\n"
            text += line.text.trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    /// Top to bottom, and left to right for lines sharing a row. Two lines
    /// whose centres are within half a line height of each other are on the
    /// same row — a table, or a label beside its value.
    static func readsBefore(_ lhs: RecognisedLine, _ rhs: RecognisedLine) -> Bool {
        let tolerance = max(lhs.boundingBox.height, rhs.boundingBox.height) / 2
        if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) <= tolerance {
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        return lhs.boundingBox.midY > rhs.boundingBox.midY
    }

    private static func gap(between upper: RecognisedLine, and lower: RecognisedLine) -> CGFloat {
        upper.boundingBox.minY - lower.boundingBox.maxY
    }

    /// The median rather than the mean: one big gap above a heading would
    /// pull a mean up far enough that no break was ever found.
    static func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
