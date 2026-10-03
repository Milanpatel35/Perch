import SwiftUI

/// A peek laid out around the cutout: one thing either side, the notch
/// between them.
///
/// Anything drawn in the middle of a peek is drawn under the camera housing,
/// and on a notched Mac nobody can see it. Four peeks did exactly that — a
/// meeting starting, a system alert, the battery list and the clipboard
/// picker — and a meeting alert you cannot read is not an alert. The gap is
/// the hardware's own width, from `notchMetrics` (`CLAUDE.md` §9).
public struct NotchFlanks<Leading: View, Trailing: View>: View {

    @Environment(\.notchMetrics) private var metrics

    private let leading: Leading
    private let trailing: Trailing

    public init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 0) {
            leading
                .padding(.leading, 14)

            Spacer(minLength: metrics.collapsedSize.width)

            trailing
                .lineLimit(1)
                .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
