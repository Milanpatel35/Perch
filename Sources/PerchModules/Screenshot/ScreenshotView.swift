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
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
        } trailing: {
            Text(line)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(line))
    }

    private var symbol: String {
        switch outcome {
        case .saved: "camera.viewfinder"
        case .copiedImage: "doc.on.clipboard.fill"
        case .copiedText: "text.viewfinder"
        case .noText: "text.badge.xmark"
        case .failed, .needsPermission: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch outcome {
        case .failed, .needsPermission, .noText: .orange
        case .saved, .copiedImage, .copiedText: .white
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
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .accessibilityHidden(true)

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
        Button {
            service.perform(action)
        } label: {
            // Five buttons share one row of the home surface. A `Label`
            // spaces its icon too generously for that, and "Window" and
            // "Screen" were cut to "Wind…" and "Scre…".
            HStack(spacing: 3) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.14)))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(service.isCapturing)
        .help(Text(Self.help(for: action)))
    }

    private static func help(for action: ScreenshotAction) -> String {
        switch action {
        case .save(.area): String(localized: "Capture an area")
        case .save(.window): String(localized: "Capture a window")
        case .save(.screen): String(localized: "Capture this screen")
        case .copyText: String(localized: "Copy the text in an area")
        case .pin: String(localized: "Pin an area above everything")
        }
    }
}

public extension ModuleHost {

    /// The capture row, or nothing when the module is off.
    @MainActor
    func screenshotTile() -> AnyView? {
        guard let service = service(ScreenshotService.self), service.isActive else { return nil }
        return AnyView(ScreenshotTile(service: service))
    }
}
