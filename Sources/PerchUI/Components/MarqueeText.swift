import AppKit
import SwiftUI

/// A single line of text that scrolls itself when it does not fit.
///
/// Every module that shows a title needs this, because the island is narrow
/// and song titles, file names and meeting subjects are not (TC-MED-006).
///
/// It scrolls **only** when it has to, and only while it is on screen. A
/// marquee still animating a title that already fits is a wakeup every frame
/// for no information (`CLAUDE.md` §5.1). With Reduce Motion on it does not
/// scroll at all — it truncates.
///
/// The text is measured with AppKit rather than with a `GeometryReader` and a
/// preference key. It is the same measurement, it is exact, and it costs one
/// function call instead of an extra layout pass on every module that shows a
/// title.
public struct MarqueeText: View {

    private let text: String
    private let weight: Font.Weight
    private let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Points per second. Slow enough to read, which is the whole point.
    private let speed: Double = 26

    /// How long the text sits still at each end before moving off.
    private let dwell: Double = 1.6

    public init(_ text: String, weight: Font.Weight = .regular, size: CGFloat = 13) {
        self.text = text
        self.weight = weight
        self.size = size
    }

    public var body: some View {
        GeometryReader { proxy in
            let overflow = max(0, measuredWidth - proxy.size.width)

            Group {
                if overflow > 1 && !reduceMotion {
                    TimelineView(.animation) { context in
                        label
                            .fixedSize()
                            .offset(x: offset(at: context.date, overflow: overflow))
                    }
                } else {
                    label.truncationMode(.tail)
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
            .clipped()
        }
        .frame(height: size * 1.35)
        .accessibilityLabel(Text(text))
    }

    private var label: some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .lineLimit(1)
    }

    private var measuredWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: weight.nsWeight)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// A there-and-back cycle: dwell, scroll left, dwell, scroll back.
    ///
    /// Derived from the clock rather than held in state, so nothing has to be
    /// stepped, reset or cancelled — the view simply stops being asked the
    /// moment it leaves the screen.
    private func offset(at date: Date, overflow: CGFloat) -> CGFloat {
        let travel = Double(overflow) / speed
        let cycle = (dwell * 2) + (travel * 2)
        guard cycle > 0 else { return 0 }

        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycle)

        switch phase {
        case ..<dwell:
            return 0
        case ..<(dwell + travel):
            return -overflow * CGFloat((phase - dwell) / travel)
        case ..<(dwell + travel + dwell):
            return -overflow
        default:
            let returning = (phase - dwell - travel - dwell) / travel
            return -overflow * CGFloat(1 - returning)
        }
    }
}

extension Font.Weight {

    /// SwiftUI and AppKit spell the same weights differently, and the
    /// measurement has to use the one the text is actually drawn with.
    var nsWeight: NSFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}
