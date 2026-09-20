import CoreGraphics
import PerchCore
import SwiftUI

/// The view half of a module.
///
/// `IslandActivity` is the model and lives in Foundation-only code so it can
/// be unit-tested. This is the other half: how that model draws. A module
/// conforms its activity to this in `<Name>View.swift` (`CLAUDE.md` §4).
///
/// `AnyView` here is deliberate. It is the one place the island erases a
/// view type, and it buys the ability to hold seventeen unrelated modules in
/// one queue without the queue knowing any of them.
@MainActor
public protocol IslandActivityPresenting: IslandActivity {

    /// Drawn beside the notch while the island is peeking. Must survive being
    /// squeezed into the width of a notch plus a few points.
    func peekView() -> AnyView

    /// Drawn when the island is open.
    func expandedView() -> AnyView

    /// Size of the peek presentation, including the notch it sits around.
    var peekSize: CGSize { get }

    /// Size of the expanded presentation. Clamped to
    /// `IslandLayout.maximumContentSize` — the panel is sized from that, so
    /// anything larger is clipped by the window rather than by the layout.
    var expandedSize: CGSize { get }
}

public extension IslandActivityPresenting {
    var peekSize: CGSize { CGSize(width: 320, height: 32) }
    var expandedSize: CGSize { CGSize(width: 380, height: 160) }
}
