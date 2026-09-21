import PerchCore
import SwiftUI

extension HUDActivity: IslandActivityPresenting {

    /// Narrow. A HUD is a glance, and the stock one it replaces is about this
    /// wide — matching it is the point.
    var peekSize: CGSize { CGSize(width: 280, height: 34) }

    /// Never opened, because `isExpandable` is false: your hand is on the
    /// keyboard, not the trackpad. The size is here because the protocol asks
    /// for it.
    var expandedSize: CGSize { peekSize }

    func peekView() -> AnyView {
        AnyView(HUDPeek(reading: reading))
    }

    func expandedView() -> AnyView {
        AnyView(HUDPeek(reading: reading))
    }
}

private struct HUDPeek: View {

    let reading: HUDReading

    @Environment(\.notchMetrics) private var metrics

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                // Fixed width so the glyph does not shift sideways as it
                // changes shape — the speaker symbol is four different widths
                // across its four levels, and a HUD that jiggles while you
                // hold a key is worse than no HUD.
                .frame(width: 22)
                .padding(.leading, 12)

            Spacer(minLength: metrics.collapsedSize.width)

            trailing
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    @ViewBuilder
    private var trailing: some View {
        if reading.kind.showsLevel, let level = reading.level {
            HUDLevelBar(level: level, isMuted: reading.isMuted)
        } else {
            VStack(alignment: .trailing, spacing: 0) {
                Text(reading.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                if let detail = reading.detail {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .lineLimit(1)
        }
    }

    private var symbol: String {
        switch reading.kind {
        case .volume:
            if reading.isMuted { return "speaker.slash.fill" }
            switch reading.level ?? 0 {
            case ..<0.01: return "speaker.fill"
            case ..<0.34: return "speaker.wave.1.fill"
            case ..<0.67: return "speaker.wave.2.fill"
            default: return "speaker.wave.3.fill"
            }
        case .brightness:
            return (reading.level ?? 0) < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .power:
            return "powerplug.fill"
        case .bluetooth:
            return "dot.radiowaves.left.and.right"
        case .focus:
            return "moon.fill"
        case .capture:
            return "camera.fill"
        }
    }

    private var accessibilityLabel: String {
        if let percentage = reading.percentage, reading.kind.showsLevel {
            return reading.isMuted
                ? "\(reading.kind.displayName) muted"
                : "\(reading.kind.displayName) \(percentage) percent"
        }
        return [reading.title, reading.detail].compactMap { $0 }.joined(separator: ", ")
    }
}

/// The level bar, drawn rather than taken from a `ProgressView` so the fill
/// tracks the value exactly and the track stays visible on black.
struct HUDLevelBar: View {

    let level: Double
    var isMuted: Bool = false

    private let width: CGFloat = 92
    private let height: CGFloat = 5

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: width, height: height)

            Capsule()
                .fill(isMuted ? Color.white.opacity(0.35) : Color.white)
                .frame(width: max(0, width * level), height: height)
        }
        .frame(width: width, height: height)
        // No explicit animation: the island's own transition token carries
        // this, which is what keeps every module moving identically
        // (`CLAUDE.md` §9).
        .accessibilityHidden(true)
    }
}
