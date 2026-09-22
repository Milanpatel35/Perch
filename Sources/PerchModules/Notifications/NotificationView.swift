import PerchCore
import SwiftUI

extension NotificationActivity: IslandActivityPresenting {

    var peekSize: CGSize { CGSize(width: 330, height: 36) }
    var expandedSize: CGSize { CGSize(width: 380, height: canReplyNow ? 190 : 150) }

    func peekView() -> AnyView {
        AnyView(NotificationPeek(burst: burst))
    }

    func expandedView() -> AnyView {
        AnyView(NotificationPanel(burst: burst, canReplyNow: canReplyNow))
    }
}

/// App icon and sender on the left, the count on the right.
private struct NotificationPeek: View {

    let burst: NotificationPolicy.Burst

    @Environment(\.notchMetrics) private var metrics

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                icon
                    .frame(width: 16, height: 16)

                Text(burst.latest.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: 120, alignment: .leading)
            .padding(.leading, 12)

            Spacer(minLength: metrics.collapsedSize.width)

            Group {
                if burst.count > 1 {
                    Text("\(burst.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.18), in: Capsule())
                } else {
                    Text(burst.appName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                burst.count > 1
                    ? String(localized: "\(burst.count) from \(burst.appName)")
                    : String(localized: "\(burst.appName): \(burst.latest.title)")
            )
        )
    }

    @ViewBuilder
    private var icon: some View {
        if let image = burst.bundleID.flatMap(NSImage.appIcon(forBundleID:)) {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "bell.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

/// The opened notification: what it says, and the one thing worth doing
/// about it without leaving what you were doing.
private struct NotificationPanel: View {

    let burst: NotificationPolicy.Burst
    let canReplyNow: Bool

    @EnvironmentObject private var modules: ModuleHost
    @State private var draft = ""
    @State private var replyFailed = false
    @FocusState private var isFieldFocused: Bool

    private var service: NotificationService? { modules.service(NotificationService.self) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Text(burst.latest.body)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if canReplyNow {
                replyRow
            } else {
                openRow
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(burst.latest.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(burst.count > 1 ? "\(burst.appName) · \(burst.count)" : burst.appName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    /// The reply field is the one thing in the whole app that takes the
    /// keyboard, and it gives it back the moment it is done — the clipboard
    /// picker set that rule and TC-ISL-008 enforces it.
    private var replyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Reply…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .focused($isFieldFocused)
                    .onSubmit(send)
                    .onAppear {
                        service?.setReplyFieldActive(true)
                        isFieldFocused = true
                    }
                    .onDisappear { service?.setReplyFieldActive(false) }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(draft.isEmpty ? .white.opacity(0.3) : .white)
                }
                .buttonStyle(.plain)
                .disabled(draft.isEmpty)
                .accessibilityLabel(Text("Send reply"))
            }

            if replyFailed {
                // TC-NTF-011. The banner went, or its field moved. Say so.
                Text("That banner has gone. Open \(burst.appName) instead.")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange.opacity(0.9))
            }
        }
    }

    private var openRow: some View {
        Button {
            service?.open()
        } label: {
            Label("Open \(burst.appName)", systemImage: "arrow.up.forward.app")
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func send() {
        guard !draft.isEmpty else { return }

        if service?.reply(with: draft) == true {
            draft = ""
            replyFailed = false
        } else {
            replyFailed = true
        }
    }
}

extension NSImage {

    /// The icon of an installed app, by bundle identifier.
    ///
    /// `nil` for an app that is not installed — which happens for a
    /// notification posted by something since removed, and draws a bell
    /// rather than the generic document icon that caught us out in #14.
    static func appIcon(forBundleID bundleID: String) -> NSImage? {
        guard
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
