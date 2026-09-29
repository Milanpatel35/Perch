import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § CAM for everything that is arithmetic rather than
/// hardware — TC-CAM-003, TC-CAM-004, TC-CAM-012 and TC-CAM-014.
///
/// The module that owns a capture device should have as little logic in it
/// as possible, which is why the shapes, the clamping and the device choice
/// are all values tested here with no camera anywhere.
final class CameraPresentationTests: XCTestCase {

    // MARK: - TC-CAM-003

    func test_TC_CAM_003_mirroringIsOnByDefaultAndSurvivesARoundTrip() throws {
        var presentation = CameraPresentation()
        XCTAssertTrue(presentation.isMirrored)

        presentation.isMirrored = false

        let encoded = try JSONEncoder().encode(presentation)
        let decoded = try JSONDecoder().decode(CameraPresentation.self, from: encoded)

        XCTAssertFalse(decoded.isMirrored)
        XCTAssertEqual(decoded, presentation)
    }

    // MARK: - TC-CAM-004

    /// Every shape keeps its ratio at every size. A squashed face is the
    /// failure TC-CAM-004 names, and it comes from the view computing a
    /// height of its own.
    func test_TC_CAM_004_everyShapeKeepsItsRatioAtEverySize() {
        for shape in CameraPresentation.Shape.allCases {
            var presentation = CameraPresentation()
            presentation.shape = shape

            for width in [160.0, 260.0, 400.0, 640.0] {
                presentation.setWidth(width)
                XCTAssertEqual(
                    presentation.size.width / presentation.size.height,
                    shape.aspectRatio,
                    accuracy: 0.0001,
                    "\(shape) distorted at \(width)pt"
                )
            }
        }
    }

    func test_TC_CAM_004_theCircleIsSquare() {
        var presentation = CameraPresentation()
        presentation.shape = .circle
        presentation.setWidth(200)

        XCTAssertEqual(presentation.size.width, presentation.size.height)
        XCTAssertEqual(CameraPresentation.Shape.circle.cornerFraction, 0.5)
    }

    func test_TC_CAM_004_everyShapeIsOfferedInThePicker() {
        XCTAssertEqual(CameraPresentation.Shape.allCases.count, 4)
        for shape in CameraPresentation.Shape.allCases {
            XCTAssertFalse(shape.displayName.isEmpty)
            XCTAssertGreaterThan(shape.aspectRatio, 0)
        }
    }

    // MARK: - Clamping

    /// The width comes from a scroll wheel, and a scroll wheel has no end
    /// stops. A preview scrolled to 4pt or to 9000pt is a preview nobody can
    /// get back.
    func test_scrollingPastTheEndClampsRatherThanRunningAway() {
        var presentation = CameraPresentation()

        for _ in 0..<200 { presentation.resize(byScroll: -50) }
        XCTAssertEqual(presentation.width, CameraPresentation.minimumWidth)

        for _ in 0..<200 { presentation.resize(byScroll: 50) }
        XCTAssertEqual(presentation.width, CameraPresentation.maximumWidth)
    }

    func test_opacityNeverGoesBelowAQuarter() {
        var presentation = CameraPresentation()

        presentation.setOpacity(0)
        XCTAssertEqual(presentation.opacity, 0.25)

        presentation.setOpacity(4)
        XCTAssertEqual(presentation.opacity, 1)
    }

    /// Resizing is proportional, so the same flick moves a small preview a
    /// little and a large one a lot.
    func test_resizingIsProportional() {
        var small = CameraPresentation()
        small.setWidth(200)
        let smallBefore = small.width
        small.resize(byScroll: 20)

        var large = CameraPresentation()
        large.setWidth(600)
        let largeBefore = large.width
        large.resize(byScroll: 20)

        XCTAssertGreaterThan(large.width - largeBefore, small.width - smallBefore)
    }

    // MARK: - TC-CAM-012

    private let builtIn = CameraDevice(id: "built-in", name: "FaceTime HD", isBuiltIn: true)
    private let external = CameraDevice(id: "usb", name: "Logitech C920")
    private let phone = CameraDevice(id: "iphone", name: "Priya's iPhone", isContinuity: true)

    func test_theRememberedDeviceWinsWhenItIsStillThere() {
        let chosen = CameraSelection.resolve(preferred: "usb", from: [builtIn, external, phone])
        XCTAssertEqual(chosen?.id, "usb")
    }

    func test_theBuiltInCameraIsTheFallback() {
        XCTAssertEqual(
            CameraSelection.resolve(preferred: "gone", from: [external, builtIn])?.id,
            "built-in"
        )
        XCTAssertEqual(
            CameraSelection.resolve(preferred: nil, from: [external, builtIn])?.id,
            "built-in"
        )
    }

    func test_noCameraAtAllIsAnAnswerRatherThanACrash() {
        XCTAssertNil(CameraSelection.resolve(preferred: "usb", from: []))
        XCTAssertNil(CameraSelection.fallback(after: "usb", from: []))
    }

    func test_TC_CAM_012_unpluggingFallsBackToWhatIsLeft() {
        let next = CameraSelection.fallback(after: "usb", from: [builtIn, phone])
        XCTAssertEqual(next?.id, "built-in")
    }

    func test_TC_CAM_012_unpluggingTheOnlyCameraLeavesNothing() {
        XCTAssertNil(CameraSelection.fallback(after: "usb", from: [external]))
    }
}
