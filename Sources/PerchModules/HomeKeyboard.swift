import AppKit
import Combine
import KeyboardShortcuts
import PerchCore

extension KeyboardShortcuts.Name {
    /// Opens the island from the keyboard. No default, like every other
    /// Perch shortcut: Settings ▸ Keyboard Shortcuts sets it, or "Use
    /// suggested shortcuts" does.
    public static let openPerch = Self("openPerch")
}

/// The island, driven from the keyboard.
///
/// The Open Perch shortcut opens the home surface and takes key focus for
/// as long as it stays open. While it does, one letter runs one action
/// (`HomeKeymap`) and Escape closes it. Focus goes back to the app in front
/// the moment the home surface goes, whatever made it go.
///
/// Nothing runs between uses: the shortcut is a system hotkey, and the key
/// monitor exists only while the island is open from the keyboard.
@MainActor
public final class HomeKeyboard {

    private let modules: ModuleHost
    private let island: IslandController

    private var monitor: Any?
    private var presentation: AnyCancellable?

    /// Whether the island is open and listening for a letter.
    public private(set) var isListening = false

    public init(modules: ModuleHost, island: IslandController) {
        self.modules = modules
        self.island = island
    }

    /// Registers the Open Perch shortcut. Called once, at launch.
    public func start() {
        KeyboardShortcuts.onKeyUp(for: .openPerch) { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        }
    }

    public func stop() {
        KeyboardShortcuts.disable(.openPerch)
        endListening()
    }

    /// The shortcut a second time closes what the first one opened.
    public func toggle() {
        if isListening {
            close()
        } else {
            open()
        }
    }

    public func open() {
        // Home, or Now Playing — which opens into the same tabbed surface.
        guard let id = island.presented?.id, Self.opensTabs.contains(id) else { return }

        if island.state.presentation != .expanded(id) {
            island.send(.clicked)
        }
        guard island.state.presentation == .expanded(id) else { return }

        isListening = true
        island.setRequiresKeyFocus(true, owner: Self.focusOwner)

        // However the home surface goes — Escape, a click away, a
        // notification taking the island — the keyboard goes back with it.
        presentation = island.$state
            .map(\.presentation)
            .removeDuplicates()
            .filter { $0 != .expanded(id) }
            .sink { [weak self] _ in self?.endListening() }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window is IslandPanel else { return event }
            let key = event.charactersIgnoringModifiers ?? ""
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags
            let used = MainActor.assumeIsolated {
                self.handle(key: key, keyCode: keyCode, modifiers: modifiers)
            }
            return used ? nil : event
        }
    }

    public func close() {
        guard isListening else { return }
        endListening()
        island.send(.collapseRequested)
    }

    /// One key press while listening. True if Perch used it.
    ///
    /// The letter's action runs *after* the keyboard is handed back, so an
    /// action that wants the keyboard itself — the clipboard's search field
    /// — raises it fresh rather than inheriting this.
    @discardableResult
    func handle(key: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard isListening else { return false }

        if keyCode == Self.escape {
            close()
            return true
        }

        // A number switches tab and keeps listening.
        let plain = modifiers.isDisjoint(with: [.command, .control, .option])
        if plain, let tab = HomeTab.tab(for: key) {
            modules.homeTab = tab
            return true
        }

        // ⌘W, ⌃A and the rest belong to whoever defined them.
        guard modifiers.isDisjoint(with: [.command, .control, .option]),
            let action = HomeKeymap.action(for: key),
            modules.canPerform(action)
        else { return false }

        endListening()
        modules.perform(action)
        return true
    }

    private func endListening() {
        guard isListening else { return }
        isListening = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        presentation = nil
        island.setRequiresKeyFocus(false, owner: Self.focusOwner)
    }

    private static let focusOwner = "home.keyboard"

    /// The activities whose opened view is the tabbed home surface.
    private static let opensTabs: Set<ActivityID> = [
        HomeActivity.identifier, NowPlayingActivity.identifier
    ]
    private static let escape: UInt16 = 53
}

public extension ModuleHost {

    /// Whether the module behind an action is on.
    @MainActor
    func canPerform(_ action: HomeAction) -> Bool {
        switch action {
        case .clipboard: service(ClipboardService.self)?.isActive ?? false
        case .focus: service(FocusService.self)?.isActive ?? false
        case .camera: service(CameraService.self)?.isActive ?? false
        case .calendar: service(CalendarService.self)?.isActive ?? false
        case .captureArea, .captureWindow, .captureScreen, .copyText, .pin, .colour, .measure,
            .scan:
            service(ScreenshotService.self)?.isActive ?? false
        }
    }

    /// Runs an action exactly as its button on the home surface does.
    @MainActor
    func perform(_ action: HomeAction) {
        guard canPerform(action) else { return }
        let screenshot = service(ScreenshotService.self)

        switch action {
        case .clipboard: service(ClipboardService.self)?.openPicker()
        case .focus: service(FocusService.self)?.launch()
        case .camera: service(CameraService.self)?.openPreview()
        case .calendar: service(CalendarService.self)?.openApp()
        case .captureArea: screenshot?.perform(.save(.area))
        case .captureWindow: screenshot?.perform(.save(.window))
        case .captureScreen: screenshot?.perform(.save(.screen))
        case .copyText: screenshot?.perform(.copyText)
        case .pin: screenshot?.perform(.pin)
        case .colour: screenshot?.pickColor()
        case .measure: screenshot?.perform(.measure)
        case .scan: screenshot?.perform(.scanCode)
        }
    }
}
