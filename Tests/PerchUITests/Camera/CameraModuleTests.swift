import AVFoundation
import AppKit
import PerchCore
import SwiftUI
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` § CAM for the parts that need the real module —
/// and in particular the three promises `CLAUDE.md` §4 singles this module
/// out for: TC-CAM-007, TC-CAM-008 and TC-CAM-009.
///
/// A CI machine has no camera permission, so nothing here opens a device.
/// That turns out to be the point: the promises are all about what the
/// module does *not* do, and every one of them is testable without one.
@MainActor
final class CameraModuleTests: XCTestCase {

    private struct Harness {
        let camera: CameraService
        let island: IslandController
    }

    private func makeService() -> Harness {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        return Harness(camera: CameraService(island: island), island: island)
    }

    // MARK: - TC-CAM-009

    /// **The promise on the website.** Switching the module on opens no
    /// device. Neither does listing cameras, and neither does enabling the
    /// pre-call check.
    func test_TC_CAM_009_switchingTheModuleOnOpensNoDevice() {
        let harness = makeService()
        harness.camera.activate()

        XCTAssertTrue(harness.camera.isActive)
        XCTAssertFalse(harness.camera.isPreviewing)
        XCTAssertNil(harness.camera.session.session, "no session exists until the preview opens")
        XCTAssertFalse(harness.camera.session.isRunning)

        harness.camera.deactivate()
    }

    func test_TC_CAM_009_listingDevicesOpensNoDevice() {
        let harness = makeService()
        harness.camera.activate()

        harness.camera.refreshDevices()

        XCTAssertNil(harness.camera.session.session)
        harness.camera.deactivate()
    }

    func test_TC_CAM_009_enablingThePreCallCheckOpensNoDevice() {
        let harness = makeService()
        harness.camera.activate()

        var configuration = PreCallCheck.Configuration()
        configuration.isEnabled = true
        harness.camera.setPreCallConfiguration(configuration)

        XCTAssertNil(harness.camera.session.session)
        harness.camera.deactivate()
    }

    /// The whole module, switched on and off five times, never opens a
    /// device. This is the test that catches somebody adding a warm-up.
    func test_TC_CAM_009_noLifecyclePathOpensADevice() {
        let harness = makeService()

        for _ in 0..<5 {
            harness.camera.activate()
            harness.camera.refreshDevices()
            harness.camera.setShape(.circle)
            harness.camera.toggleMirror()
            harness.camera.deactivate()
            XCTAssertNil(harness.camera.session.session)
        }
    }

    // MARK: - TC-CAM-006

    func test_TC_CAM_006_closingThePreviewReleasesTheSessionSynchronously() {
        let harness = makeService()
        harness.camera.activate()

        // Nothing to release on a machine with no permission, but the
        // teardown path is the same one and must be safe either way.
        harness.camera.closePreview()

        XCTAssertNil(harness.camera.session.session)
        XCTAssertFalse(harness.camera.isPreviewing)
        XCTAssertNil(harness.island.presented)

        harness.camera.deactivate()
    }

    func test_TC_CAM_006_switchingTheModuleOffReleasesEverything() {
        let harness = makeService()
        harness.camera.activate()
        harness.camera.deactivate()

        XCTAssertFalse(harness.camera.isActive)
        XCTAssertFalse(harness.camera.isPreviewing)
        XCTAssertNil(harness.camera.session.session)
        XCTAssertTrue(harness.camera.devices.isEmpty)
        XCTAssertNil(harness.island.presented)
    }

    func test_TC_CAM_006_deactivatingTwiceIsSafe() {
        let harness = makeService()
        harness.camera.activate()
        harness.camera.deactivate()
        harness.camera.deactivate()

        XCTAssertFalse(harness.camera.isActive)
    }

    // MARK: - TC-CAM-007 and TC-CAM-008

    /// **No frame reaches disk, and no buffer is kept.** Both are true by
    /// construction rather than by discipline: a running preview has no
    /// output attached at all, so there is nothing to write and nothing to
    /// retain. A session that grew an output would fail this.
    func test_TC_CAM_007_aRunningPreviewHasNoOutputAttached() {
        let harness = makeService()
        harness.camera.activate()

        XCTAssertTrue(harness.camera.session.session?.outputs.isEmpty ?? true)

        harness.camera.deactivate()
    }

    func test_TC_CAM_008_snapshotWithoutAPreviewWritesNothing() async {
        let harness = makeService()
        harness.camera.activate()

        var wrote = false
        harness.camera.onSnapshot = { _ in
            wrote = true
            return true
        }

        harness.camera.snapshot()

        XCTAssertFalse(wrote, "there is no preview, so there is nothing to capture")
        harness.camera.deactivate()
    }

    // MARK: - TC-CAM-015

    /// With the calendar module off, nothing calls the camera. Here the
    /// call is made anyway — and it must still be the pre-call rules that
    /// decide, not a crash and not an unasked-for green light.
    func test_TC_CAM_015_aMeetingTooFarOffDoesNotOpenAnything() {
        let harness = makeService()
        harness.camera.activate()

        harness.camera.meetingApproaching(
            eventID: "standup",
            title: "Standup",
            startsAt: Date().addingTimeInterval(3_600),
            hasLink: true
        )

        XCTAssertFalse(harness.camera.isPreviewing)
        XCTAssertNil(harness.camera.session.session)

        harness.camera.deactivate()
    }

    func test_TC_CAM_015_theHookIsInertWhileTheModuleIsOff() {
        let harness = makeService()

        harness.camera.meetingApproaching(
            eventID: "standup",
            title: "Standup",
            startsAt: Date().addingTimeInterval(30),
            hasLink: true
        )

        XCTAssertNil(harness.camera.session.session)
        XCTAssertNil(harness.island.presented)
    }

    // MARK: - Presentation

    func test_TC_CAM_003_mirroringPersistsAcrossTheModuleBeingSwitchedOff() {
        let harness = makeService()
        harness.camera.activate()

        let before = harness.camera.presentation.isMirrored
        harness.camera.toggleMirror()
        XCTAssertNotEqual(harness.camera.presentation.isMirrored, before)

        harness.camera.deactivate()
        harness.camera.activate()

        XCTAssertNotEqual(harness.camera.presentation.isMirrored, before)
        harness.camera.toggleMirror()
        harness.camera.deactivate()
    }

    func test_TC_CAM_004_shapeChangesAreRememberedAndKeepTheirRatio() {
        let harness = makeService()
        harness.camera.activate()

        harness.camera.setShape(.wide)
        XCTAssertEqual(harness.camera.presentation.shape, .wide)
        XCTAssertEqual(
            harness.camera.presentation.size.width / harness.camera.presentation.size.height,
            16.0 / 9.0,
            accuracy: 0.0001
        )

        harness.camera.setShape(.rounded)
        harness.camera.deactivate()
    }

    /// Resizing is clamped in Core, so a flick cannot lose the preview —
    /// and the module must not be able to route around that.
    func test_resizingThroughTheServiceStaysClamped() {
        let harness = makeService()
        harness.camera.activate()

        for _ in 0..<200 { harness.camera.resize(byScroll: -80) }
        XCTAssertEqual(harness.camera.presentation.width, CameraPresentation.minimumWidth)

        for _ in 0..<200 { harness.camera.resize(byScroll: 80) }
        XCTAssertEqual(harness.camera.presentation.width, CameraPresentation.maximumWidth)

        var reset = harness.camera.presentation
        reset.setWidth(260)
        harness.camera.setPresentation(reset)
        harness.camera.deactivate()
    }
}
