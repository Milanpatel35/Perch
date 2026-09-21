import Foundation
import PerchCore

/// A system overlay, in the notch instead of the middle of the screen.
///
/// **One identifier for all six kinds, deliberately.** Turning the volume up
/// while the brightness HUD is still on screen should replace it, not queue
/// behind it — you pressed a key and you want to see the result of that key.
/// Sharing an id means the island updates in place and the transition is a
/// value change rather than a dismiss and a re-present, which is what makes
/// a held key look smooth (TC-HUD-002).
///
/// **Ambient priority, deliberately.** A HUD must not pre-empt a timer
/// finishing or a low battery. It composes with whatever is on the island
/// rather than fighting it (TC-HUD-004): if something more important is
/// there, the queue keeps it there and the HUD waits, which is the correct
/// answer for an overlay you triggered by pressing a key you can press again.
struct HUDActivity: IslandActivity {

    static let identifier = ActivityID("hud.current")

    let id = Self.identifier
    let source: ModuleID = .hud
    let priority: ActivityPriority = .ambient

    /// The stock HUD is on screen for about a second and a half. Matching it
    /// is the point — this is a replacement, not a new thing to learn.
    let timeToLive: Duration? = .seconds(1.6)

    /// A HUD is a glance, not a surface. Hovering one should not open it into
    /// something you can click, because your hand is on the keyboard.
    let isExpandable = false

    let reading: HUDReading
}
