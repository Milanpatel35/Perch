import PerchCore
import SwiftUI

/// The monitor on the island's home surface: CPU, memory and network in one
/// row, and a click through to Activity Monitor.
///
/// Where the module lives by default. The gauge beside the notch is wider
/// than the notch, so it covers part of the menu bar all the time; this is
/// only there while the island is open.
///
/// **It owns a sampler, the same way the gauge does.** `onAppear` asks for
/// one and `onDisappear` hands it back, so closing the island stops sampling
/// (TC-SYS-009).
struct SystemStatsTile: View {

    @ObservedObject var service: SystemStatsService

    private static let shown: [GaugeKind] = [.cpu, .memory, .network]

    var body: some View {
        Button {
            service.openActivityMonitor()
        } label: {
            HStack(spacing: 14) {
                ForEach(Self.shown) { kind in
                    readout(kind)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { service.beginSampling(.expanded) }
        .onDisappear { service.endSampling(.expanded) }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens Activity Monitor"))
    }

    @ViewBuilder
    private func readout(_ kind: GaugeKind) -> some View {
        HStack(spacing: 5) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .accessibilityHidden(true)
            Text(kind.reading(from: service.snapshot) ?? "—")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .accessibilityLabel(
            Text("\(kind.displayName) \(kind.reading(from: service.snapshot) ?? "")"))
    }
}

public extension ModuleHost {

    /// The monitor's row on the home surface, or nothing when the module is
    /// off.
    @MainActor
    func systemStatsTile() -> AnyView? {
        guard let service = service(SystemStatsService.self), service.isActive else { return nil }
        return AnyView(SystemStatsTile(service: service))
    }
}
