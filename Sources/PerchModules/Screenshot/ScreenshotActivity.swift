import Foundation
import PerchCore

/// What the screenshot module says on the island once a capture is done.
///
/// Only an outcome, never the capture in progress: while somebody is
/// choosing an area the island is closed, so it is not in the picture
/// (TC-SCR-013). A cancelled capture says nothing at all (TC-SCR-004), and
/// a capture that went into the shelf or a pin says nothing either — the
/// shelf opening, or the card appearing, already said it.
struct ScreenshotActivity: IslandActivity {

    static let identifier = ActivityID("screenshot.result")

    let id = Self.identifier
    let source: ModuleID = .screenshot

    /// A file just landed, which is what this tier is for.
    let priority: ActivityPriority = .fileDrop

    let outcome: Outcome

    let isExpandable = false

    enum Outcome: Equatable, Sendable {
        /// Saved to the screenshot folder, named `filename`.
        case saved(filename: String, folder: String)
        case copiedImage
        case copiedText(characters: Int)
        case noText
        case failed(reason: String)
        /// Screen Recording is off. Stays longer, because it asks somebody
        /// to go and do something.
        case needsPermission
        /// A colour on the clipboard, in the chosen format.
        case copiedColor(text: String, color: SampledColor)
        /// An area's size on the clipboard, `W × H`.
        case measured(String)
        case openedLink(host: String)
        case copiedCode
        case noCode
    }

    var timeToLive: Duration? {
        outcome == .needsPermission ? .seconds(6) : .seconds(3)
    }
}
