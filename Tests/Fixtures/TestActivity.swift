import Foundation
@testable import PerchCore

/// A minimal `IslandActivity` for testing the reducer and the queue without
/// dragging in a real module.
struct TestActivity: IslandActivity {
    let id: ActivityID
    let source: ModuleID
    let priority: ActivityPriority
    let timeToLive: Duration?
    let isExpandable: Bool

    init(
        _ id: String,
        source: ModuleID = .nowPlaying,
        priority: ActivityPriority = .ambient,
        timeToLive: Duration? = .seconds(3),
        isExpandable: Bool = true
    ) {
        self.id = ActivityID(id)
        self.source = source
        self.priority = priority
        self.timeToLive = timeToLive
        self.isExpandable = isExpandable
    }
}

extension ActivityID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

/// Screens the geometry tests run against, standing in for hardware nobody
/// has to plug in. Values match the real safe-area insets those models report.
enum TestScreen {

    /// 14" MacBook Pro — notched built-in.
    static let notched14 = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaInsets: EdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
        notchWidth: 186,
        scaleFactor: 2,
        isBuiltIn: true
    )

    /// 16" MacBook Pro — a different notch, to prove nothing is hardcoded.
    static let notched16 = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        safeAreaInsets: EdgeInsets(top: 34, left: 0, bottom: 0, right: 0),
        notchWidth: 204,
        scaleFactor: 2,
        isBuiltIn: true
    )

    /// Pre-notch built-in display, e.g. an Intel MacBook on Ventura.
    static let builtInNoNotch = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        safeAreaInsets: .zero,
        notchWidth: 0,
        scaleFactor: 2,
        isBuiltIn: true
    )

    /// An external display. Never reports a notch inset.
    static let external = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
        safeAreaInsets: .zero,
        notchWidth: 0,
        scaleFactor: 1,
        isBuiltIn: false
    )

    /// A screen reporting a nonzero but implausible top inset. Must not be
    /// trusted as a notch (TC-GEO-009).
    static let degenerate = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        safeAreaInsets: EdgeInsets(top: 2, left: 0, bottom: 0, right: 0),
        notchWidth: 4,
        scaleFactor: 2,
        isBuiltIn: true
    )
}
