import CoreAudio
import PerchCore
import SwiftUI

/// The bars beside the notch.
///
/// **What this is honestly showing.** It reflects *playback*, not amplitude.
/// Reading the actual signal would mean capturing system audio, which on
/// macOS means Screen Recording permission and a capture session running for
/// the whole time music plays — a permission prompt and a constant cost, for
/// decoration. Perch does not do that, and says so rather than implying a
/// spectrum analyser.
///
/// It stops dead on pause: no timeline, no view, no wakeups (TC-MED-002).
struct Visualiser: View {

    let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barCount = 4
    private let barWidth: CGFloat = 2.5
    private let spacing: CGFloat = 2.5

    var body: some View {
        Group {
            if isPlaying && !reduceMotion {
                TimelineView(.animation) { context in
                    bars(at: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                // Paused, or motion is not wanted. A static, even row —
                // present, but saying nothing is happening.
                bars(at: nil)
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    private func bars(at time: TimeInterval?) -> some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: barWidth, height: height(of: index, at: time))
            }
        }
    }

    private func height(of index: Int, at time: TimeInterval?) -> CGFloat {
        guard let time else { return 4 }

        // Each bar runs at its own rate and offset, so the row never reads as
        // a single wave moving across.
        let rate = 3.1 + (Double(index) * 0.73)
        let phase = Double(index) * 1.7
        let wave = (sin((time * rate) + phase) + 1) / 2
        return 3 + CGFloat(wave) * 11
    }
}

/// The seek bar.
///
/// Draws from `PlaybackProgress`, which knows its own rate — so a paused
/// track is a constant and needs no clock at all, and a playing one only ticks
/// while the expanded island is actually on screen.
struct Scrubber: View {

    let progress: PlaybackProgress
    @Binding var scrubbing: Double?
    let onSeek: (Duration) -> Void

    var body: some View {
        VStack(spacing: 4) {
            if progress.isAdvancing && scrubbing == nil {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    track(fraction: fraction(at: context.date))
                }
            } else {
                track(fraction: fraction(at: .now))
            }

            HStack {
                Text(timestamp(elapsedFraction))
                Spacer()
                Text(progress.duration.map(timeString) ?? "--:--")
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var elapsedFraction: Duration {
        guard let duration = progress.duration else {
            return progress.elapsed(at: .now)
        }
        return duration * (fraction(at: .now) ?? 0)
    }

    private func fraction(at date: Date) -> Double? {
        scrubbing ?? progress.fraction(at: date)
    }

    private func track(fraction: Double?) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: width * CGFloat(fraction ?? 0))
            }
            .frame(height: 4)
            .contentShape(Rectangle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard progress.duration != nil else { return }
                        scrubbing = min(1, max(0, value.location.x / width))
                    }
                    .onEnded { _ in
                        defer { scrubbing = nil }
                        guard let duration = progress.duration,
                            let target = scrubbing
                        else { return }
                        onSeek(duration * target)
                    }
            )
        }
        .frame(height: 12)
        .accessibilityLabel(Text("Playback position"))
        .accessibilityValue(Text(timestamp(elapsedFraction)))
    }

    /// A live stream has no length, so it shows elapsed time rather than a
    /// position within something that has no end (TC-MED-004's cousin).
    private func timestamp(_ duration: Duration) -> String {
        timeString(duration)
    }

    private func timeString(_ duration: Duration) -> String {
        let total = Int(duration.seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

/// The output-device picker — route without opening Control Centre.
///
/// The device list is read when the menu opens and thrown away when it
/// closes. Nothing is observed in between, which is the difference between a
/// picker and a background service.
struct OutputDeviceButton: View {

    @State private var devices: [AudioOutputService.Device] = []
    @State private var currentID: AudioDeviceID?

    var body: some View {
        Menu {
            if devices.isEmpty {
                Text("No output devices")
            }
            ForEach(devices) { device in
                Button {
                    AudioOutputService.setOutputDevice(device.id)
                    reload()
                } label: {
                    Label(device.name, systemImage: device.symbolName)
                    if device.id == currentID {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Image(systemName: currentSymbol)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onAppear { reload() }
        .accessibilityLabel(Text("Audio output device"))
    }

    private var currentSymbol: String {
        devices.first { $0.id == currentID }?.symbolName ?? "airplayaudio"
    }

    private func reload() {
        devices = AudioOutputService.outputDevices()
        currentID = AudioOutputService.currentOutputDeviceID
    }
}
