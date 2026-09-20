import Foundation
import PerchCore

/// The shelf, as the island sees it.
///
/// Module 2 of `docs/FEATURES.md`. Two states, and they are genuinely
/// different things: *holding* files, which is ambient and stays until the
/// shelf is empty, and *being dragged onto*, which is a drop target and
/// outranks almost everything because the user is mid-gesture and needs to
/// see where to let go.
struct ShelfActivity: IslandActivity {

    static let identifier = ActivityID("shelf.current")

    let id = Self.identifier
    let source: ModuleID = .shelf

    var items: [ShelfItem]

    /// True while something is being dragged over the island.
    var isDropTarget: Bool

    /// A drop target is urgent — the pointer is held down and the person is
    /// looking for somewhere to release it. Holding files is ambient.
    var priority: ActivityPriority {
        isDropTarget ? .fileDrop : .ambient
    }

    /// Never expires. The shelf holds things until they are taken, and a
    /// drop target lasts exactly as long as the drag does.
    var timeToLive: Duration? { nil }

    init(items: [ShelfItem], isDropTarget: Bool = false) {
        self.items = items
        self.isDropTarget = isDropTarget
    }
}
