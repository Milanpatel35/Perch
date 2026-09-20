import AppKit
import Foundation
import PerchCore

/// The island's root view needs the shelf specifically, because the island
/// itself is the drop target — not the shelf's view, which does not exist
/// until the shelf has something to present (TC-SHF-001).
///
/// Declared here, in the module, rather than in `PerchUI`: it keeps the
/// dependency pointing the right way. The island layer knows there is *a*
/// shelf; it does not know what a `ShelfService` is.
public extension ModuleHost {
    var shelf: ShelfDropTarget? {
        service(ShelfService.self)
    }
}

/// The slice of the shelf the island needs in order to be a drop target.
@MainActor
public protocol ShelfDropTarget: AnyObject {
    var isDropTarget: Bool { get }
    func beginDrag()
    func endDrag()
    @discardableResult
    func accept(_ providers: [NSItemProvider]) async -> Int
}
