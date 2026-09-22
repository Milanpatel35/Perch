import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § SYS for the alert rules — TC-SYS-007 and
/// TC-SYS-008, the two that decide whether thresholds are usable or whether
/// people switch the whole module off.
final class StatAlertsTests: XCTestCase {

    private let noon = Date(timeIntervalSinceReferenceDate: 12 * 3_600)

    private func alerts(cpuThreshold: Double = 0.9, sustained: Double = 60) -> StatAlerts {
        var configuration = StatAlerts.Configuration()
        configuration.rules = [
            StatAlerts.Rule(
                metric: .cpu,
                isEnabled: true,
                threshold: cpuThreshold,
                sustainedFor: .seconds(sustained)
            )
        ]
        return StatAlerts(configuration: configuration)
    }

    private func snapshot(cpu: Double) -> SystemSnapshot {
        var snapshot = SystemSnapshot()
        snapshot.cpu = SystemSnapshot.CPU(total: cpu)
        return snapshot
    }

    // MARK: - TC-SYS-007

    func test_TC_SYS_007_firesOnceNotOncePerSample() {
        var alerts = alerts()

        // Crossed, but not yet for long enough.
        XCTAssertTrue(alerts.evaluate(snapshot(cpu: 0.95), now: noon).isEmpty)

        let fired = alerts.evaluate(
            snapshot(cpu: 0.95),
            now: noon.addingTimeInterval(60)
        )
        XCTAssertEqual(fired.count, 1)
        XCTAssertEqual(fired.first?.metric, .cpu)

        // Thirty more samples at the same load. Still one alert.
        for second in 62...120 {
            let more = alerts.evaluate(
                snapshot(cpu: 0.95),
                now: noon.addingTimeInterval(Double(second))
            )
            XCTAssertTrue(more.isEmpty, "fired again at +\(second)s")
        }
    }

    /// A build spiking the CPU for two seconds is not an event.
    func test_TC_SYS_007_aBriefSpikeNeverFires() {
        var alerts = alerts()

        XCTAssertTrue(alerts.evaluate(snapshot(cpu: 0.99), now: noon).isEmpty)
        XCTAssertTrue(
            alerts.evaluate(snapshot(cpu: 0.99), now: noon.addingTimeInterval(2)).isEmpty
        )
        XCTAssertTrue(
            alerts.evaluate(snapshot(cpu: 0.10), now: noon.addingTimeInterval(4)).isEmpty
        )
    }

    // MARK: - TC-SYS-008

    func test_TC_SYS_008_crossingTwiceFiresTwice() {
        var alerts = alerts()

        _ = alerts.evaluate(snapshot(cpu: 0.95), now: noon)
        XCTAssertEqual(
            alerts.evaluate(snapshot(cpu: 0.95), now: noon.addingTimeInterval(60)).count,
            1
        )

        // Recovered well clear of the line.
        XCTAssertTrue(
            alerts.evaluate(snapshot(cpu: 0.20), now: noon.addingTimeInterval(120)).isEmpty
        )

        // And back up again.
        _ = alerts.evaluate(snapshot(cpu: 0.95), now: noon.addingTimeInterval(180))
        XCTAssertEqual(
            alerts.evaluate(snapshot(cpu: 0.95), now: noon.addingTimeInterval(240)).count,
            1
        )
    }

    /// The whole of the hysteresis rule: a value sitting on the line does
    /// not produce an alert every minute for as long as it sits there.
    func test_TC_SYS_008_sittingOnTheLineDoesNotFlap() {
        var alerts = alerts()

        _ = alerts.evaluate(snapshot(cpu: 0.95), now: noon)
        _ = alerts.evaluate(snapshot(cpu: 0.95), now: noon.addingTimeInterval(60))

        // Dipping just under the threshold but not past the re-arm line.
        var time = 120.0
        for load in [0.89, 0.95, 0.88, 0.94, 0.89, 0.96] {
            let fired = alerts.evaluate(
                snapshot(cpu: load),
                now: noon.addingTimeInterval(time)
            )
            XCTAssertTrue(fired.isEmpty, "flapped at \(load)")
            time += 60
        }
    }

    func test_TC_SYS_008_theRearmLineIsTenPercentClear() {
        let rule = StatAlerts.Rule(metric: .cpu, threshold: 0.9)
        XCTAssertEqual(rule.rearmThreshold, 0.81, accuracy: 0.0001)
    }

    /// Free disk space is the one metric that fires when it goes *down*, so
    /// its re-arm line has to be above the threshold rather than below it.
    func test_TC_SYS_008_theDiskRuleRunsTheOtherWayRound() {
        XCTAssertTrue(StatAlerts.Metric.diskFree.firesWhenBelow)
        XCTAssertFalse(StatAlerts.Metric.cpu.firesWhenBelow)

        let rule = StatAlerts.Rule(metric: .diskFree, threshold: 100)
        XCTAssertGreaterThan(rule.rearmThreshold, rule.threshold)
    }

    func test_theDiskRuleFiresWhenSpaceRunsOut() {
        var configuration = StatAlerts.Configuration()
        configuration.rules = [
            StatAlerts.Rule(
                metric: .diskFree,
                isEnabled: true,
                threshold: 10_000,
                sustainedFor: .seconds(0)
            )
        ]
        var alerts = StatAlerts(configuration: configuration)

        var snapshot = SystemSnapshot()
        snapshot.disks = [
            SystemSnapshot.Disk(id: "a", name: "Macintosh HD", free: 5_000, total: 100_000)
        ]

        XCTAssertEqual(alerts.evaluate(snapshot, now: noon).count, 1)
    }

    // MARK: - TC-SYS-005

    /// An unreadable sensor must not read as zero. A temperature rule on a
    /// Mac that reports no temperature is not "0°C, everything is fine".
    func test_TC_SYS_005_anUnreadableMetricNeverFiresAndNeverRecovers() {
        var configuration = StatAlerts.Configuration()
        configuration.rules = [
            StatAlerts.Rule(
                metric: .temperature,
                isEnabled: true,
                threshold: 95,
                sustainedFor: .seconds(0)
            )
        ]
        var alerts = StatAlerts(configuration: configuration)

        // No thermal reading at all.
        XCTAssertTrue(alerts.evaluate(SystemSnapshot(), now: noon).isEmpty)
        XCTAssertNil(alerts.value(of: .temperature, in: SystemSnapshot()))
    }

    // MARK: - Configuration

    func test_everyRuleIsOffByDefault() {
        let configuration = StatAlerts.Configuration()

        XCTAssertEqual(configuration.rules.count, StatAlerts.Metric.allCases.count)
        for rule in configuration.rules {
            XCTAssertFalse(rule.isEnabled, "\(rule.metric) is on by default")
        }
    }

    func test_aDisabledRuleForgetsItsCrossing() {
        var alerts = alerts()
        _ = alerts.evaluate(snapshot(cpu: 0.95), now: noon)

        var disabled = StatAlerts.Configuration()
        disabled.rules = [StatAlerts.Rule(metric: .cpu, isEnabled: false, threshold: 0.9)]
        alerts.setConfiguration(disabled)

        // Switched back on, it starts again rather than firing for a
        // crossing nobody was watching.
        var reenabled = StatAlerts.Configuration()
        reenabled.rules = [
            StatAlerts.Rule(
                metric: .cpu,
                isEnabled: true,
                threshold: 0.9,
                sustainedFor: .seconds(60)
            )
        ]
        alerts.setConfiguration(reenabled)

        XCTAssertTrue(
            alerts.evaluate(snapshot(cpu: 0.95), now: noon.addingTimeInterval(120)).isEmpty
        )
    }
}
