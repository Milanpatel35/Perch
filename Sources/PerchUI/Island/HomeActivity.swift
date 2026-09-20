import PerchCore
import SwiftUI

/// The island's home surface — what it shows when nothing else is happening.
///
/// It is a real activity rather than a special case in the reducer, submitted
/// at `ambient` priority with no time to live. That is what `ambient` is for,
/// and it buys three things for free: hover-to-open works through the same
/// path as every module, anything more urgent pre-empts it without a rule
/// being written, and `.idle` keeps its honest meaning — every module off,
/// nothing to show, panel inert (TC-ISL-001).
///
/// Its peek is deliberately the exact size of the notch, so an idle island is
/// invisible on a notched Mac and is the bare pill on one without.
public struct HomeActivity: IslandActivity {

    public static let identifier = ActivityID("island.home")

    public let id = Self.identifier
    public let source: ModuleID = .appearance
    public let priority: ActivityPriority = .ambient

    /// Never expires. The home surface is not an event; it is the floor.
    public let timeToLive: Duration? = nil
    public let isExpandable = true

    /// Matches the notch so the peek presentation draws nothing extra.
    public let collapsedSize: CGSize

    public init(collapsedSize: CGSize) {
        self.collapsedSize = collapsedSize
    }
}
