import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § BAT for the accessory half — what is listed, in
/// what order, and what happens to something that walks out of range.
final class AccessoryRosterTests: XCTestCase {

    private func airPods(
        left: Int? = 72,
        right: Int? = 68,
        caseLevel: Int? = 90
    ) -> AccessoryBattery {
        AccessoryBattery(
            id: "00-11-22-33-44-55",
            name: "AirPods Pro",
            kind: .earbuds,
            levels: .init(left: left, right: right, caseLevel: caseLevel)
        )
    }

    private func mouse(_ level: Int = 45) -> AccessoryBattery {
        AccessoryBattery(
            id: "aa-bb-cc-dd-ee-ff",
            name: "Magic Mouse",
            kind: .mouse,
            levels: .init(single: level)
        )
    }

    private func keyboard(_ level: Int = 60) -> AccessoryBattery {
        AccessoryBattery(
            id: "11-22-33-44-55-66",
            name: "Magic Keyboard",
            kind: .keyboard,
            levels: .init(single: level)
        )
    }

    // MARK: - TC-BAT-003

    func test_TC_BAT_003_airPodsReportBothBudsAndTheCase() {
        var roster = AccessoryRoster()
        let changes = roster.replace(with: [airPods()])

        XCTAssertEqual(changes.connected.count, 1)
        XCTAssertEqual(roster.count, 1)

        let levels = roster.accessory("00-11-22-33-44-55")?.levels
        XCTAssertEqual(levels?.left, 72)
        XCTAssertEqual(levels?.right, 68)
        XCTAssertEqual(levels?.caseLevel, 90)
        XCTAssertEqual(levels?.all.count, 3)
        XCTAssertTrue(levels?.isSplit == true)
    }

    /// The case being nearly full is no comfort when a bud is nearly empty,
    /// so the number the island leads with is the lowest one.
    func test_TC_BAT_003_theLevelShownIsTheLowestOfTheThree() {
        var roster = AccessoryRoster()
        roster.replace(with: [airPods(left: 72, right: 4, caseLevel: 90)])

        XCTAssertEqual(roster.accessory("00-11-22-33-44-55")?.lowest, 4)
    }

    func test_TC_BAT_003_aDeviceReportingOneLevelIsNotSplit() {
        var roster = AccessoryRoster()
        roster.replace(with: [mouse(45)])

        let levels = roster.accessory("aa-bb-cc-dd-ee-ff")?.levels
        XCTAssertEqual(levels?.single, 45)
        XCTAssertEqual(levels?.lowest, 45)
        XCTAssertFalse(levels?.isSplit == true)
    }

    // MARK: - TC-BAT-004

    func test_TC_BAT_004_aDisconnectedAccessoryLeavesNoStaleLevel() {
        var roster = AccessoryRoster()
        roster.replace(with: [airPods(), mouse()])
        XCTAssertEqual(roster.count, 2)

        // The AirPods went back in the case: the next scan does not see them.
        let changes = roster.replace(with: [mouse()])

        XCTAssertEqual(changes.disconnected.map(\.id), ["00-11-22-33-44-55"])
        XCTAssertNil(roster.accessory("00-11-22-33-44-55"))
        XCTAssertEqual(roster.count, 1)
    }

    func test_TC_BAT_004_reconnectingDoesNotProduceTwoEntries() {
        var roster = AccessoryRoster()
        roster.replace(with: [airPods()])
        roster.replace(with: [])
        let changes = roster.replace(with: [airPods(left: 40, right: 38)])

        XCTAssertEqual(roster.count, 1)
        XCTAssertEqual(changes.connected.count, 1)
        XCTAssertEqual(roster.accessory("00-11-22-33-44-55")?.levels.left, 40)
    }

    func test_aLevelChangeIsNeitherAConnectionNorADisconnection() {
        var roster = AccessoryRoster()
        roster.replace(with: [mouse(45)])

        let changes = roster.replace(with: [mouse(44)])

        XCTAssertTrue(changes.isEmpty)
        XCTAssertEqual(roster.accessory("aa-bb-cc-dd-ee-ff")?.levels.single, 44)
    }

    // MARK: - Order

