import PerchCore
import SwiftUI

/// Every action Perch can run, as one row of small buttons on Home — so
/// nothing is a tab away. Each shows its name and key on hover.
struct QuickActionsRow: View {

    let modules: ModuleHost

    var body: some View {
        HStack(spacing: 6) {
            ForEach(modules.quickActions(), id: \.self) { action in
                QuickActionButton(action: action) { modules.perform(action) }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct QuickActionButton: View {

    let action: HomeAction
    let run: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: run) {
            Image(systemName: action.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.8))
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(hovering ? 0.22 : 0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Text("\(Text(action.title)) — \(String(HomeKeymap.key(for: action)))"))
        .accessibilityLabel(Text(action.title))
    }
}

extension HomeAction {

    var title: LocalizedStringKey {
        switch self {
        case .clipboard: "Clipboard"
        case .focus: "Focus"
        case .camera: "Camera"
        case .calendar: "Calendar"
        case .captureArea: "Capture an area"
        case .captureWindow: "Capture a window"
        case .captureScreen: "Capture the screen"
        case .copyText: "Copy text from an area"
        case .pin: "Pin an area"
        case .colour: "Pick a colour"
        case .measure: "Measure an area"
        case .scan: "Scan a QR code"
        }
    }

    var symbol: String {
        switch self {
        case .clipboard: "doc.on.clipboard"
        case .focus: "timer"
        case .camera: "camera"
        case .calendar: "calendar"
        case .captureArea: "rectangle.dashed"
        case .captureWindow: "macwindow"
        case .captureScreen: "display"
        case .copyText: "text.viewfinder"
        case .pin: "pin"
        case .colour: "eyedropper"
        case .measure: "ruler"
        case .scan: "qrcode.viewfinder"
        }
    }
}

public extension ModuleHost {

    /// The actions Home offers: every one whose module is on, in keymap
    /// order. Calendar is left out — Home already shows the calendar.
    @MainActor
    func quickActions() -> [HomeAction] {
        HomeAction.allCases.filter { $0 != .calendar && canPerform($0) }
    }
}
