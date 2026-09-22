import PerchCore
import SwiftUI

// MARK: - The countdown, and the call

extension CalendarActivity: IslandActivityPresenting {

    var peekSize: CGSize { CGSize(width: 320, height: 34) }
    var expandedSize: CGSize { CGSize(width: 380, height: isRunning ? 200 : 210) }

    func peekView() -> AnyView {
        AnyView(CalendarPeek(event: event, isRunning: isRunning, controls: controls))
    }

    func expandedView() -> AnyView {
        AnyView(
            CalendarPanel(
                event: event,
                isRunning: isRunning,
                controls: controls,
                queuedCount: queuedCount
            )
        )
    }
}

/// Title on the left of the notch, time on the right.
///
/// The countdown is `Text(timerInterval:)` — rendered by macOS from a date
/// range, with nothing in Perch redrawing it. The focus timer proved the
/// pattern; this is the second module to use it, and the reason neither has
/// a per-second timer (`CLAUDE.md` §5.1).
private struct CalendarPeek: View {

    let event: CalendarEvent
    let isRunning: Bool
    let controls: MeetingControlState

    @Environment(\.notchMetrics) private var metrics

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(event.tint)
                    .frame(width: 7, height: 7)

                Text(event.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 110, alignment: .leading)
            .padding(.leading, 12)

            Spacer(minLength: metrics.collapsedSize.width)

            trailing
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    @ViewBuilder
    private var trailing: some View {
        if isRunning {
            HStack(spacing: 8) {
                if let isMuted = controls.isMuted {
                    Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isMuted ? .red : .white)
                }
                Text("Now")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        } else {
            // Rendered by macOS, not by us.
            Text(timerInterval: Date()...event.startDate, countsDown: true)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private var accessibilityLabel: String {
        isRunning
            ? String(localized: "\(event.title), happening now")
            : String(localized: "\(event.title), starting soon")
    }
}

/// The opened event: what it is, when it is, and the two things you might
/// actually want to do about it.
private struct CalendarPanel: View {

    let event: CalendarEvent
    let isRunning: Bool
    let controls: MeetingControlState
    let queuedCount: Int

    @EnvironmentObject private var modules: ModuleHost

    private var service: CalendarService? { modules.service(CalendarService.self) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider().overlay(.white.opacity(0.12))

            if isRunning {
                meetingControls
            } else {
                joinRow
            }

            if queuedCount > 0 {
                Text("^[\(queuedCount) more event](inflect: true) today")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(event.tint)
                .frame(width: 3, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let service = event.meeting?.service {
                Text(service.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.1), in: Capsule())
            }
        }
    }

    private var subtitle: String {
        let time = event.startDate.formatted(date: .omitted, time: .shortened)
        guard let location = event.location, !location.isEmpty, event.meeting == nil else {
            return event.calendarTitle.isEmpty ? time : "\(time) · \(event.calendarTitle)"
        }
        return "\(time) · \(location)"
    }

    // MARK: - Before it starts

    @ViewBuilder
    private var joinRow: some View {
        if event.meeting != nil {
            Button {
                service?.join(event)
            } label: {
                Label("Join", systemImage: "video.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        } else {
            // TC-CAL-005: no link, no button. Not a disabled one — an
            // explanation, which is the difference between "nothing to press"
            // and "this app is broken".
            Text("No meeting link on this event.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - While it runs

    @ViewBuilder
    private var meetingControls: some View {
        switch controls.availability {
        case .available:
            HStack(spacing: 8) {
                controlButton(
                    title: controls.isMuted == true ? "Unmute" : "Mute",
                    symbol: controls.isMuted == true ? "mic.slash.fill" : "mic.fill",
                    tint: controls.isMuted == true ? .red : .white
                ) { service?.toggleMute() }

                controlButton(
                    title: controls.isCameraOn == true ? "Stop video" : "Start video",
                    symbol: controls.isCameraOn == true ? "video.fill" : "video.slash.fill",
                    tint: controls.isCameraOn == true ? .white : .white.opacity(0.6)
                ) { service?.toggleCamera() }

                controlButton(title: "Leave", symbol: "phone.down.fill", tint: .red) {
                    service?.leaveMeeting()
                }
            }

        case .needsAccessibility:
            // TC-CAL-012. The countdown keeps working; only the controls
            // need this, and it is asked for here rather than at launch.
            unavailable("Mute and leave need Accessibility.") {
                Button("Grant…") { service?.requestAccessibility() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }

        case .notRunning:
            unavailable("\(controls.service?.displayName ?? "The meeting app") is not running.")

        case .unsupported:
            // TC-CAL-011. The vendor moved its menus, or you are not
            // actually in the call. Either way: say so, do not hang.
            unavailable("Controls are not available for this call.")

        case .noMeeting:
            unavailable("Happening now.")
        }
    }

    private func controlButton(
        title: LocalizedStringKey,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }

    private func unavailable(
        _ message: LocalizedStringKey,
        @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            Spacer(minLength: 0)
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Starting now

extension MeetingStartingActivity: IslandActivityPresenting {

    var peekSize: CGSize { CGSize(width: 320, height: 36) }
    var expandedSize: CGSize { CGSize(width: 360, height: 130) }

    func peekView() -> AnyView {
        AnyView(
            HStack(spacing: 8) {
                Image(systemName: "video.badge.waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }

    func expandedView() -> AnyView {
        AnyView(MeetingStartingPanel(event: event))
    }
}

private struct MeetingStartingPanel: View {

    let event: CalendarEvent

    @EnvironmentObject private var modules: ModuleHost

    var body: some View {
        VStack(spacing: 10) {
            Text("Starting now")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)

            Text(event.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if event.meeting != nil {
                Button {
                    modules.service(CalendarService.self)?.join(event)
                } label: {
                    Label("Join", systemImage: "video.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 7)
                        .background(.green.opacity(0.22), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shared

extension CalendarEvent {

    /// The calendar's own colour, or the island's default. Core stores four
    /// numbers because it may not import AppKit; the conversion is here.
    var tint: Color {
        guard let calendarColor else { return .accentColor }
        return Color(
            .sRGB,
            red: calendarColor.red,
            green: calendarColor.green,
            blue: calendarColor.blue,
            opacity: calendarColor.alpha
        )
    }
}
