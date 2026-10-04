import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` TC-PRF-005 for the pointer every C callback in
/// Perch carries: an event arriving after its module has gone must do
/// nothing, not crash.
final class CallbackContextTests: XCTestCase {

    private final class Target {}

    func test_TC_PRF_005_theCallbackFindsItsTargetWhileItLives() {
        let target = Target()
        let pointer = CallbackContext.retain(target)
        defer { CallbackContext<Target>.release(pointer) }

        XCTAssertTrue(CallbackContext<Target>.target(of: pointer) === target)
    }

    /// The crash this exists for: the battery observer outlived its service
    /// and a power event dereferenced freed memory.
    func test_TC_PRF_005_aCallbackAfterItsTargetHasGoneDoesNothing() throws {
        var target: Target? = Target()
        let pointer = CallbackContext.retain(try XCTUnwrap(target))
        defer { CallbackContext<Target>.release(pointer) }

        target = nil

        XCTAssertNil(CallbackContext<Target>.target(of: pointer))
    }

    func test_TC_PRF_005_theContextDoesNotKeepItsTargetAlive() {
        weak var watched: Target?
        let pointer: UnsafeMutableRawPointer
        do {
            let target = Target()
            watched = target
            pointer = CallbackContext.retain(target)
        }
        defer { CallbackContext<Target>.release(pointer) }

        XCTAssertNil(watched, "no retain cycle through the C API")
    }

    func test_TC_PRF_005_aNilPointerIsNoTarget() {
        XCTAssertNil(CallbackContext<Target>.target(of: nil))
        CallbackContext<Target>.release(nil)
    }
}
