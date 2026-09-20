import Defaults
import Foundation
import PerchCore

/// Every persisted preference in the app, in one place.
///
/// Stored in the app's own `UserDefaults` suite, which is inside the
/// container — nothing Perch remembers lives in shared storage
/// (TC-PRV-003).
public extension Defaults.Keys {

    /// Which modules are switched on.
    ///
    /// The default is deliberately small. A first run that switches on
    /// eighteen modules asks for five permissions and looks like spyware;
    /// `docs/PLAN.md` §3.1 ships presets instead.
    static let enabledModules = Key<Set<ModuleID>>(
        "modules.enabled",
        default: [.nowPlaying, .shelf, .clipboard, .hud, .battery]
    )

    /// Which screen owns the island.
    static let islandScreenPolicy = Key<String>(
        "island.screenPolicy",
        default: "builtIn"
    )

    /// Gestures, each individually disableable (`docs/FEATURES.md` §18).
    static let hoverToExpand = Key<Bool>("gesture.hoverToExpand", default: true)
    static let clickToPin = Key<Bool>("gesture.clickToPin", default: true)
    static let dragToOpenShelf = Key<Bool>("gesture.dragToOpenShelf", default: true)
    static let swipeToSkip = Key<Bool>("gesture.swipeToSkip", default: true)
}

extension ModuleID: Defaults.Serializable {}

public extension ModuleID {

    /// The name shown in Preferences and in onboarding.
    var displayName: String {
        switch self {
        case .nowPlaying: String(localized: "Now Playing")
        case .shelf: String(localized: "Shelf")
        case .clipboard: String(localized: "Clipboard")
        case .focus: String(localized: "Focus Timer")
        case .calendar: String(localized: "Calendar & Meetings")
        case .hud: String(localized: "HUD Replacement")
        case .battery: String(localized: "Battery & Accessories")
        case .notifications: String(localized: "Notifications")
        case .camera: String(localized: "Camera")
        case .systemStats: String(localized: "System Stats")
        case .weather: String(localized: "Weather")
        case .windows: String(localized: "Window Management")
        case .shortcuts: String(localized: "Shortcuts")
        case .notes: String(localized: "Notes")
        case .voice: String(localized: "Voice to Text")
        case .screenshot: String(localized: "Screenshots")
        case .hideNotch: String(localized: "Hide the Notch")
        case .appearance: String(localized: "Appearance & Gestures")
        }
    }

    /// The SF Symbol used for the module in Preferences and onboarding.
    var symbolName: String {
        switch self {
        case .nowPlaying: "music.note"
        case .shelf: "tray.full"
        case .clipboard: "doc.on.clipboard"
        case .focus: "timer"
        case .calendar: "calendar"
        case .hud: "slider.horizontal.3"
        case .battery: "battery.100"
        case .notifications: "bell"
        case .camera: "camera"
        case .systemStats: "gauge.with.dots.needle.33percent"
        case .weather: "cloud.sun"
        case .windows: "macwindow.on.rectangle"
        case .shortcuts: "command"
        case .notes: "note.text"
        case .voice: "waveform"
        case .screenshot: "camera.viewfinder"
        case .hideNotch: "rectangle.topthird.inset.filled"
        case .appearance: "paintbrush"
        }
    }
}
