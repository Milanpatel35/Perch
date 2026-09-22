import Foundation

/// "Tell me when CPU is over 90% for a minute."
///
/// `docs/FEATURES.md` §10's alert thresholds, and the two rules that make
/// them bearable: an alert fires **once** when it is crossed rather than
/// once per sample (TC-SYS-007), and it re-arms only after the value has
/// come back past a separate, lower line (TC-SYS-008). Without that second
/// line a value sitting on the threshold produces an alert every few
/// seconds for as long as it sits there.
public struct StatAlerts: Equatable, Sendable {

    /// What can be watched. Deliberately short: a monitor with twenty
    /// alertable fields is a monitor nobody configures.
    public enum Metric: String, Equatable, Sendable, Codable, CaseIterable {
        case cpu
        case memoryPressure
        case diskFree
        case temperature

        public var displayName: String {
            switch self {
            case .cpu: String(localized: "CPU")
            case .memoryPressure: String(localized: "Memory pressure")
            case .diskFree: String(localized: "Free disk space")
            case .temperature: String(localized: "Temperature")
            }
        }

        /// Whether the alert fires when the value goes *below* the
        /// threshold rather than above it. Free disk space is the only one,
        /// and getting it backwards would mean an alert every day except
        /// the one that mattered.
        public var firesWhenBelow: Bool { self == .diskFree }
    }

    public struct Rule: Equatable, Sendable, Codable, Identifiable, Hashable {
        public var id: String { metric.rawValue }

        public var metric: Metric
        public var isEnabled: Bool

        /// The line that fires the alert. Units are the metric's own: a
        /// fraction for CPU, bytes for disk, degrees for temperature.
        public var threshold: Double

        /// How long the value has to stay past the line before it counts.
        ///
        /// A build spiking the CPU for two seconds is not an event. Sixty
        /// seconds by default, which is what `docs/FEATURES.md` §10's own
        /// example asks for.
        public var sustainedFor: Duration

        public init(
            metric: Metric,
            isEnabled: Bool = false,
            threshold: Double,
            sustainedFor: Duration = .seconds(60)
        ) {
            self.metric = metric
            self.isEnabled = isEnabled
            self.threshold = threshold
            self.sustainedFor = sustainedFor
        }

        /// 10% clear of the line before the alert re-arms. Hysteresis, and
        /// the whole of TC-SYS-008.
        public var rearmThreshold: Double {
            metric.firesWhenBelow ? threshold * 1.1 : threshold * 0.9
        }
    }

    public struct Configuration: Equatable, Sendable, Codable {
        public var rules: [Rule] = Metric.allCases.map(Rule.default(for:))

        public init() {}
    }

    /// What an alert looks like when it fires.
    public struct Alert: Equatable, Sendable {
        public let metric: Metric
        public let value: Double
        public let threshold: Double
    }

    public private(set) var configuration: Configuration

    /// Per metric: when it first went past the line, and whether it has
    /// already fired for this crossing.
    private var crossedAt: [Metric: Date] = [:]
    private var fired: Set<Metric> = []

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public mutating func setConfiguration(_ configuration: Configuration) {
        self.configuration = configuration

        // A rule switched off must not fire the moment it is switched back
        // on because of a crossing nobody is watching any more.
        for rule in configuration.rules where !rule.isEnabled {
            crossedAt[rule.metric] = nil
            fired.remove(rule.metric)
        }
    }

    /// Feeds one sample in and returns anything that should reach the island.
    ///
    /// Called once per sample, which is at most every two seconds — so the
    /// "fires once, not once per sample" rule is enforced here and cannot be
    /// worked around by a caller sampling faster.
    public mutating func evaluate(_ snapshot: SystemSnapshot, now: Date) -> [Alert] {
        var alerts: [Alert] = []

        for rule in configuration.rules where rule.isEnabled {
            guard let value = value(of: rule.metric, in: snapshot) else {
                // Unreadable on this hardware. Not a crossing, and not a
                // recovery either — just nothing (TC-SYS-005).
                continue
            }

            let isPast =
                rule.metric.firesWhenBelow
                ? value < rule.threshold
                : value > rule.threshold

            guard isPast else {
                // Recovered past the re-arm line, so the next crossing can
                // fire again (TC-SYS-008).
                let hasRecovered =
                    rule.metric.firesWhenBelow
                    ? value > rule.rearmThreshold
                    : value < rule.rearmThreshold

                if hasRecovered {
                    crossedAt[rule.metric] = nil
                    fired.remove(rule.metric)
                }
                continue
            }

            let since = crossedAt[rule.metric] ?? now
            crossedAt[rule.metric] = since

            guard now.timeIntervalSince(since) >= rule.sustainedFor.seconds else { continue }
            guard !fired.contains(rule.metric) else { continue }

            fired.insert(rule.metric)
            alerts.append(Alert(metric: rule.metric, value: value, threshold: rule.threshold))
        }

        return alerts
    }

    public mutating func reset() {
        crossedAt.removeAll()
        fired.removeAll()
    }

    /// Pulls a metric out of a snapshot in the units its threshold is in.
    ///
    /// `nil` where the hardware does not report it, which is a first-class
    /// answer: an unreadable sensor must not read as zero and fire the
    /// "temperature is fine" case for ever.
    public func value(of metric: Metric, in snapshot: SystemSnapshot) -> Double? {
        switch metric {
        case .cpu:
            snapshot.cpu.total
        case .memoryPressure:
            switch snapshot.memory.pressure {
            case .normal: 0
            case .warning: 1
            case .critical: 2
            }
        case .diskFree:
            snapshot.disks.map { Double($0.free) }.min()
        case .temperature:
            snapshot.thermal?.temperature
        }
    }
}

extension StatAlerts.Rule {

    /// The defaults, and all of them are off.
    ///
    /// A monitor that starts alerting on the day it is installed is one
    /// people switch off entirely. The numbers are there so that switching
    /// one on is a single click rather than a decision about units.
    static func `default`(for metric: StatAlerts.Metric) -> Self {
        switch metric {
        case .cpu:
            Self(metric: .cpu, threshold: 0.9)
        case .memoryPressure:
            Self(metric: .memoryPressure, threshold: 0.5, sustainedFor: .seconds(30))
        case .diskFree:
            Self(
                metric: .diskFree, threshold: 10 * 1_024 * 1_024 * 1_024, sustainedFor: .seconds(0))
        case .temperature:
            Self(metric: .temperature, threshold: 95)
        }
    }
}
