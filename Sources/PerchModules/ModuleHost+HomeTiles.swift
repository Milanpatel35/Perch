import SwiftUI

public extension ModuleHost {

    /// Every module row on the home surface, in order. One list, so the
    /// view that draws the rows and the island that sizes around them can
    /// never disagree about how many there are.
    @MainActor
    func homeTiles() -> [HomeTile] {
        let button = HomeTile.buttonHeight
        return [
            batteryTile().map { HomeTile($0) },
            systemStatsTile().map { HomeTile($0) },
            launcherTile().map { HomeTile($0, heading: "Quick access", height: button) },
            shortcutsTile().map { HomeTile($0, height: button) },
            screenshotTile().map { HomeTile($0, heading: "Capture", height: button) },
            screenshotToolsTile().map { HomeTile($0, heading: "Tools", height: button) }
        ].compactMap { $0 }
    }
}
