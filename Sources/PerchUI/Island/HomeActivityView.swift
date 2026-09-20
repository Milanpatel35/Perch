import AppKit
import PerchCore
import SwiftUI

extension HomeActivity: IslandActivityPresenting {

    public var peekSize: CGSize { collapsedSize }

    public var expandedSize: CGSize { CGSize(width: 420, height: 180) }

    public func peekView() -> AnyView {
        // Nothing. On a notched Mac the home peek *is* the cutout.
        AnyView(Color.clear)
    }

    public func expandedView() -> AnyView {
        AnyView(HomeSurface())
    }
}

/// The tray behind the notch.
///
/// Modules add their own tiles here as they land — the shelf's stack, the
/// clipboard's last few entries, the next calendar event. Until then it is
/// the island's front door and the thing that proves the panel works.
private struct HomeSurface: View {

    @Environment(\.colorScheme) private var colorScheme

    /// The monochrome mark, tinted white for the island's black background.
    /// Loaded once — a view body runs often, and `NSImage(named:)` on every
    /// pass is work for nothing.
    private static let mark: NSImage = {
        let image = NSImage(named: "MenuBarIcon") ?? NSImage()
        image.isTemplate = false
        return image.tinted(.white)
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(nsImage: Self.mark)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                Text("Perch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(Date.now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Divider().overlay(Color.white.opacity(0.12))

            Text("Every module you switch on appears here.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Perch home"))
    }
}
