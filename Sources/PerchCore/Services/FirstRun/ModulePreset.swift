import Foundation

/// The four starting points the first run offers (`docs/PLAN.md` §3.1).
///
/// With a dozen modules built, a first run that presents a dozen switches is
/// a form, not a welcome. A preset is a sentence somebody recognises
/// themselves in, and every switch stays in Settings afterwards.
public enum ModulePreset: String, CaseIterable, Sendable {
    case music
    case work
    case everything
    case justHideTheNotch

    /// What the preset switches on, limited to what exists in this build.
    ///
    /// A preset never names a module that is not built: switching one on
    /// would do nothing, and a switch that does nothing is a bug report
    /// (#61).
    public func modules(built: Set<ModuleID>) -> Set<ModuleID> {
        wanted.intersection(built)
    }

    /// Every permission the preset's modules may ask for, in the order the
    /// first run lists them. Nothing is asked for here — each module still
    /// asks at the moment it needs to (`CLAUDE.md` §5.3). This is so the
    /// card can say so before anybody picks it.
    public func permissions(built: Set<ModuleID>) -> [ModulePermission] {
        let asked = Set(modules(built: built).flatMap(\.permissions))
        return ModulePermission.allCases.filter(asked.contains)
    }

    private var wanted: Set<ModuleID> {
        switch self {
        case .music:
            [.nowPlaying, .hud, .battery]
        case .work:
            [.nowPlaying, .shelf, .clipboard, .focus, .calendar, .notifications, .hud, .battery]
        case .everything:
            // Hide-the-notch is left out: it changes how the menu bar looks
            // rather than adding something to the island, and "everything"
            // should not mean "and paint my menu bar black".
            Set(ModuleID.allCases).subtracting([.hideNotch, .appearance])
        case .justHideTheNotch:
            [.hideNotch]
        }
    }
}

/// A system permission a module may ask for. The table at the end of
/// `docs/FEATURES.md` is the source; this is that table in code.
public enum ModulePermission: String, CaseIterable, Sendable {
    case calendar
    case accessibility
    case camera
    case location
    case microphone
    case screenRecording
}

public extension ModuleID {

    /// What this module may ask for. Asked lazily, by the module, when it is
    /// switched on or first used — never at launch (TC-PRV-002).
    var permissions: [ModulePermission] {
        switch self {
        case .calendar: [.calendar, .accessibility]
        case .notifications, .windows: [.accessibility]
        case .camera: [.camera]
        case .weather: [.location]
        case .voice: [.microphone]
        case .screenshot: [.screenRecording]
        case .nowPlaying, .shelf, .clipboard, .focus, .hud, .battery, .systemStats,
            .shortcuts, .notes, .hideNotch, .appearance:
            []
        }
    }
}
