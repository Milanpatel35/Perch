import Foundation
import PerchCore

/// A notification, mirrored into the island.
///
/// One activity per app rather than one per message: nine messages from one
/// person is one entry saying nine, which is what `NotificationPolicy.Burst`
/// is for (TC-NTF-004).
struct NotificationActivity: IslandActivity {

    /// Keyed on the app, so a second message from the same person updates
    /// the entry in place rather than pushing another one behind it.
    var id: ActivityID {
        ActivityID("notification.\(burst.bundleID ?? burst.appName)")
    }

    let source: ModuleID = .notifications

    /// Above Now Playing, below a finishing timer. A message is worth
    /// interrupting an album sleeve for; it is not worth taking the island
    /// from a meeting that is starting or a Pomodoro that has just ended.
    let priority: ActivityPriority = .fileDrop

    /// Six seconds unless it can be replied to.
    ///
    /// A banner you can type into must not vanish while you are reaching
    /// for it, so a repliable notification is held until it is dismissed —
    /// the island's version of the banner that waits.
    var timeToLive: Duration? { burst.latest.canReply ? nil : .seconds(6) }

    let burst: NotificationPolicy.Burst

    /// Whether Perch can still type into the banner this came from.
    ///
    /// Separate from `canReply` on the notification itself: the banner is
    /// what holds the reply field, and it leaves the screen on its own
    /// schedule. False means the expanded view offers "Open" instead
    /// (TC-NTF-011).
    let canReplyNow: Bool
}
