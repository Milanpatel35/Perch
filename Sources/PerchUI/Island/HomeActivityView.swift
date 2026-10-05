import AppKit
import KeyboardShortcuts
import PerchCore
import SwiftUI

extension HomeActivity: IslandActivityPresenting {

    public var peekSize: CGSize { collapsedSize }

    /// The size with no module rows. The island root view asks
    /// `expandedSize(tiles:)` instead, because only it can see which modules
    /// are on; this answers the protocol for anything that cannot.
    public var expandedSize: CGSize { Self.expandedSize(tiles: []) }

    /// Tall enough for the header and the rows, and no taller. A fixed
    /// 180pt left a band of empty black under one or two rows.
    ///
    /// 460 wide since every button shows its key: the capture row's five
    /// buttons did not fit in 420 with a key cap each.
    public static func expandedSize(tiles: [HomeTile]) -> CGSize {
        let chrome: CGFloat = 14 + 18 + 10 + 1 + 10 + 12
        let rows =
            tiles.isEmpty
            ? HomeTile.readoutHeight
            : tiles.map(\.totalHeight).reduce(0, +) + CGFloat(tiles.count - 1) * rowSpacing
        return CGSize(width: 460, height: chrome + rows)
    }

    static let rowSpacing: CGFloat = 10

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
    @EnvironmentObject private var modules: ModuleHost

    /// The monochrome mark, tinted white for the island's black background.
    /// Loaded once — a view body runs often, and `NSImage(named:)` on every
    /// pass is work for nothing.
    private static let mark: NSImage = {
        let image = NSImage(named: "MenuBarIcon") ?? NSImage()
        image.isTemplate = false
        return image.tinted(.white)
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: HomeActivity.rowSpacing) {
            HStack(spacing: 8) {
                Image(nsImage: Self.mark)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                Text("Perch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if let shortcut = KeyboardShortcuts.getShortcut(for: .openPerch) {
                    // How to get back here without the mouse.
                    Text(shortcut.description)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .help(Text("Opens Perch from anywhere"))
                }
                Text(Date.now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                if let openSettings = modules.openSettings {
                    // The way to every module that is *off*: the island can
                    // only show buttons for the ones that are on.
                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help(Text("Settings — switch modules on and off"))
                    .accessibilityLabel(Text("Settings"))
                }
            }

            Divider().overlay(Color.white.opacity(0.12))

            let tiles = modules.homeTiles()

            if tiles.isEmpty {
                Text("Every module you switch on appears here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(tiles.indices, id: \.self) { index in
                    row(tiles[index])
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Perch home"))
    }

    /// Drawn at exactly the height the island sized for (`HomeTile`).
    private func row(_ tile: HomeTile) -> some View {
        VStack(alignment: .leading, spacing: HomeTile.headingGap) {
            if let heading = tile.heading {
                Text(heading)
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(height: HomeTile.headingHeight)
                    .accessibilityAddTraits(.isHeader)
            }
            tile.view
                .frame(height: tile.height, alignment: .leading)
        }
    }
}
