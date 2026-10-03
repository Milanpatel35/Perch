import SwiftUI

public extension ModuleHost {

    /// Every module row on the home surface, in order. One list, so the
    /// view that draws the rows and the island that sizes around them can
    /// never disagree about how many there are.
    @MainActor
    func homeTiles() -> [AnyView] {
        [batteryTile(), systemStatsTile(), shortcutsTile()].compactMap { $0 }
    }
}
