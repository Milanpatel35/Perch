import PerchCore
import SwiftUI

// MARK: - The running session

extension FocusActivity: IslandActivityPresenting {

    var peekSize: CGSize { CGSize(width: 300, height: 34) }
    var expandedSize: CGSize { CGSize(width: 340, height: 180) }

    func peekView() -> AnyView {
        AnyView(FocusPeek(timer: timer))
    }

    func expandedView() -> AnyView {
        AnyView(
            FocusPanel(
                timer: timer,
                sessionsToday: sessionsToday,
                streakDays: streakDays
            )
        )
    }
}

/// The countdown, beside the notch.
///
/// **`Text(timerInterval:)` is the whole trick.** macOS renders a live
/// countdown from a date range without anything in Perch redrawing it, so
/// there is no per-second timer here or anywhere else in the module
/// (`CLAUDE.md` §5.1). It also means the countdown stops existing when the
/// island is not showing it, which is the same rule the system stats sampler
/// will have to follow.
private struct FocusPeek: View {

    let timer: PomodoroTimer

    @Environment(\.notchMetrics) private var metrics

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: timer.phase?.symbolName ?? "timer")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(timer.phase?.tint ?? .white)
                .frame(width: 20)
                .padding(.leading, 12)

            Spacer(minLength: metrics.collapsedSize.width)

            countdown
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    @ViewBuilder
    private var countdown: some View {
        HStack(spacing: 6) {
            if timer.isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }

            if let endsAt = timer.endsAt, timer.isRunning {
                // Rendered by macOS, not by us.
                Text(timerInterval: Date()...endsAt, countsDown: true)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 44, alignment: .trailing)
            } else {
                Text(timer.remainingClock)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    private var accessibilityLabel: String {
        let phase = timer.phase?.displayName ?? "Focus"
        return timer.isPaused
            ? "\(phase) paused, \(timer.remainingClock) left"
            : "\(phase), \(timer.remainingClock) left"
    }
}

/// The opened session: a ring, the controls, and what it adds up to.
private struct FocusPanel: View {

    let timer: PomodoroTimer
    let sessionsToday: Int
    let streakDays: Int

    @EnvironmentObject private var modules: ModuleHost

    private var service: FocusService? { modules.service(FocusService.self) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ring
                VStack(alignment: .leading, spacing: 3) {
                    Text(timer.phase?.displayName ?? "Focus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(timer.isPaused ? "Paused" : "Running")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }

            controls

            Divider().overlay(Color.white.opacity(0.12))

            HStack(spacing: 16) {
                FocusCount(label: "Today", value: "\(sessionsToday)")
                FocusCount(label: "Streak", value: streakDays == 1 ? "1 day" : "\(streakDays) days")
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Focus timer"))
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 4)
            Circle()
                .trim(from: 0, to: timer.progress(at: Date()) ?? 0)
                .stroke(
                    timer.phase?.tint ?? .white,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text(timer.remainingClock)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(width: 58, height: 58)
        .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(timer.isRunning ? "Pause" : "Start") {
                service?.toggle()
            }
            .buttonStyle(FocusButtonStyle(isProminent: true))

            Button("Stop") {
                service?.stop()
            }
            .buttonStyle(FocusButtonStyle(isProminent: false))

            Spacer(minLength: 0)
        }
    }
}

// MARK: - The finished session

extension FocusFinishedActivity: IslandActivityPresenting {

    var peekSize: CGSize { CGSize(width: 320, height: 34) }
    var expandedSize: CGSize { CGSize(width: 340, height: 150) }

    func peekView() -> AnyView {
        AnyView(
            HStack(spacing: 0) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(finished.tint)
                    .padding(.leading, 12)
                Spacer(minLength: 0)
                Text("\(finished.displayName) done")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.trailing, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(finished.displayName) finished"))
        )
    }

    func expandedView() -> AnyView {
        AnyView(
            FocusFinishedPanel(
                finished: finished,
                next: next,
                sessionsToday: sessionsToday,
                streakDays: streakDays
            )
        )
    }
}

private struct FocusFinishedPanel: View {

    let finished: PomodoroTimer.Phase
    let next: PomodoroTimer.Phase
    let sessionsToday: Int
    let streakDays: Int

    @EnvironmentObject private var modules: ModuleHost

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(finished.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(finished.displayName) finished")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(next.displayName) is next")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button("Start \(next.displayName.lowercased())") {
                    modules.service(FocusService.self)?.start(next)
                }
                .buttonStyle(FocusButtonStyle(isProminent: true))

                Button("Not now") {
                    modules.service(FocusService.self)?.stop()
                }
                .buttonStyle(FocusButtonStyle(isProminent: false))

                Spacer(minLength: 0)
            }

            Divider().overlay(Color.white.opacity(0.12))

            HStack(spacing: 16) {
                FocusCount(label: "Today", value: "\(sessionsToday)")
                FocusCount(label: "Streak", value: streakDays == 1 ? "1 day" : "\(streakDays) days")
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(finished.displayName) finished"))
    }
}

// MARK: - Parts

private struct FocusCount: View {

    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(label): \(value)"))
    }
}

private struct FocusButtonStyle: ButtonStyle {

    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isProminent ? Color.black : Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    isProminent
                        ? Color.white.opacity(configuration.isPressed ? 0.75 : 1)
                        : Color.white.opacity(configuration.isPressed ? 0.28 : 0.16)
                )
            )
    }
}

extension PomodoroTimer {

    /// "24:58". Used where a live countdown is not appropriate — a paused
    /// timer, and the ring's centre.
    var remainingClock: String {
        let seconds = Int((remaining(at: Date())?.seconds ?? 0).rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension PomodoroTimer.Phase {

    var symbolName: String {
        switch self {
        case .work: "timer"
        case .shortBreak: "cup.and.saucer.fill"
        case .longBreak: "figure.walk"
        }
    }

    var tint: Color {
        switch self {
        case .work: .orange
        case .shortBreak, .longBreak: .green
        }
    }
}
