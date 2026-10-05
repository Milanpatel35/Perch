import AppKit
import KeyboardShortcuts
import PerchCore
import SwiftUI

extension HomeActivity: IslandActivityPresenting {

    public var peekSize: CGSize { collapsedSize }

    /// One size for every tab, so switching tabs never resizes the island
    /// — and the window around it — under the pointer. As small as Home's
    /// music, week, readouts and actions allow, and a month grid fits: the
    /// first tabbed surface, 620 × 290, was mostly empty black.
    public var expandedSize: CGSize { Self.surfaceSize }

    public static let surfaceSize = CGSize(width: 560, height: 252)

    public func peekView() -> AnyView {
        // Nothing. On a notched Mac the home peek *is* the cutout.
        AnyView(Color.clear)
    }

    public func expandedView() -> AnyView {
        AnyView(HomeSurface())
    }
}

/// The tabbed surface, for an activity that opens into it rather than into
/// a panel of its own — Now Playing, so that opening the island while music
/// plays shows the music *and* the week, as every comparable app does.
@MainActor
public func tabbedHomeSurface() -> AnyView {
    AnyView(HomeSurface())
}

/// The opened island: a row of tabs, and the chosen tab under it.
///
/// What each tab shows comes from the modules (`homeTabView`); this draws
/// the frame around it. It goes back to Home every time it closes.
private struct HomeSurface: View {

    @EnvironmentObject private var modules: ModuleHost

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(HomeTab.allCases, id: \.self) { tab in
                    TabButton(tab: tab, isSelected: modules.homeTab == tab) {
                        modules.homeTab = tab
                    }
                }
                Spacer(minLength: 8)
                trailing
            }

            Divider().overlay(Color.white.opacity(0.12))

            modules.homeTabView(modules.homeTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(modules.homeTab)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDisappear { modules.homeTab = .home }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Perch home"))
    }

    private var trailing: some View {
        HStack(spacing: 8) {
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
    }
}

private struct TabButton: View {

    let tab: HomeTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(isSelected ? 0.18 : 0)))
            .foregroundStyle(.white.opacity(isSelected ? 1 : 0.55))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Text("\(Text(title)) — \(String(tab.key))"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var title: LocalizedStringKey {
        switch tab {
        case .home: "Home"
        case .media: "Media"
        case .calendar: "Calendar"
        case .shelf: "Shelf"
        case .tools: "Tools"
        }
    }

    private var symbol: String {
        switch tab {
        case .home: "house"
        case .media: "music.note"
        case .calendar: "calendar"
        case .shelf: "tray"
        case .tools: "square.grid.2x2"
        }
    }
}

/// One row of buttons with its heading, drawn at the height `HomeTile`
/// states.
public struct HomeTileRow: View {

    let tile: HomeTile

    public init(tile: HomeTile) {
        self.tile = tile
    }

    public var body: some View {
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
