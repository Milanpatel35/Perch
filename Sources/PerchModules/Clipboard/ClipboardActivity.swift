import Foundation
import PerchCore

/// A copy, announced.
///
/// Brief on purpose. The clipboard's real interface is the picker, reached by
/// a keyboard shortcut; this is the acknowledgement that something landed.
/// An island that stayed open after every copy would be unusable.
struct ClipboardActivity: IslandActivity {

    static let identifier = ActivityID("clipboard.latest")

    let id = Self.identifier
    let source: ModuleID = .clipboard
    let priority: ActivityPriority = .ambient

    var entry: ClipboardEntry
    var historyCount: Int

    /// Two seconds. Long enough to read "Copied", short enough not to be in
    /// the way of the next thing you do.
    let timeToLive: Duration? = .seconds(2)

    init(entry: ClipboardEntry, historyCount: Int) {
        self.entry = entry
        self.historyCount = historyCount
    }
}

/// The searchable picker, which is a different thing: it stays until
/// dismissed, takes the keyboard, and is what the module is actually for.
struct ClipboardPickerActivity: IslandActivity {

    static let identifier = ActivityID("clipboard.picker")

    let id = Self.identifier
    let source: ModuleID = .clipboard

    /// Above ambient: the user asked for this by pressing a shortcut, so it
    /// displaces whatever was merely sitting there.
    let priority: ActivityPriority = .fileDrop

    /// Stays until dismissed. It has a text field in it.
    let timeToLive: Duration? = nil

    var entries: [ClipboardEntry]
}
