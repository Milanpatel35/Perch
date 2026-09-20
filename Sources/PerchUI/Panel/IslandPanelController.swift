import AppKit
import Combine
import PerchCore
import SwiftUI

/// Owns the panel, puts it on the right screen, and keeps it there.
///
/// Re-anchoring is the part that breaks in competing apps: a display is
/// plugged in, the arrangement changes, the laptop lid closes, and the island
/// ends up off-screen or on the wrong display. Every one of those arrives as
/// the same notification, and every one of them is handled by recomputing
/// from scratch rather than by patching the old frame
/// (TC-GEO-005 … TC-GEO-008).
@MainActor
public final class IslandPanelController {

    /// Which screen owns the island.
    public enum ScreenPolicy: String, CaseIterable, Sendable {
        /// The Mac's own display, falling back to the main one. The default,
        /// because that is where the notch is.
        case builtIn
        /// Whichever screen currently has the menu bar and key window.
        case active
    }

    public var screenPolicy: ScreenPolicy = .builtIn {
        didSet { reanchor() }
    }

    private let controller: IslandController
    private let motion: MotionPreferences
    private let modules: ModuleHost

    private var panel: IslandPanel?
    private var hostingView: NSHostingView<IslandRootView>?
    private var cancellables: Set<AnyCancellable> = []

    /// The layout the panel was last placed with. Kept so a notification
    /// storm — plugging in a dock fires several — does not rebuild the panel
    /// when nothing about the geometry actually changed.
    private var layout: IslandLayout?

    /// Called every time the island is placed or re-placed, including the
    /// first time. The app uses it to keep the home activity's collapsed size
    /// in step with whatever screen the island is on — a 14" notch and a 16"
    /// notch are different sizes, and moving between them mid-session is one
    /// notification, not a relaunch.
    public var onLayoutChange: ((IslandLayout) -> Void)?

    public init(
        controller: IslandController,
        motion: MotionPreferences,
        modules: ModuleHost
    ) {
        self.controller = controller
        self.motion = motion
        self.modules = modules
    }

    // MARK: - Lifecycle

    public func show() {
        reanchor()
        observeScreenChanges()
        observeMouseEvents()
    }

    /// Tears the panel down completely. Called on quit, so no orphan window
    /// outlives the app (TC-UPD-004).
    public func teardown() {
        cancellables.removeAll()
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        hostingView = nil
        layout = nil
    }

    // MARK: - Placement

    /// Recomputes everything from the current screen state.
    public func reanchor() {
        guard let screen = targetScreen else {
            // Every display is gone — a locked laptop with the lid closed and
            // nothing attached. Put the panel away rather than leaving it at
            // a stale frame to reappear in the wrong place.
            panel?.orderOut(nil)
            layout = nil
            return
        }

        let geometry = ScreenGeometry(screen: screen)
        let next = IslandLayout(
            metrics: NotchMetrics(screen: geometry),
            screen: geometry
        )

        if next == layout, let panel, panel.isVisible { return }
        layout = next

        let frame = CGRect.fromDisplaySpace(next.panelFrame)
        let panel = panel ?? makePanel(frame: frame, layout: next)
        panel.setFrame(frame, display: true)

        hostingView?.rootView = IslandRootView(
            controller: controller,
            motion: motion,
            modules: modules,
            layout: next
        )

        panel.orderFrontRegardless()
        onLayoutChange?(next)
    }

    private func makePanel(frame: CGRect, layout: IslandLayout) -> IslandPanel {
        let panel = IslandPanel(contentRect: frame)

        let hosting = NSHostingView(
            rootView: IslandRootView(
                controller: controller,
                motion: motion,
                modules: modules,
                layout: layout
            )
        )
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        self.panel = panel
        self.hostingView = hosting
        return panel
    }

    private var targetScreen: NSScreen? {
        switch screenPolicy {
        case .builtIn:
            NSScreen.screens.first(where: \.isBuiltIn) ?? NSScreen.primaryScreen
        case .active:
            NSScreen.main ?? NSScreen.primaryScreen
        }
    }

    // MARK: - Observation

    private func observeScreenChanges() {
        // Hot-plug, arrangement change, resolution change, rotation and
        // Sidecar all arrive here. One handler, one recompute.
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reanchor() }
            .store(in: &cancellables)

        // Waking from sleep can restore a different arrangement than the one
        // the Mac went to sleep with.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reanchor() }
            .store(in: &cancellables)
    }

    private func observeMouseEvents() {
        controller.$acceptsMouseEvents
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.panel?.ignoresMouseEvents = !enabled
            }
            .store(in: &cancellables)

        // Key focus is opt-in and momentary. Only a module with a text field
        // raises it, and the panel drops it again as soon as they lower it.
        controller.$requiresKeyFocus
            .removeDuplicates()
            .sink { [weak self] required in
                self?.panel?.allowsKeyFocus = required
            }
            .store(in: &cancellables)
    }
}
