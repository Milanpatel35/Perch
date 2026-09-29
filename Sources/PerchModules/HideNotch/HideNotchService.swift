import AppKit
import Combine
import Defaults
import PerchCore

/// One display, as the Preferences pane lists it.
struct HideNotchDisplay: Equatable, Identifiable {
    let id: String
    let name: String
    let hasNotch: Bool
    let showsStrip: Bool
}

/// Module 17 — hide-the-notch mode.
///
/// TopNotch's whole product as one pane (`docs/FEATURES.md` §17). A strip
/// behind the menu bar on each chosen display, filled black or with the
/// wallpaper's top edge, and an island that can draw nothing until something
/// happens.
///
/// **The one module with no activity.** Everything else puts something *on*
/// the island; this changes how the menu bar and the idle island look, and
/// never presents anything. So there is no `HideNotchActivity.swift` —
/// writing one to satisfy `CLAUDE.md` §4's file list would be a type nobody
/// submits.
///
/// Nothing here polls. The strips move when the display arrangement changes,
/// and re-colour when the wallpaper watcher says so — and only while the
/// setting that needs each one is on.
@MainActor
final class HideNotchService: ObservableObject, PerchModule {

    static let moduleID: ModuleID = .hideNotch

    @Published private(set) var configuration: HideNotchConfiguration
    @Published private(set) var displays: [HideNotchDisplay] = []

    private(set) var isActive = false

    private let island: IslandController
    private let wallpaper = WallpaperWatcher()

    /// One strip per display that has one, keyed by display UUID.
    private var strips: [String: MenuBarStripPanel] = [:]
    private var screenObserver: AnyCancellable?

    init(island: IslandController) {
        self.island = island
        self.configuration = Defaults[.hideNotch]
    }

    // MARK: - What the tests look at

    var stripCount: Int { strips.count }
    var isObservingScreens: Bool { screenObserver != nil }
    var isWatchingWallpaper: Bool { wallpaper.isWatching }

    // MARK: - PerchModule

    func activate() {
        guard !isActive else { return }
        isActive = true
        apply()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        // Synchronous and total: TC-HID-005 is "returns to normal
        // immediately, no artefacts", and TC-HID-007 is that nothing is left
        // listening afterwards.
        closeAllStrips()
        screenObserver = nil
        wallpaper.stop()
        island.setHidesIdleIsland(false)
        displays = []
    }

    // MARK: - Settings

    func setConfiguration(_ configuration: HideNotchConfiguration) {
        self.configuration = configuration
        Defaults[.hideNotch] = configuration
        if isActive { apply() }
    }

    func setShowsStrip(_ shows: Bool, onDisplay id: String) {
        var updated = configuration
        updated.displayChoices[id] = shows
        setConfiguration(updated)
    }

    // MARK: - Applying

    /// Brings windows and observers in line with the configuration. Each
    /// resource exists only while the setting that needs it is on.
    private func apply() {
        island.setHidesIdleIsland(configuration.isInvisibleWhenIdle)

        if configuration.isBlackoutEnabled {
            observeScreens()
        } else {
            screenObserver = nil
        }

        if configuration.isBlackoutEnabled, configuration.fill == .wallpaper {
            wallpaper.start { [weak self] in self?.layoutStrips() }
        } else {
            wallpaper.stop()
        }

        layoutStrips()
    }

    /// Recomputes every strip from scratch, the same way the island
    /// re-anchors: a dock plugged in fires several notifications, and
    /// patching the previous layout is how a strip ends up on a display that
    /// has gone (TC-HID-003).
    private func layoutStrips() {
        var shown: Set<String> = []
        var listed: [HideNotchDisplay] = []

        for screen in NSScreen.screens {
            guard let id = screen.displayUUID else { continue }

            let geometry = ScreenGeometry(screen: screen)
            let hasNotch = NotchMetrics(screen: geometry).mode == .hardware
            let wanted = configuration.showsStrip(on: id, hasNotch: hasNotch)

            listed.append(
                HideNotchDisplay(
                    id: id,
                    name: screen.localizedName,
                    hasNotch: hasNotch,
                    showsStrip: configuration.displayChoices[id] ?? hasNotch
                )
            )

            guard wanted,
                let frame = MenuBarStrip.frame(on: geometry, menuBarHeight: screen.menuBarHeight)
            else { continue }

            let strip = strips[id] ?? MenuBarStripPanel()
            strips[id] = strip
            strip.show(frame: .fromDisplaySpace(frame), colour: colour(for: screen))
            shown.insert(id)
        }

        for (id, strip) in strips where !shown.contains(id) {
            strip.orderOut(nil)
            strips[id] = nil
        }

        displays = listed
    }

    private func colour(for screen: NSScreen) -> StripColor {
        guard configuration.fill == .wallpaper else { return .black }
        return wallpaper.colour(for: screen) ?? .black
    }

    private func observeScreens() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.layoutStrips() }
    }

    private func closeAllStrips() {
        for strip in strips.values {
            strip.orderOut(nil)
        }
        strips = [:]
    }
}
