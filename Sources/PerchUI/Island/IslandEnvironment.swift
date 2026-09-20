import PerchCore
import SwiftUI

private struct NotchMetricsKey: EnvironmentKey {
    /// A plausible virtual pill, used only when a view is rendered outside
    /// the island — a SwiftUI preview, or a snapshot test.
    static let defaultValue = NotchMetrics(
        screen: ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
    )
}

public extension EnvironmentValues {

    /// The geometry of the island this view is being drawn in.
    ///
    /// Modules need it because a peek presentation is laid out *around* the
    /// cutout: artwork on one side, visualiser on the other, and the notch
    /// itself in between. The gap is the hardware's width, which differs per
    /// model and must never be hardcoded (`CLAUDE.md` §9).
    var notchMetrics: NotchMetrics {
        get { self[NotchMetricsKey.self] }
        set { self[NotchMetricsKey.self] = newValue }
    }
}
