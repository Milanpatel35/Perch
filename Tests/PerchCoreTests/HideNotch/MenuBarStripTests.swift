import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § HID for the parts that are arithmetic: where the
/// strip goes, which displays get one, what colour it is, and when the
/// island draws nothing.
final class MenuBarStripTests: XCTestCase {

    private let notched = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaInsets: EdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
        notchWidth: 185
    )

    private let external = ScreenGeometry(
        frame: CGRect(x: 1512, y: -200, width: 2560, height: 1440),
        scaleFactor: 1,
        isBuiltIn: false
    )

    // MARK: - TC-HID-001

    func test_TC_HID_001_theStripCoversTheWholeMenuBarOfANotchedDisplay() throws {
        let strip = try XCTUnwrap(MenuBarStrip.frame(on: notched, menuBarHeight: 32))

        XCTAssertEqual(strip, CGRect(x: 0, y: 0, width: 1512, height: 32))
    }

    /// A strip a pixel short of either the notch or the bar leaves a hairline,
    /// which is the one thing this mode exists to remove.
    func test_TC_HID_001_theStripIsAsTallAsTheTallerOfNotchAndMenuBar() throws {
        let taller = try XCTUnwrap(MenuBarStrip.frame(on: notched, menuBarHeight: 37))
        XCTAssertEqual(taller.height, 37)

        let shorter = try XCTUnwrap(MenuBarStrip.frame(on: notched, menuBarHeight: 24))
        XCTAssertEqual(shorter.height, 32)
    }

    func test_TC_HID_001_aFractionalHeightRoundsUpToAWholePixel() throws {
        let screen = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: EdgeInsets(top: 32.3, left: 0, bottom: 0, right: 0),
            notchWidth: 185,
            scaleFactor: 2
        )

        let strip = try XCTUnwrap(MenuBarStrip.frame(on: screen, menuBarHeight: 0))
        XCTAssertEqual(strip.height, 32.5)
    }

    func test_TC_HID_001_aHiddenMenuBarWithNoNotchHasNothingToCover() {
        XCTAssertNil(MenuBarStrip.frame(on: external, menuBarHeight: 0))
    }

    // MARK: - TC-HID-003

    /// The strip lands on the display it was asked for, in that display's own
    /// coordinates — not at the primary's origin.
    func test_TC_HID_003_theStripSitsOnItsOwnDisplay() throws {
        let strip = try XCTUnwrap(MenuBarStrip.frame(on: external, menuBarHeight: 25))

        XCTAssertEqual(strip, CGRect(x: 1512, y: -200, width: 2560, height: 25))
    }

    func test_TC_HID_003_byDefaultOnlyANotchedDisplayGetsAStrip() {
        let configuration = HideNotchConfiguration()

        XCTAssertTrue(configuration.showsStrip(on: "built-in", hasNotch: true))
        XCTAssertFalse(configuration.showsStrip(on: "external", hasNotch: false))
    }

    func test_TC_HID_003_aPerDisplayChoiceOverridesTheDefault() {
        var configuration = HideNotchConfiguration()
        configuration.displayChoices = ["built-in": false, "external": true]

        XCTAssertFalse(configuration.showsStrip(on: "built-in", hasNotch: true))
        XCTAssertTrue(configuration.showsStrip(on: "external", hasNotch: false))
        XCTAssertFalse(
            configuration.showsStrip(on: "another", hasNotch: false),
            "a choice for one display says nothing about the others"
        )
    }

    // MARK: - TC-HID-005

    func test_TC_HID_005_blackoutOffMeansNoStripAnywhere() {
        var configuration = HideNotchConfiguration()
        configuration.displayChoices = ["external": true]
        configuration.isBlackoutEnabled = false

        XCTAssertFalse(configuration.showsStrip(on: "built-in", hasNotch: true))
        XCTAssertFalse(configuration.showsStrip(on: "external", hasNotch: false))
    }

    // MARK: - TC-HID-002

    func test_TC_HID_002_theColourIsTheAverageOfTheTopRowsOnly() throws {
        // Two rows of blue sky over two rows of sand. Averaged whole it is
        // beige; the top edge is blue.
        let sky: [UInt8] = [0, 0, 255, 255]
        let sand: [UInt8] = [255, 200, 100, 255]
        let pixels =
            Array(repeating: sky, count: 4).flatMap { $0 }
            + Array(repeating: sand, count: 4).flatMap { $0 }

        let colour = try XCTUnwrap(
            WallpaperEdge.averageColor(rgba: pixels, width: 2, height: 4, rows: 2)
        )

        XCTAssertEqual(colour, StripColor(red: 0, green: 0, blue: 1))
    }

    func test_TC_HID_002_moreRowsThanTheImageHasReadsOnlyWhatIsThere() throws {
        let pixels: [UInt8] = [255, 0, 0, 255, 0, 0, 0, 255]

        let colour = try XCTUnwrap(
            WallpaperEdge.averageColor(rgba: pixels, width: 2, height: 1, rows: 40)
        )

        XCTAssertEqual(colour.red, 0.5, accuracy: 0.0001)
        XCTAssertEqual(colour.green, 0)
    }

    func test_TC_HID_002_aMalformedBufferGivesNoColourRatherThanAGuess() {
        XCTAssertNil(WallpaperEdge.averageColor(rgba: [], width: 0, height: 0, rows: 4))
        XCTAssertNil(WallpaperEdge.averageColor(rgba: [0, 0, 0], width: 2, height: 2, rows: 1))
    }

    func test_stripColourIsClampedAndBlackIsDark() {
        XCTAssertEqual(StripColor(red: 2, green: -1, blue: 0.5).red, 1)
        XCTAssertEqual(StripColor(red: 2, green: -1, blue: 0.5).green, 0)
        XCTAssertEqual(StripColor.black.luminance, 0)
        XCTAssertEqual(StripColor(red: 1, green: 1, blue: 1).luminance, 1, accuracy: 0.0001)
    }

    // MARK: - TC-HID-006

    func test_TC_HID_006_normallyTheIslandAlwaysDraws() {
        for presentation: IslandPresentation in [.idle, .peek("x"), .expanded("x")] {
            XCTAssertTrue(
                IdleVisibility.isDrawn(presentation, showsHome: true, invisibleWhenIdle: false)
            )
        }
    }

    func test_TC_HID_006_invisibleModeHidesTheIdleAndCollapsedHomeIsland() {
        XCTAssertFalse(IdleVisibility.isDrawn(.idle, showsHome: false, invisibleWhenIdle: true))
        XCTAssertFalse(
            IdleVisibility.isDrawn(.peek("island.home"), showsHome: true, invisibleWhenIdle: true)
        )
    }

    /// Something happening is exactly when it appears.
    func test_TC_HID_006_invisibleModeStillShowsEveryActivity() {
        XCTAssertTrue(
            IdleVisibility.isDrawn(.peek("battery.low"), showsHome: false, invisibleWhenIdle: true)
        )
        XCTAssertTrue(
            IdleVisibility.isDrawn(
                .expanded("battery.low"), showsHome: false, invisibleWhenIdle: true)
        )
    }

    /// Hovering the notch still opens the home surface. An island that
    /// cannot be reached is not invisible, it is gone.
    func test_TC_HID_006_theHomeIslandStillDrawsOnceHoveredOpen() {
        XCTAssertTrue(
            IdleVisibility.isDrawn(
                .expanded("island.home"), showsHome: true, invisibleWhenIdle: true)
        )
    }

    func test_configurationRoundTripsThroughCodable() throws {
        var configuration = HideNotchConfiguration()
        configuration.fill = .wallpaper
        configuration.displayChoices = ["a": true]
        configuration.isInvisibleWhenIdle = true

        let data = try JSONEncoder().encode(configuration)
        XCTAssertEqual(
            try JSONDecoder().decode(HideNotchConfiguration.self, from: data), configuration)
    }
}
