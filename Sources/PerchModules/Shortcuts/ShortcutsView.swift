import PerchCore
import SwiftUI

// MARK: - Messages and runs

extension ShortcutsActivity: IslandActivityPresenting {

    var peekSize: CGSize { CGSize(width: 340, height: 34) }
    var expandedSize: CGSize { CGSize(width: 380, height: 96) }

    func peekView() -> AnyView {
        AnyView(ShortcutsPeek(kind: kind))
    }

    /// Only a message with a body opens — the body is what there is to see.
    func expandedView() -> AnyView {
        AnyView(ShortcutsMessage(kind: kind))
    }
}

private struct ShortcutsPeek: View {

    let kind: ShortcutsActivity.Kind

    @Environment(\.notchMetrics) private var metrics

    var body: some View {
        HStack(spacing: 0) {
            symbol
                .font(.system(size: 13, weight: .medium))
                .padding(.leading, 14)

            Spacer(minLength: metrics.collapsedSize.width)

            Text(line)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(line))
    }

    @ViewBuilder
    private var symbol: some View {
        switch kind {
        case .message:
            Image(systemName: "text.bubble.fill").foregroundStyle(.white)
        case .running:
            // The system's own indeterminate spinner, which honours Reduce
            // Motion by itself.
            ProgressView().controlSize(.small).tint(.white)
        case .finished(_, .succeeded):
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .finished(_, .failed):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var line: String {
        switch kind {
        case .message(let message):
            message.title
        case .running(let name):
            String(localized: "Running \(name)…")
        case .finished(let name, .succeeded(let output)):
            output ?? String(localized: "\(name) finished")
        case .finished(let name, .failed(let reason)):
            "\(name): \(reason)"
        }
    }
}

private struct ShortcutsMessage: View {

    let kind: ShortcutsActivity.Kind

    var body: some View {
        if case .message(let message) = kind {
            VStack(alignment: .leading, spacing: 6) {
                Text(message.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let body = message.body {
                    Text(body)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 34)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Favourites on the home surface

/// One row of buttons, one per favourite (`docs/FEATURES.md` §13).
///
/// On the home surface rather than an activity of its own: favourites are
/// something you reach for, not something that happens, and the home
/// surface is where the island keeps things you reach for.
struct ShortcutsTile: View {

    @ObservedObject var service: ShortcutsService

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.2.layers.3d.fill")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .accessibilityHidden(true)

            ForEach(service.favourites.names, id: \.self) { name in
                Button {
                    service.run(name)
                } label: {
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.14)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(service.runningName != nil)
                .opacity(service.runningName == nil || service.runningName == name ? 1 : 0.5)
                .accessibilityLabel(Text("Run \(name)"))
            }

            Spacer(minLength: 0)
        }
    }
}

public extension ModuleHost {

    /// The favourites row, or nothing when the module is off or has no
    /// favourites — so an empty row never takes space on the home surface.
    @MainActor
    func shortcutsTile() -> AnyView? {
        guard let service = service(ShortcutsService.self),
            service.isActive,
            !service.favourites.names.isEmpty
        else { return nil }
        return AnyView(ShortcutsTile(service: service))
    }

    /// Where the app sends every `perch://` URL. Returns false — and does
    /// nothing at all — when the Shortcuts module is off, which is what
    /// "switched off" has to mean for a URL scheme.
    @MainActor
    @discardableResult
    func handlePerchURL(_ url: URL) -> Bool {
        service(ShortcutsService.self)?.handle(url) ?? false
    }
}
