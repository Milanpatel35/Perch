import SwiftUI

/// The island's outline: rounded at the bottom, *inverted* at the top where
/// it meets the screen edge.
///
/// The inverted corners are what make the island read as the hardware cutout
/// growing rather than as a black rectangle parked underneath it. On a
/// notchless Mac the same shape is used with a zero top radius, which gives
/// the floating pill.
public struct NotchShape: Shape {

    /// Radius of the two bottom corners.
    public var bottomRadius: CGFloat

    /// Radius of the concave corners where the island meets the screen edge.
    /// Zero on the virtual pill, which is not attached to anything.
    public var topRadius: CGFloat

    public init(bottomRadius: CGFloat, topRadius: CGFloat) {
        self.bottomRadius = bottomRadius
        self.topRadius = topRadius
    }

    /// Animating the radii alongside the frame is what stops the corners
    /// popping when the island grows.
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topRadius) }
        set {
            bottomRadius = newValue.first
            topRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        let top = max(0, min(topRadius, rect.width / 2))
        let bottom = max(0, min(bottomRadius, min(rect.height, rect.width / 2 - top)))

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))

        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}
