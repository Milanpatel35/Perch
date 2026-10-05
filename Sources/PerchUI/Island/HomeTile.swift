import SwiftUI

/// One row on the home surface, and how much room it takes.
///
/// The height is stated rather than measured, because the island has to
/// size itself — and the window around it — before the row is drawn
/// (`IslandSizing`). The surface draws every row at exactly this height,
/// so the two never disagree.
public struct HomeTile {

    public let view: AnyView
    public let heading: LocalizedStringKey?
    public let height: CGFloat

    /// A row of readouts — battery, stats.
    public static let readoutHeight: CGFloat = 18
    /// A row of `HomeRowButton`s.
    public static let buttonHeight: CGFloat = 24
    /// A heading, and the gap under it.
    public static let headingHeight: CGFloat = 12
    public static let headingGap: CGFloat = 4

    public init(
        _ view: AnyView,
        heading: LocalizedStringKey? = nil,
        height: CGFloat = readoutHeight
    ) {
        self.view = view
        self.heading = heading
        self.height = height
    }

    /// The whole row, heading included.
    public var totalHeight: CGFloat {
        height + (heading == nil ? 0 : Self.headingHeight + Self.headingGap)
    }
}