    /// By kind, then by name. Never by level: a list that reorders itself as
    /// the numbers tick is a list you cannot click on.
    func test_theOrderIsStableWhileLevelsMove() {
        var roster = AccessoryRoster()
        roster.replace(with: [mouse(45), airPods(), keyboard(60)])

        XCTAssertEqual(roster.accessories.map(\.kind), [.earbuds, .keyboard, .mouse])

        roster.replace(with: [mouse(3), airPods(), keyboard(99)])
        XCTAssertEqual(roster.accessories.map(\.kind), [.earbuds, .keyboard, .mouse])
    }

    func test_lowestPicksTheAccessoryClosestToDying() {
        var roster = AccessoryRoster()
        roster.replace(with: [mouse(45), airPods(left: 8, right: 60), keyboard(60)])

        XCTAssertEqual(roster.lowest?.kind, .earbuds)
        XCTAssertEqual(roster.lowest?.lowest, 8)
    }

    func test_anAccessoryThatReportsNoLevelIsNeverTheLowest() {
        var roster = AccessoryRoster()
        let silent = AccessoryBattery(
            id: "silent",
            name: "Some Dongle",
            kind: .other,
            levels: .init()
        )
        roster.replace(with: [silent, mouse(45)])

        XCTAssertEqual(roster.count, 2)
        XCTAssertEqual(roster.lowest?.id, "aa-bb-cc-dd-ee-ff")
    }

    // MARK: - TC-BAT-008

    /// Zero means "not reporting", not "flat". A bud in its case publishes
    /// its key with a zero in it, and the Mac's own keyboard publishes the
    /// whole service with no battery in it — confirmed on hardware while this
    /// module was written.
    func test_TC_BAT_008_zeroMeansNotReportingRatherThanFlat() {
        XCTAssertNil(AccessoryBattery.Levels.reported(0))
        XCTAssertNil(AccessoryBattery.Levels.reported(nil))
        XCTAssertNil(AccessoryBattery.Levels.reported(-1))
        XCTAssertNil(AccessoryBattery.Levels.reported(101))

        XCTAssertEqual(AccessoryBattery.Levels.reported(1), 1)
        XCTAssertEqual(AccessoryBattery.Levels.reported(100), 100)
    }

    func test_TC_BAT_008_aDeviceWithNoLevelsAtAllIsNotListed() {
        let levels = AccessoryBattery.Levels(
            single: AccessoryBattery.Levels.reported(0),
            left: AccessoryBattery.Levels.reported(nil),
            right: AccessoryBattery.Levels.reported(nil),
            caseLevel: AccessoryBattery.Levels.reported(nil)
        )

        XCTAssertTrue(levels.isEmpty)
    }

    // MARK: - Classification

    /// The heuristic lives in Core precisely so it can be tested against the
    /// real marketing strings IOKit hands back, rather than being buried in
    /// the scanner where nothing can reach it.
    func test_productNamesAreClassifiedFromWhatIOKitActuallyReports() {
        let expected: [String: AccessoryBattery.Kind] = [
            "AirPods Pro": .earbuds,
            "AirPods": .earbuds,
            "Milan's AirPods": .earbuds,
            "Galaxy Buds": .earbuds,
            "Magic Mouse": .mouse,
            "Magic Keyboard with Touch ID": .keyboard,
            "Magic Trackpad": .trackpad,
            "Xbox Wireless Controller": .gameController,
            "Some Dongle": .other
        ]

        for (name, kind) in expected {
            XCTAssertEqual(
                AccessoryBattery.Kind.classify(productName: name),
                kind,
                "\(name) should classify as \(kind)"
            )
        }
    }

    /// AirPods Max match both "airpods" and "headphones", and they are
    /// headphones. The order of the patterns is the whole of this test.
    func test_airPodsMaxAreHeadphonesNotEarbuds() {
        XCTAssertEqual(AccessoryBattery.Kind.classify(productName: "AirPods Max"), .headphones)
        XCTAssertEqual(AccessoryBattery.Kind.classify(productName: "Beats Studio Pro"), .headphones)
    }

    func test_classificationIgnoresCase() {
        XCTAssertEqual(AccessoryBattery.Kind.classify(productName: "MAGIC MOUSE"), .mouse)
    }

    // MARK: - TC-BAT-005

    /// The desktop case: no Mac battery, accessories still listed.
    func test_TC_BAT_005_accessoriesAreIndependentOfTheMacsOwnBattery() {
        var roster = AccessoryRoster()
        roster.replace(with: [keyboard(60), mouse(45)])

        XCTAssertFalse(PowerSnapshot.absent.isPresent)
        XCTAssertEqual(roster.count, 2)
    }
}
