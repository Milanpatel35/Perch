import Foundation
import PerchCore

/// The system monitor, on the island.
///
/// **It carries no data.** The snapshot and the history live in the service,
/// and the view reads them — because the activity is a value that the queue
/// copies, and copying sixty points of history on every sample is how a
/// monitor becomes the thing it is monitoring (TC-SYS-015).
struct SystemStatsActivity: IslandActivity {

    static let identifier = ActivityID("systemstats.gauge")

    let id = Self.identifier
    let source: ModuleID = .systemStats

    /// Ambient, and the lowest thing on the island. A gauge is something you
    /// glance at; it must lose to everything else, every time.
    let priority: ActivityPriority = .ambient

    /// Held until withdrawn. The gauge is a state you switched on, not an
    /// event that happened.
    let timeToLive: Duration? = nil

    /// Which two readouts the micro-gauge shows
    /// (`docs/FEATURES.md` §10).
    let gauges: [GaugeKind]
}

/// A threshold that has been crossed.
///
/// Separate from the gauge because it is an event rather than a state, and
/// because it has to be able to interrupt while the gauge never does.
struct SystemAlertActivity: IslandActivity {

    var id: ActivityID { ActivityID("systemstats.alert.\(alert.metric.rawValue)") }

    let source: ModuleID = .systemStats

    /// The one thing in this module that interrupts. A disk about to fill up
    /// is worth taking the island from an album sleeve for.
    let priority: ActivityPriority = .systemAlert

    let timeToLive: Duration? = .seconds(10)

    let alert: StatAlerts.Alert
}

/// The two readouts the collapsed island can show.
///
/// "Pick any two of CPU / RAM / net / temp" — `docs/FEATURES.md` §10. Two,
/// because the space beside a notch fits two glyphs and a number each, and a
/// third would mean shrinking the type past reading size.
enum GaugeKind: String, Equatable, Sendable, Codable, CaseIterable, Identifiable {
    case cpu
    case memory
    case network
    case temperature

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cpu: String(localized: "CPU")
        case .memory: String(localized: "Memory")
        case .network: String(localized: "Network")
        case .temperature: String(localized: "Temperature")
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "arrow.up.arrow.down"
        case .temperature: "thermometer.medium"
        }
    }

    /// What the gauge shows, already formatted. `nil` where the hardware
    /// does not report it, which draws nothing rather than a dash
    /// (TC-SYS-005).
    func reading(from snapshot: SystemSnapshot) -> String? {
        switch self {
        case .cpu:
            "\(Int(snapshot.cpu.total * 100))%"
        case .memory:
            "\(Int(snapshot.memory.usedFraction * 100))%"
        case .network:
            snapshot.network.downRate.map { rate in
                "\(ByteFormat.rate(rate))"
            }
        case .temperature:
            snapshot.thermal?.temperature.map { "\(Int($0))°" }
        }
    }

    /// 0–1, for the bar behind the number. `nil` for a rate, which has no
    /// ceiling to be a fraction of.
    func fraction(from snapshot: SystemSnapshot) -> Double? {
        switch self {
        case .cpu: snapshot.cpu.total
        case .memory: snapshot.memory.usedFraction
        case .network: nil
        case .temperature: snapshot.thermal?.temperature.map { min(1, $0 / 100) }
        }
    }
}

/// Byte formatting, in one place so the gauge, the grid and the settings
/// pane cannot disagree about what "MB" means.
enum ByteFormat {

    static func size(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB, .useTB]
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Bytes per second, short enough to sit beside a notch.
    static func rate(_ bytesPerSecond: Double) -> String {
        let megabytes = bytesPerSecond / 1_000_000
        if megabytes >= 1 {
            return String(format: "%.1f MB/s", megabytes)
        }
        return String(format: "%.0f KB/s", bytesPerSecond / 1_000)
    }
}
