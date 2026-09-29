import PerchCore
import SwiftUI

extension SystemStatsActivity: IslandActivityPresenting {

    var peekSize: CGSize { CGSize(width: 320, height: 34) }
    var expandedSize: CGSize { CGSize(width: 400, height: 260) }

    func peekView() -> AnyView {
        AnyView(MicroGauge(gauges: gauges))
    }

    func expandedView() -> AnyView {
        AnyView(StatGrid())
    }
}

/// The two-glyph readout beside the notch.
///
/// **This view owns a sampler.** `onAppear` asks for one and `onDisappear`
/// gives it back, which is the whole of TC-SYS-009: the timer cannot outlive
/// the thing that needs it, because the thing that needs it is what asked.
private struct MicroGauge: View {

    let gauges: [GaugeKind]

    @EnvironmentObject private var modules: ModuleHost
    @Environment(\.notchMetrics) private var metrics

    private var service: SystemStatsService? { modules.service(SystemStatsService.self) }

    var body: some View {
        HStack(spacing: 0) {
            readout(gauges.first)
                .frame(maxWidth: 80, alignment: .leading)
                .padding(.leading, 12)

            Spacer(minLength: metrics.collapsedSize.width)

            readout(gauges.dropFirst().first)
                .frame(maxWidth: 80, alignment: .trailing)
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { service?.beginSampling(.microGauge) }
        .onDisappear { service?.endSampling(.microGauge) }
    }

    @ViewBuilder
    private func readout(_ kind: GaugeKind?) -> some View {
        if let kind, let snapshot = service?.snapshot, let text = kind.reading(from: snapshot) {
            HStack(spacing: 5) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))

                Text(text)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(kind.displayName) \(text)"))
        } else {
            Color.clear.frame(width: 0)
        }
    }
}

/// The opened monitor: a compact grid of sparklines, and a way through to
/// Activity Monitor.
///
/// This view owns a sampler too, at the higher demand. Both can be up at
/// once during the expand animation, which is why the service counts
/// demands rather than holding a flag.
private struct StatGrid: View {

    @EnvironmentObject private var modules: ModuleHost

    private var service: SystemStatsService? { modules.service(SystemStatsService.self) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let service {
                grid(for: service)
            }

            Spacer(minLength: 0)

            HStack {
                if let uptime = service?.snapshot.uptime {
                    Text("Up \(Self.uptimeText(uptime))")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer(minLength: 0)

                Button("Activity Monitor") { service?.openActivityMonitor() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { service?.beginSampling(.expanded) }
        .onDisappear { service?.endSampling(.expanded) }
    }

    @ViewBuilder
    private func grid(for service: SystemStatsService) -> some View {
        let snapshot = service.snapshot

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            tile(
                Text("CPU"),
                value: "\(Int(snapshot.cpu.total * 100))%",
                detail: snapshot.cpu.topProcess?.name,
                graph: Graph(history: service.cpuHistory, ceiling: 1),
                tint: .green
            )

            tile(
                Text("Memory"),
                value: ByteFormat.size(snapshot.memory.used),
                detail: snapshot.memory.pressure.rawValue,
                graph: Graph(history: service.memoryHistory, ceiling: 1),
                tint: tint(for: snapshot.memory.pressure)
            )

            tile(
                Text("Network"),
                value: snapshot.network.downRate.map(ByteFormat.rate) ?? "—",
                detail: snapshot.network.upRate.map { "↑ \(ByteFormat.rate($0))" },
                graph: Graph(
                    history: service.networkHistory,
                    ceiling: service.networkHistory.ceiling(minimum: 1_000)
                ),
                tint: .blue
            )

            // TC-SYS-005 and TC-SYS-006: unreadable means no tile, never a
            // tile of zeroes.
            if let gpu = snapshot.gpu, let utilisation = gpu.utilisation {
                tile(
                    Text("GPU"),
                    value: "\(Int(utilisation * 100))%",
                    detail: gpu.vramUsed.map(ByteFormat.size),
                    tint: .purple
                )
            } else if let disk = snapshot.disks.first {
                tile(
                    Text(verbatim: disk.name),
                    value: "\(ByteFormat.size(disk.free)) free",
                    detail: String(localized: "of \(ByteFormat.size(disk.total))"),
                    tint: .orange
                )
            }
        }
    }

    private func tint(for pressure: SystemSnapshot.Memory.Pressure) -> Color {
        switch pressure {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }

    /// The title is a `Text` rather than a key: three of these are UI copy
    /// that must be localisable, and the fourth is a volume name, which is
    /// somebody's own words and must not be run through a string table.
    /// A history and the ceiling it is drawn against always travel
    /// together — a ceiling without a history means nothing, and a history
    /// without one cannot be drawn.
    private struct Graph {
        let history: StatHistory
        let ceiling: Double
    }

    private func tile(
        _ title: Text,
        value: String,
        detail: String? = nil,
        graph: Graph? = nil,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            title
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))

            Text(value)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)

            if let graph {
                Sparkline(history: graph.history, ceiling: graph.ceiling, tint: tint)
                    .frame(height: 20)
            } else if let detail {
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .frame(height: 20, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private static func uptimeText(_ uptime: Duration) -> String {
        let hours = Int(uptime.seconds) / 3_600
        if hours >= 24 { return "\(hours / 24)d" }
        return hours >= 1 ? "\(hours)h" : "\(Int(uptime.seconds) / 60)m"
    }
}

/// Sixty points, drawn as a filled line.
///
/// A flat line at zero draws as a flat line along the bottom, not as a blank
/// box — `StatHistory.ceiling` never returns zero, which is what makes that
/// true (TC-SYS-014).
private struct Sparkline: View {

    let history: StatHistory
    let ceiling: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let points = self.points(in: geometry.size)

            ZStack {
                if points.count > 1 {
                    path(points, in: geometry.size)
                        .fill(tint.opacity(0.18))

                    line(points)
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                } else {
                    // One point, or none. A rule along the bottom says "no
                    // history yet" without looking broken.
                    Rectangle()
                        .fill(tint.opacity(0.25))
                        .frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let values = history.values
        guard values.count > 1 else { return values.isEmpty ? [] : [.zero] }

        let step = size.width / Double(values.count - 1)
        return values.enumerated().map { index, value in
            let normalised = min(1, max(0, value / ceiling))
            return CGPoint(x: Double(index) * step, y: size.height * (1 - normalised))
        }
    }

    private func line(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        return path
    }

    private func path(_ points: [CGPoint], in size: CGSize) -> Path {
        var path = line(points)
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Alerts

extension SystemAlertActivity: IslandActivityPresenting {

    var peekSize: CGSize { CGSize(width: 320, height: 34) }
    var expandedSize: CGSize { CGSize(width: 340, height: 120) }

    func peekView() -> AnyView {
        AnyView(
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text(headline)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }

    func expandedView() -> AnyView {
        AnyView(
            VStack(spacing: 8) {
                Text(headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }

    var headline: String {
        alert.metric.displayName
    }

    var detail: String {
        switch alert.metric {
        case .cpu:
            String(localized: "\(Int(alert.value * 100))% and staying there.")
        case .memoryPressure:
            String(localized: "Memory pressure is high.")
        case .diskFree:
            String(localized: "\(ByteFormat.size(UInt64(max(0, alert.value)))) left.")
        case .temperature:
            String(localized: "\(Int(alert.value))°C.")
        }
    }
}
