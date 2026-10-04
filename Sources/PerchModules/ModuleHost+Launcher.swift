import PerchCore
import SwiftUI

/// The launcher row: a button for each module that is on and has something
/// to open by hand. Which ones, and in what order, is `HomeLauncher`'s call.
struct LauncherTile: View {

    let entries: [ModuleID]
    let modules: ModuleHost

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .accessibilityHidden(true)

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
                    help: String(localized: "Search everything you copied")
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
                    help: String(localized: "Check how you look before a call")
                ) {
                    camera.openPreview()
                }
            }
        case .calendar:
            if let calendar = modules.service(CalendarService.self) {
                HomeRowButton(
                    title: "Calendar", symbol: "calendar",
                    help: String(localized: "Open Calendar")
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
        switch HomeLauncher.FocusAction(focus.timer) {
        case .start:
            HomeRowButton(
                title: "Focus", symbol: "timer",
                help: String(localized: "Start a focus session")
            ) {
                focus.start()
            }
        case .pause:
            HomeRowButton(
                title: "Pause", symbol: "pause.fill",
                help: String(localized: "Pause the focus session")
            ) {
                focus.toggle()
            }
        case .resume:
            HomeRowButton(
                title: "Resume", symbol: "play.fill",
                help: String(localized: "Resume the focus session")
            ) {
                focus.toggle()
            }
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
