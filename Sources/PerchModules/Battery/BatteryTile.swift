import PerchCore
import SwiftUI

/// The battery, on the island's home surface.
///
/// This is where the module actually lives for most people: the alerts are
/// rare by design, and this is the thing you open the island to glance at.
///
/// It exists only while the home surface is expanded, and it re-reads the
/// accessories when it appears. That is the whole of the module's sampling
/// story — no timer, no background work, and nothing at all while the island
/// is closed (`CLAUDE.md` §5.1).
struct BatteryTile: View {

    @ObservedObject var service: BatteryService

    var body: some View {
        Button {
            service.showStatus()
        } label: {
            HStack(spacing: 10) {
                macBattery
                lowestAccessory

                if !service.power.isPresent && service.roster.isEmpty {
                    Text("Nothing is reporting a battery level.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The one place accessories are re-read for display. `onAppear`
        // rather than a timer: the levels are only stale when nobody is
        // looking at them, and that is the point.
        .onAppear { service.refreshAccessories() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityHint(Text("Opens the full battery list"))
    }

    @ViewBuilder
    private var macBattery: some View {
        if service.power.isPresent {
            BatteryGauge(
                percentage: service.power.percentage,
                isCharging: service.power.isCharging
            )
            Text("\(service.power.percentage)%")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var lowestAccessory: some View {
        if let lowest = service.roster.lowest, let level = lowest.lowest {
            Image(systemName: lowest.kind.symbolName)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
            Text("\(level)%")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(level <= 20 ? .orange : .white.opacity(0.75))
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if service.power.isPresent {
            parts.append("This Mac, \(service.power.percentage) percent")
        }
        if let lowest = service.roster.lowest, let level = lowest.lowest {
            parts.append("\(lowest.name), \(level) percent")
        }
        return parts.isEmpty ? "No battery levels reported" : parts.joined(separator: ". ")
    }
}
