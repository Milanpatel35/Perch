import CoreGraphics
import PerchCore

/// How big the island is right now.
///
/// One answer for the two things that need it: the view that draws the
/// island, and the panel that sizes the window around it. If they ever
/// disagreed, the window would either clip the island or go back to taking
/// clicks that belong to the apps beside the notch (TC-GEO-013).
@MainActor
enum IslandSizing {

    static func islandSize(
        for presentation: IslandPresentation,
        presented: AnyIslandActivity?,
        modules: ModuleHost,
        layout: IslandLayout
    ) -> CGSize {
        let presenting = presented?.base as? any IslandActivityPresenting

        let requested: CGSize =
            switch presentation {
            case .idle:
                layout.metrics.collapsedSize
            case .peek:
                presenting?.peekSize ?? layout.metrics.collapsedSize
            case .expanded:
                // The home surface sizes to the module rows it is about to
                // draw; every other activity knows its own size.
                presented?.id == HomeActivity.identifier
                    ? HomeActivity.expandedSize(tiles: modules.homeTiles())
                    : presenting?.expandedSize ?? layout.metrics.collapsedSize
            }

        return layout.islandFrame(contentSize: requested).size
    }
}
