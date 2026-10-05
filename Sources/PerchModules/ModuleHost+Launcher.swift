import PerchCore
import SwiftUI

/// The launcher row: a button for each module that is on and has something
/// to open by hand. Which ones, and in what order, is `HomeLauncher`'s call.
struct LauncherTile: View {

    let entries: [ModuleID]
    let modules: ModuleHost

    var body: some View {
        HStack(spacing: 5) {
            ForEach(entries, id: \.self) { entry in
                button(for: entry)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func button(for entry: ModuleID) -> some View {
        switch entry {
        case .clipboard:
            if let clipboard = modules.service(ClipboardService.self) {
                HomeRowButton(
                    title: "Clipboard", symbol: "doc.on.clipboard",
                    help: String(localized: "Search everything you copied"),
                    key: HomeKeymap.key(for: .clipboard)
                ) {
                    clipboard.openPicker()
                }
            }
        case .focus:
            if let focus = modules.service(FocusService.self) {
                FocusLaunchButton(focus: focus)
            }
        case .camera:
            if let camera = modules.service(CameraService.self) {
                HomeRowButton(
                    title: "Camera", symbol: "camera",
                    help: String(localized: "Check how you look before a call"),
                    key: HomeKeymap.key(for: .camera)
                ) {
                    camera.openPreview()
                }
            }
        case .calendar:
            if let calendar = modules.service(CalendarService.self) {
                HomeRowButton(
                    title: "Calendar", symbol: "calendar",
                    help: String(localized: "Open Calendar"),
                    key: HomeKeymap.key(for: .calendar)
                ) {
                    calendar.openApp()
                }
            }
        default:
            EmptyView()
        }
    }
}

/// Observes the timer on its own, so a session starting or pausing redraws
/// one button rather than the whole home surface.
private struct FocusLaunchButton: View {

    @ObservedObject var focus: FocusService

    var body: some View {
        HomeRowButton(
            title: title, symbol: symbol, help: help, key: HomeKeymap.key(for: .focus)
        ) {
            focus.launch()
        }
    }

    private var action: HomeLauncher.FocusAction { HomeLauncher.FocusAction(focus.timer) }

    private var title: LocalizedStringKey {
        switch action {
        case .start: "Focus"
        case .pause: "Pause"
        case .resume: "Resume"
        }
    }

    private var symbol: String {
        switch action {
        case .start: "timer"
        case .pause: "pause.fill"
        case .resume: "play.fill"
        }
    }

    private var help: String {
        switch action {
        case .start: String(localized: "Start a focus session")
        case .pause: String(localized: "Pause the focus session")
        case .resume: String(localized: "Resume the focus session")
        }
    }
}

public extension ModuleHost {

    /// The launcher row, or nothing when no module with a button is on.
    @MainActor
    func launcherTile() -> AnyView? {
        let entries = HomeLauncher.entries { id in
            (module(for: id)?.isActive) ?? false
        }
        guard !entries.isEmpty else { return nil }
        return AnyView(LauncherTile(entries: entries, modules: self))
    }
}
