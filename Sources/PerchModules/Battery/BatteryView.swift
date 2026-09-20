import PerchCore
import SwiftUI

// MARK: - The announcement

extension BatteryActivity: IslandActivityPresenting {

    var peekSize: CGSize { CGSize(width: 320, height: 34) }
    var expandedSize: CGSize { CGSize(width: 380, height: expandedHeight) }

    func peekView() -> AnyView {
        AnyView(BatteryPeek(reason: reason, power: power))
    }

    /// Hovering an alert opens into the full list. The thing you want after
    /// "battery low" is "how low, and what else is flat".
    func expandedView() -> AnyView {
        AnyView(BatteryStatusList(power: power, accessories: accessories))
    }

    private var expandedHeight: CGFloat {
        BatteryStatusList.height(macBattery: power.isPresent, accessories: accessories.count)
    }
}

private struct BatteryPeek: View {

    let reason: BatteryActivity.Reason
    let power: PowerSnapshot

    @Environment(\.notchMetrics) private var metrics

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .padding(.leading, 14)

            Spacer(minLength: metrics.collapsedSize.width)

            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(message))
    }

    private var symbol: String {
        switch reason {
        case .pluggedIn: "powerplug.fill"
        case .unplugged: "powerplug"
        case .low: "exclamationmark.triangle.fill"
        case .charged: "battery.100.bolt"
        }
    }

    private var tint: Color {
        switch reason {
        case .low: .orange
        case .charged, .pluggedIn: .green
        case .unplugged: .white
        }
    }

    private var message: String {
        switch reason {
        case .pluggedIn(let level): "Charging · \(level)%"
        case .unplugged(let level): "On battery · \(level)%"
        case .low(let level): "Battery low · \(level)%"
        case .charged: "Fully charged"
        }
    }
}

// MARK: - The readable state

extension BatteryStatusActivity: IslandActivityPresenting {

    var peekSize: CGSize { CGSize(width: 300, height: 34) }

    var expandedSize: CGSize {
        CGSize(
            width: 380,
            height: BatteryStatusList.height(
                macBattery: power.isPresent,
                accessories: accessories.count
            )
        )
    }

    func peekView() -> AnyView {
        AnyView(
            Text("Battery")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }

    func expandedView() -> AnyView {
        AnyView(BatteryStatusList(power: power, accessories: accessories))
    }
}

/// The Mac, then everything connected to it.
struct BatteryStatusList: View {

    let power: PowerSnapshot
    let accessories: [AccessoryBattery]

    /// Sized from the content rather than scrolled. Four accessories is
    /// already an unusual number; a scroll view inside the notch is worse
    /// than a list that is honestly short.
    ///
    /// `nonisolated` because the activities ask for it while sizing
    /// themselves, which is not main-actor work — it is arithmetic.
    nonisolated static func height(macBattery: Bool, accessories: Int) -> CGFloat {
        let rows = (macBattery ? 1 : 0) + max(accessories, 1)
        return 46 + (CGFloat(rows) * 34)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Battery")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))

            if power.isPresent {
                MacBatteryRow(power: power)
            }

            if accessories.isEmpty {
                Text(
                    power.isPresent
                        ? "Nothing else is reporting a level."
                        : "This Mac has no battery, and nothing connected is reporting one."
                )
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(accessories) { accessory in
                    AccessoryRow(accessory: accessory)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Battery"))
    }
}

private struct MacBatteryRow: View {

    let power: PowerSnapshot

    var body: some View {
        HStack(spacing: 8) {
            BatteryGauge(percentage: power.percentage, isCharging: power.isCharging)

            Text("This Mac")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))

            Spacer(minLength: 8)

            if let remaining = power.remainingDescription {
                Text(remaining)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text("\(power.percentage)%")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("This Mac, \(power.percentage) percent"))
    }
}

private struct AccessoryRow: View {

    let accessory: AccessoryBattery

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: accessory.kind.symbolName)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 22)

            Text(accessory.name)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(accessory.levelSummary)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(accessory.isLow ? .orange : .white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(accessory.name), \(accessory.levelSummary)"))
    }
}

/// The battery glyph, drawn rather than taken from SF Symbols so that the
/// fill tracks the real level instead of snapping to the nearest 25%.
struct BatteryGauge: View {

    let percentage: Int
    var isCharging: Bool = false

    private var fill: Color {
        if isCharging { return .green }
        if percentage <= 10 { return .red }
        if percentage <= 20 { return .orange }
        return .white
    }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
                    .frame(width: 22, height: 11)

                RoundedRectangle(cornerRadius: 2)
                    .fill(fill)
                    .frame(width: max(2, 20 * CGFloat(percentage) / 100), height: 8)
                    .padding(.leading, 1)

                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.leading, 7)
                }
            }

            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.45))
                .frame(width: 2, height: 4)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Presentation helpers

extension AccessoryBattery {

    /// Orange below 20%, the same line the Mac's own gauge uses.
    var isLow: Bool { (lowest ?? 100) <= 20 }
}

extension AccessoryBattery.Kind {

    var symbolName: String {
        switch self {
        case .earbuds: "airpods.gen3"
        case .headphones: "headphones"
        case .mouse: "magicmouse"
        case .keyboard: "keyboard"
        case .trackpad: "magictrackpad"
        case .gameController: "gamecontroller"
        case .other: "dot.radiowaves.left.and.right"
        }
    }
}

extension PowerSnapshot {

    /// "2h 40m left", or nothing at all while macOS works it out — which it
    /// is for a minute or two after every change, so the absent case is the
    /// common one rather than the edge.
    var remainingDescription: String? {
        guard let timeRemaining else { return nil }

        let minutes = Int(timeRemaining.seconds / 60)
        guard minutes > 0 else { return nil }

        let hours = minutes / 60
        let remainder = minutes % 60
        let clock = hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"

        return isPluggedIn ? "\(clock) to full" : "\(clock) left"
    }
}
