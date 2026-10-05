import Combine
import PerchCore
import SwiftUI

/// What each tab of the opened island shows.
///
/// Here, in the modules, because every tab is made of modules; the island
/// itself (`HomeActivityView`) knows only that there are tabs. A tab whose
/// module is off offers to switch it on rather than showing an empty page.
public extension ModuleHost {

    @MainActor
    func homeTabView(_ tab: HomeTab) -> AnyView {
        switch tab {
        case .home: AnyView(HomeTabView(modules: self))
        case .media: AnyView(MediaTabView(modules: self))
        case .calendar: AnyView(CalendarTabView(modules: self))
        case .shelf: AnyView(ShelfTabView(modules: self))
        case .tools: AnyView(ToolsTabView(modules: self))
        }
    }
}

// MARK: - Home

/// Everything at a glance, and every action one click away: the music
/// beside the week, the readouts under them, then a row with a button for
/// each thing Perch can do.
private struct HomeTabView: View {

    let modules: ModuleHost

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if let nowPlaying = modules.activeNowPlaying {
                        NowPlayingCard(service: nowPlaying)
                    } else {
                        SwitchOn(module: .nowPlaying, modules: modules)
                    }
                }
                .frame(width: 236, height: 118)

                Group {
                    if let calendar = modules.showableCalendar {
                        CalendarAccessReader(service: calendar, layout: .card)
                    } else {
                        SwitchOn(module: .calendar, modules: modules)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 118, alignment: .topLeading)
            }

            let readouts = [modules.batteryTile(), modules.systemStatsTile()].compactMap { $0 }
            if !readouts.isEmpty {
                HStack(spacing: 18) {
                    ForEach(readouts.indices, id: \.self) { readouts[$0] }
                    Spacer(minLength: 0)
                }
                .frame(height: HomeTile.readoutHeight)
            }

            QuickActionsRow(modules: modules)
        }
    }
}

/// The track, small: artwork, title, artist, and the three buttons.
private struct NowPlayingCard: View {

    @ObservedObject var service: NowPlayingService

    var body: some View {
        if let snapshot = service.snapshot {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Artwork(data: snapshot.artwork, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(snapshot.title, weight: .semibold)
                        MarqueeText(
                            snapshot.artist.isEmpty ? snapshot.album : snapshot.artist,
                            weight: .regular
                        )
                        .foregroundStyle(.white.opacity(0.6))
                    }
                }
                HStack(spacing: 14) {
                    TransportButton(symbol: "backward.fill") { service.previousTrack() }
                    TransportButton(
                        symbol: snapshot.isPlaying ? "pause.fill" : "play.fill",
                        size: 16
                    ) {
                        service.togglePlayPause()
                    }
                    TransportButton(symbol: "forward.fill") { service.nextTrack() }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(height: 118)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
        } else {
            NothingPlaying()
                .padding(10)
                .frame(height: 118)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
        }
    }
}

private struct NothingPlaying: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing playing")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Play something in any app.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Media

private struct MediaTabView: View {

    let modules: ModuleHost

    var body: some View {
        if let service = modules.service(NowPlayingService.self), service.isActive {
            MediaPlayer(service: service)
        } else {
            SwitchOn(module: .nowPlaying, modules: modules)
        }
    }
}

private struct MediaPlayer: View {

    @ObservedObject var service: NowPlayingService

    var body: some View {
        if let snapshot = service.snapshot {
            NowPlayingExpanded(snapshot: snapshot)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
        } else {
            NothingPlaying()
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Calendar

private struct CalendarTabView: View {

    let modules: ModuleHost

    var body: some View {
        if let service = modules.showableCalendar {
            CalendarAccessReader(service: service, layout: .full)
        } else {
            SwitchOn(module: .calendar, modules: modules)
        }
    }
}

/// Observes the service, so access being granted redraws the calendar.
private struct CalendarAccessReader: View {

    @ObservedObject var service: CalendarService
    let layout: HomeCalendar.Layout

    var body: some View {
        if let preview = HomeCalendarPreview.events {
            HomeCalendar(
                access: .granted, events: preview,
                changes: Empty().eraseToAnyPublisher(), layout: layout)
        } else {
            HomeCalendar(service: service, layout: layout)
        }
    }
}

extension ModuleHost {

    /// Now Playing, if it is on.
    @MainActor
    fileprivate var activeNowPlaying: NowPlayingService? {
        guard let service = service(NowPlayingService.self), service.isActive else { return nil }
        return service
    }

    /// The calendar module, if it is on — or if a demo week stands in for it.
    @MainActor
    fileprivate var showableCalendar: CalendarService? {
        guard let service = service(CalendarService.self) else { return nil }
        return service.isActive || HomeCalendarPreview.events != nil ? service : nil
    }
}

/// A demo week for `make screenshots`. The website's pictures are drawn
/// from the real views, and CI has no calendar — nor should a test ask
/// macOS for one. Nil, and unused, everywhere else.
@MainActor
enum HomeCalendarPreview {
    static var events: ((DateInterval) -> [CalendarEvent])?
}

// MARK: - Shelf

private struct ShelfTabView: View {

    let modules: ModuleHost

    var body: some View {
        if let service = modules.service(ShelfService.self), service.isActive {
            ShelfContents(service: service)
        } else {
            SwitchOn(module: .shelf, modules: modules)
        }
    }
}

private struct ShelfContents: View {

    @ObservedObject var service: ShelfService

    var body: some View {
        if service.store.items.isEmpty, !service.isDropTarget {
            // An empty tab is a place to drop, and says so.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 18))
                        Text("Drag files onto the notch and they wait here")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.55))
                )
        } else {
            ShelfExpanded(items: service.store.items, isDropTarget: service.isDropTarget)
                .padding(.horizontal, -14)
                .padding(.top, -12)
        }
    }
}

// MARK: - Tools

private struct ToolsTabView: View {

    let modules: ModuleHost

    var body: some View {
        let tiles = [
            modules.launcherTile().map {
                HomeTile($0, heading: "Quick access", height: HomeTile.buttonHeight)
            },
            modules.shortcutsTile().map {
                HomeTile($0, heading: "Shortcuts", height: HomeTile.buttonHeight)
            },
            modules.screenshotTile().map {
                HomeTile($0, heading: "Capture", height: HomeTile.buttonHeight)
            },
            modules.screenshotToolsTile().map {
                HomeTile($0, heading: "Tools", height: HomeTile.buttonHeight)
            }
        ].compactMap { $0 }

        if tiles.isEmpty {
            Notice(
                symbol: "square.grid.2x2",
                text: "Switch on Screenshots, Clipboard or Focus and their buttons appear here."
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(tiles.indices, id: \.self) { index in
                        HomeTileRow(tile: tiles[index])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Shared

/// A tab whose module is off: what it would show, and the switch.
private struct SwitchOn: View {

    let module: ModuleID
    let modules: ModuleHost

    var body: some View {
        Notice(
            symbol: module.symbolName,
            text: "\(module.displayName) is off.",
            action: ("Switch on \(module.displayName)", { modules.enable(module) })
        )
    }
}
