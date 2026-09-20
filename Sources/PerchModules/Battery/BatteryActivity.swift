import Foundation
import PerchCore

/// Something happened to the power.
///
/// Brief by design. The battery is a thing you glance at, and an island that
/// stayed open every time a charger went in would be in the way all day. The
/// readable state — every level, all the time — is the tile on the home
/// surface, not this.
struct BatteryActivity: IslandActivity {

    static let identifier = ActivityID("battery.alert")

    /// What is being announced. The priority and the time to live both come
    /// from this rather than being passed in, because "how urgent is a low
    /// battery" is a property of the event, not of the call site.
    enum Reason: Equatable, Sendable {
        case pluggedIn(Int)
        case unplugged(Int)
        case low(Int)
        case charged
    }

    let id = Self.identifier
    let source: ModuleID = .battery
    let reason: Reason

    /// Everything else, so the expanded presentation has something to open
    /// into when somebody hovers the alert.
    let power: PowerSnapshot
    let accessories: [AccessoryBattery]

    /// A low battery is the one thing this module has that deserves to
    /// interrupt. Everything else is ambient and yields to whatever is
    /// already there (`CLAUDE.md` §3).
    var priority: ActivityPriority {
        switch reason {
        case .low: .systemAlert
        case .pluggedIn, .unplugged, .charged: .ambient
        }
    }

    /// Long enough to read, short enough to stay out of the way. The low
    /// warning gets longer because it is asking you to do something.
    var timeToLive: Duration? {
        switch reason {
        case .low: .seconds(6)
        case .charged: .seconds(3)
        case .pluggedIn, .unplugged: .seconds(2)
        }
    }

    init(
        reason: Reason,
        power: PowerSnapshot,
        accessories: [AccessoryBattery] = []
    ) {
        self.reason = reason
        self.power = power
        self.accessories = accessories
    }
}

/// The readable state: the Mac, then everything connected to it.
///
/// Stays until dismissed, because it is a thing you opened rather than a
/// thing that happened to you.
struct BatteryStatusActivity: IslandActivity {

    static let identifier = ActivityID("battery.status")

    let id = Self.identifier
    let source: ModuleID = .battery

    /// Above ambient: the user asked for this, so it displaces whatever was
    /// merely sitting there — the same rule the clipboard's picker follows.
    let priority: ActivityPriority = .fileDrop

    let timeToLive: Duration? = nil

    let power: PowerSnapshot
    let accessories: [AccessoryBattery]
}
