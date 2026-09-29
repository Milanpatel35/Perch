import AppKit
import Combine
import Defaults
import PerchCore
import SwiftUI

/// Module 10 — the system monitor.
///
/// **The sampler's lifetime belongs to the view, not to this.** That is the
/// rule `CLAUDE.md` §4 singles the module out for and TC-SYS-009 enforces:
/// collapsed with no gauge showing means no timer exists — not a slower
/// timer, none. A system monitor is the easiest way in the whole app to
/// violate §5.1, and the only defence that survives a year of changes is
/// making the timer impossible to leave running rather than remembering to
/// stop it.
///
/// The mechanism: views call `beginSampling` when they appear and
/// `endSampling` when they go, the demands are counted, and the sampler
/// exists exactly while the count is above zero at the highest demand asked
/// for. `SamplerPolicy` decides the interval; this owns nothing but the
/// counting.
@MainActor
final class SystemStatsService: ObservableObject, PerchModule {

    static let moduleID: ModuleID = .systemStats

    @Published private(set) var snapshot = SystemSnapshot()
    @Published private(set) var alerts = StatAlerts()

    /// Sixty points each, for the sparklines. Kept here rather than in the
    /// activity: the activity is a value the queue copies, and copying this
    /// on every sample is how a monitor becomes the problem (TC-SYS-015).
    @Published private(set) var cpuHistory = StatHistory()
    @Published private(set) var memoryHistory = StatHistory()
    @Published private(set) var networkHistory = StatHistory()

    @Published private(set) var gauges: [GaugeKind] = [.cpu, .memory]

    private(set) var isActive = false

    private let island: IslandController
    private let reader = SystemReader()

    /// The one sampler, and it exists only while something is drawing.
    private var sampler: Task<Void, Never>?

    /// How many views are asking, at what demand. A count rather than a
    /// flag, because the micro-gauge and the expanded grid can both be up
    /// during the expand animation, and the one that disappears first must
    /// not stop the other's sampler.
    private var demands: [SamplerPolicy.Demand: Int] = [:]

    private let now: @MainActor () -> Date

    init(island: IslandController, now: @escaping @MainActor () -> Date = { Date() }) {
        self.island = island
        self.now = now
        self.gauges = Defaults[.systemGauges]
        self.alerts = StatAlerts(configuration: Defaults[.statAlerts])
    }

    // MARK: - PerchModule

    func activate() {
        guard !isActive else { return }
        isActive = true

        // No sampler starts here, and that is the whole design. Switching
        // the module on puts a gauge on the island; the gauge's *view*
        // appearing is what starts sampling (TC-SYS-009).
        island.submit(SystemStatsActivity(gauges: gauges))
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        stopSampling()
        demands.removeAll()

        alerts.reset()
        cpuHistory.clear()
        memoryHistory.clear()
        networkHistory.clear()
        snapshot = SystemSnapshot()

        island.withdrawAll(from: .systemStats)
    }

    // MARK: - The sampler, owned by the view

    /// Called by a view when it appears. Every call must be matched by
    /// `endSampling`, which `onDisappear` does.
    func beginSampling(_ demand: SamplerPolicy.Demand) {
        guard isActive, demand != .none else { return }

        demands[demand, default: 0] += 1
        reconcile()
    }

    /// Called by a view when it goes away.
    func endSampling(_ demand: SamplerPolicy.Demand) {
        guard let count = demands[demand], count > 0 else { return }

        demands[demand] = count - 1
        if demands[demand] == 0 {
            demands[demand] = nil
        }
        reconcile()
    }

    /// The current demand: the most expensive thing anybody is drawing.
    var demand: SamplerPolicy.Demand {
        if demands[.expanded, default: 0] > 0 { return .expanded }
        if demands[.microGauge, default: 0] > 0 { return .microGauge }
        return .none
    }

    /// Whether a sampler exists. Read by TC-SYS-009, which asserts it is
    /// false whenever nothing is drawing.
    var isSampling: Bool { sampler != nil }

    /// Starts, restarts or stops the sampler so that it matches the demand.
    ///
    /// Restarting on a demand change rather than adjusting an interval: a
    /// `Task` has no interval to adjust, and an actual timer would be a
    /// thing that could be left running.
    private func reconcile() {
        guard let interval = SamplerPolicy.interval(for: demand) else {
            stopSampling()
            return
        }

        // Already sampling at this interval. Nothing to do — and in
        // particular, no second sampler.
        if let existing = currentInterval, existing == interval, sampler != nil { return }

        stopSampling()
        currentInterval = interval

        // One reading immediately, so the gauge is not blank for two
        // seconds while it waits for the first tick.
        sample()

        sampler = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.sample()
            }
        }
    }

    private var currentInterval: Duration?

    private func stopSampling() {
        sampler?.cancel()
        sampler = nil
        currentInterval = nil

        // Rate baselines go with it. Restarting must not report a rate
        // averaged over the minutes nobody was watching.
        reader.reset()
    }

    private func sample() {
        guard isActive else { return }

        let reading = reader.read()
        snapshot = reading

        cpuHistory.record(reading.cpu.total)
        memoryHistory.record(reading.memory.usedFraction)
        networkHistory.record(reading.network.downRate ?? 0)

        for alert in alerts.evaluate(reading, now: now()) {
            island.submit(SystemAlertActivity(alert: alert))
        }
    }

    /// Set by the public-IP readout, which is the only thing that writes
    /// to the snapshot from outside `sample` (`CLAUDE.md` §5.2).
    func setPublicIP(_ address: String?) {
        snapshot.network.publicIP = address
    }

    func clearPublicIP() {
        snapshot.network.publicIP = nil
    }

    // MARK: - Configuration

    /// Exactly two. The space beside a notch fits two glyphs and a number
    /// each; a third means shrinking the type past reading size.
    func setGauges(_ gauges: [GaugeKind]) {
        self.gauges = Array(gauges.prefix(2))
        Defaults[.systemGauges] = self.gauges

        guard isActive else { return }
        island.submit(SystemStatsActivity(gauges: self.gauges))
    }

    func setAlertConfiguration(_ configuration: StatAlerts.Configuration) {
        alerts.setConfiguration(configuration)
        Defaults[.statAlerts] = configuration
    }

    /// `docs/FEATURES.md` §10's last row. Opening the real thing is a better
    /// answer than growing a process list nobody asked for.
    func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
        island.send(.collapseRequested)
    }
}
