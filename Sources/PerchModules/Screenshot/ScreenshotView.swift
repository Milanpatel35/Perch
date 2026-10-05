import PerchCore
import SwiftUI

// MARK: - The outcome

extension ScreenshotActivity: IslandActivityPresenting {

    var peekSize: CGSize { CGSize(width: 360, height: 34) }

    func peekView() -> AnyView {
        AnyView(ScreenshotPeek(outcome: outcome))
    }

    /// Not expandable: the peek is the whole message.
    func expandedView() -> AnyView {
        AnyView(ScreenshotPeek(outcome: outcome))
    }
}

private struct ScreenshotPeek: View {

    let outcome: ScreenshotActivity.Outcome

    var body: some View {
        NotchFlanks {
            leading
        } trailing: {
            Text(line)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(line))
    }

    /// A picked colour shows the colour itself; everything else an icon.
    @ViewBuilder
    private var leading: some View {
        if case .copiedColor(_, let color) = outcome {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: color.red, green: color.green, blue: color.blue))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.4)))
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
        }
    }

    private var symbol: String {
        switch outcome {
        case .saved: "camera.viewfinder"
        case .copiedImage: "doc.on.clipboard.fill"
        case .copiedText: "text.viewfinder"
        case .noText: "text.badge.xmark"
        case .failed, .needsPermission: "exclamationmark.triangle.fill"
        case .copiedColor: "eyedropper"
        case .measured: "ruler"
        case .openedLink: "safari"
        case .copiedCode: "qrcode"
        case .noCode: "qrcode.viewfinder"
        }
    }

    private var tint: Color {
        switch outcome {
        case .failed, .needsPermission, .noText, .noCode: .orange
        default: .white
        }
    }

    private var line: String {
        switch outcome {
        case .saved(_, let folder):
            String(localized: "Saved to \(folder)")
        case .copiedImage:
            String(localized: "Screenshot copied")
        case .copiedText(let characters):
            String(localized: "\(characters) characters copied")
        case .noText:
            String(localized: "No text found")
        case .failed(let reason):
            reason
        case .needsPermission:
            String(localized: "Allow Screen Recording for Perch")
        case .copiedColor(let text, _):
            String(localized: "\(text) copied")
        case .measured(let label):
            String(localized: "\(label) copied")
        case .openedLink(let host):
            String(localized: "Opened \(host)")
        case .copiedCode:
            String(localized: "Code copied")
        case .noCode:
            String(localized: "No code found")
        }
    }
}

// MARK: - The buttons on the home surface

/// One row: three ways to take a screenshot, then text and pin.
///
/// On the home surface rather than an activity of its own, like the
/// Shortcuts favourites: a screenshot is something you reach for, and the
/// home surface is where the island keeps those.
struct ScreenshotTile: View {

    @ObservedObject var service: ScreenshotService

    var body: some View {
        HStack(spacing: 5) {
            button(.save(.area), "Area", "rectangle.dashed")
            button(.save(.window), "Window", "macwindow")
            button(.save(.screen), "Screen", "display")
            button(.copyText, "Text", "text.viewfinder")
            button(.pin, "Pin", "pin")

            Spacer(minLength: 0)
        }
    }

    private func button(
        _ action: ScreenshotAction,
        _ title: LocalizedStringKey,
        _ symbol: String
    ) -> some View {
        HomeRowButton(
            title: title, symbol: symbol, help: Self.help(for: action), key: Self.key(for: action)
        ) {
            service.perform(action)
        }
        .disabled(service.isCapturing)
    }

    static func key(for action: ScreenshotAction) -> Character {
        let home: HomeAction =
            switch action {
            case .save(.area): .captureArea
            case .save(.window): .captureWindow
            case .save(.screen): .captureScreen
            case .copyText: .copyText
            case .pin: .pin
            case .measure: .measure
            case .scanCode: .scan
            }
        return HomeKeymap.key(for: home)
    }

    static func help(for action: ScreenshotAction) -> String {
        switch action {
        case .save(.area): String(localized: "Capture an area")
        case .save(.window): String(localized: "Capture a window")
        case .save(.screen): String(localized: "Capture this screen")
        case .copyText: String(localized: "Copy the text in an area")
        case .pin: String(localized: "Pin an area above everything")
        case .measure: String(localized: "Copy an area’s size in points")
        case .scanCode: String(localized: "Read a QR code or barcode")
        }
    }
}

/// The second row: tools that read the screen rather than keep it.
struct ScreenshotToolsTile: View {

    @ObservedObject var service: ScreenshotService

    private static func help(_ action: ScreenshotAction) -> String {
        ScreenshotTile.help(for: action)
    }

    var body: some View {
        HStack(spacing: 5) {
            HomeRowButton(
                title: "Colour", symbol: "eyedropper",
                help: String(localized: "Copy a colour from the screen"),
                key: HomeKeymap.key(for: .colour)
            ) {
                service.pickColor()
            }
            .disabled(service.isCapturing)
            HomeRowButton(
                title: "Measure", symbol: "ruler", help: Self.help(.measure),
                key: ScreenshotTile.key(for: .measure)
            ) {
                service.perform(.measure)
            }
            .disabled(service.isCapturing)
            HomeRowButton(
                title: "Scan", symbol: "qrcode.viewfinder", help: Self.help(.scanCode),
                key: ScreenshotTile.key(for: .scanCode)
            ) {
                service.perform(.scanCode)
            }
            .disabled(service.isCapturing)

            Spacer(minLength: 0)
        }
    }
}

public extension ModuleHost {

    /// The tools row, or nothing when the module is off.
    @MainActor
    func screenshotToolsTile() -> AnyView? {
        guard let service = service(ScreenshotService.self), service.isActive else { return nil }
        return AnyView(ScreenshotToolsTile(service: service))
    }

    /// The capture row, or nothing when the module is off.
    @MainActor
    func screenshotTile() -> AnyView? {
        guard let service = service(ScreenshotService.self), service.isActive else { return nil }
        return AnyView(ScreenshotTile(service: service))
    }
}
