import Foundation

/// One of the overlays Perch replaces.
///
/// Six, not eight. `docs/FEATURES.md` §6 lists keyboard backlight and AirDrop
/// as well, and both are recorded there as not done rather than faked: the
/// keyboard's level can be *read* but nothing on macOS publishes a change to
/// it, and AirDrop has no interface at all. A switch for a HUD that can never
/// fire is worse than an honest gap.
public enum HUDKind: String, CaseIterable, Sendable, Codable {

    /// Output volume and mute, from CoreAudio. The only one of the six that
    /// is entirely public API.
    case volume

    /// Display brightness.
    case brightness

    /// Charger in, charger out. Shares its rule with module 7: keyed on the
    /// power source, never on `isCharging`.
    case power

    /// A Bluetooth accessory connected or disconnected.
    case bluetooth

    /// Focus mode turned on, changed or turned off. Do Not Disturb is a
    /// Focus, so it is this one rather than a seventh.
    case focus

    /// The camera or the microphone started or stopped being used by
    /// something. The privacy dot, with the name of what is using it.
    case capture

    public var displayName: String {
        switch self {
        case .volume: String(localized: "Volume")
        case .brightness: String(localized: "Brightness")
        case .power: String(localized: "Charging")
        case .bluetooth: String(localized: "Bluetooth")
        case .focus: String(localized: "Focus")
        case .capture: String(localized: "Camera and microphone")
        }
    }

    /// Whether this HUD draws a level bar. The others are a glyph and a line
    /// of text, and a bar stuck at 100% would be furniture.
    public var showsLevel: Bool {
        switch self {
        case .volume, .brightness: true
        case .power, .bluetooth, .focus, .capture: false
        }
    }
}

/// What to put on the island, for one HUD.
///
/// Deliberately a value with no behaviour: the watchers build one of these
/// and `HUDPolicy` decides whether it is worth showing. That is what lets
/// every rule in `docs/TEST-PLAN.md` § HUD be tested without a volume key,
/// a display, or a Bluetooth radio.
public struct HUDReading: Equatable, Sendable {

    public let kind: HUDKind

    /// 0–1 for the two HUDs that have a level, `nil` for the rest.
    public let level: Double?

    /// Muted is not the same as zero: a Mac muted at 40% goes back to 40%.
    public let isMuted: Bool

    public let title: String

    /// The second line, where there is one — a device name, a Focus name,
    /// the app using the camera.
    public let detail: String?

    public init(
        kind: HUDKind,
        level: Double? = nil,
        isMuted: Bool = false,
        title: String,
        detail: String? = nil
    ) {
        self.kind = kind
        self.level = level.map { min(1, max(0, $0)) }
        self.isMuted = isMuted
        self.title = title
        self.detail = detail
    }

    /// The level as a percentage, for the label and for VoiceOver.
    public var percentage: Int? {
        level.map { Int(($0 * 100).rounded()) }
    }
}
