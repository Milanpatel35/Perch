import Foundation
import PerchCore
import SwiftUI

/// The home surface shows a battery tile, so it needs the battery
/// specifically — the same way the island's root view needs the shelf.
///
/// It hands back a built view rather than the service, for two reasons. The
/// dependency keeps pointing the right way: the island layer knows there is
/// *a* battery tile, not what a `BatteryService` is. And the tile observes
/// the service itself, so a level that moves while the island is open
/// redraws one row instead of the whole home surface.
///
/// Returns nothing when the module is off, which is how the tile disappears
/// without the home surface needing a rule about it.
public extension ModuleHost {

    @MainActor
    func batteryTile() -> AnyView? {
        guard let service = service(BatteryService.self), service.isActive else { return nil }
        return AnyView(BatteryTile(service: service))
    }
}
