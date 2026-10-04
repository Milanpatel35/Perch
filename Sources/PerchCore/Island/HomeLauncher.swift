/// The launcher row on the home surface.
///
/// Battery, stats, Shortcuts and Screenshot each have a row of their own.
/// Everything else that is on had no way in from the island at all: the
/// clipboard behind a hotkey, the camera and the focus timer behind nothing.
/// This is the row that puts a button on each of them.
///
/// Only modules with something to open *by hand* are here. The shelf fills
/// when a file is dropped on the notch, notifications and the HUD arrive on
/// their own, and Now Playing appears when something plays — a button for
/// any of those would open nothing.
public enum HomeLauncher {

    /// Fixed, so a button never moves when another module is switched on.
    public static let order: [ModuleID] = [.clipboard, .focus, .camera, .calendar]

    /// The buttons to draw, in order. Empty means no row at all.
    public static func entries(isOn: (ModuleID) -> Bool) -> [ModuleID] {
        order.filter(isOn)
    }

    /// What the focus button does next, which is also what it says.
    public enum FocusAction: Equatable, Sendable {
        case start
        case pause
        case resume

        public init(_ timer: PomodoroTimer) {
            self = timer.isRunning ? .pause : timer.isPaused ? .resume : .start
        }
    }
}
