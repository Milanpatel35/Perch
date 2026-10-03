import Foundation

/// Where the running copy of Perch lives, and whether that stops it opening
/// at login.
///
/// A copy opened straight from Downloads runs from a randomised read-only
/// path macOS invents for it (App Translocation). A login item registered
/// from there points at a path that is gone after the next reboot, so the
/// switch would say "on" and Perch would not come back — the worst way for
/// it to fail. The first run and Settings say so instead.
public enum InstallLocation: Equatable, Sendable {
    case applications
    case translocated
    case elsewhere

    public init(bundlePath: String, homeDirectory: String = NSHomeDirectory()) {
        let path = (bundlePath as NSString).standardizingPath
        let userApplications =
            (homeDirectory as NSString).appendingPathComponent("Applications") + "/"
        if path.contains("/AppTranslocation/") {
            self = .translocated
        } else if path.hasPrefix("/Applications/") || path.hasPrefix(userApplications) {
            self = .applications
        } else {
            self = .elsewhere
        }
    }

    /// Whether opening at login can be trusted to survive a reboot.
    public var supportsLaunchAtLogin: Bool { self != .translocated }
}
