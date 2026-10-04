import Foundation

/// The pointer a C callback carries back to the object that registered it.
///
/// IOKit, the Accessibility API and the display services take a bare
/// `void *` and hand it back on every event. Passing `self` unretained —
/// which four modules did — means an event arriving after the object is
/// gone dereferences freed memory, and the whole app crashes. It happened:
/// the battery observer outlived its service and brought the test process
/// down with `EXC_BAD_ACCESS` on a real power event (TC-PRF-005).
///
/// The box holds the target weakly and is itself retained for as long as
/// the registration lives. If the target goes first, the callback finds
/// `nil` and does nothing. Release it after unregistering, never before.
final class CallbackContext<Target: AnyObject>: @unchecked Sendable {

    private(set) weak var target: Target?

    private init(_ target: Target) {
        self.target = target
    }

    /// A retained pointer for the C API. Balance it with `release(_:)`
    /// once the callback can no longer fire.
    static func retain(_ target: Target) -> UnsafeMutableRawPointer {
        Unmanaged.passRetained(CallbackContext(target)).toOpaque()
    }

    /// The target behind a pointer a callback was given, or `nil` if it has
    /// gone. Never consumes the reference.
    static func target(of pointer: UnsafeMutableRawPointer?) -> Target? {
        guard let pointer else { return nil }
        return Unmanaged<CallbackContext>.fromOpaque(pointer).takeUnretainedValue().target
    }

    /// Gives back the reference `retain(_:)` took.
    static func release(_ pointer: UnsafeMutableRawPointer?) {
        guard let pointer else { return }
        Unmanaged<CallbackContext>.fromOpaque(pointer).release()
    }
}
