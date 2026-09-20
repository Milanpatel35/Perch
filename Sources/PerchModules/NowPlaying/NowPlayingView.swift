import Defaults
import PerchCore
import SwiftUI

extension NowPlayingActivity: IslandActivityPresenting {

    /// The peek is laid out *around* the cutout: artwork on one side, the
    /// visualiser on the other, the hardware in between. The gap is the
    /// notch's own width, read from the environment — never a constant.
    var peekSize: CGSize { CGSize(width: 320, height: 34) }

    var expandedSize: CGSize { CGSize(width: 420, height: 196) }

    func peekView() -> AnyView {
        AnyView(NowPlayingPeek(snapshot: snapshot))
    }

    func expandedView() -> AnyView {
        AnyView(NowPlayingExpanded(snapshot: snapshot))
    }
}

// MARK: - Peek

private struct NowPlayingPeek: View {

    let snapshot: NowPlayingSnapshot

    @Environment(\.notchMetrics) private var metrics
    @Default(.nowPlayingVisualiser) private var showVisualiser

    var body: some View {
        HStack(spacing: 0) {
            Artwork(data: snapshot.artwork, size: 24)
                .padding(.leading, 10)

            // The hardware. Nothing is drawn here; the island simply is the
            // cutout at this width.
            Spacer(minLength: metrics.collapsedSize.width)

            Group {
                if showVisualiser {
                    Visualiser(isPlaying: snapshot.isPlaying)
                } else {
                    Image(systemName: snapshot.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: 22)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(snapshot.title) — \(snapshot.artist)"))
    }
}

// MARK: - Expanded

private struct NowPlayingExpanded: View {

    let snapshot: NowPlayingSnapshot

    @EnvironmentObject private var modules: ModuleHost
    @State private var scrubbing: Double?

    private var service: NowPlayingService? {
        modules.service(NowPlayingService.self)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Artwork(data: snapshot.artwork, size: 56)

                VStack(alignment: .leading, spacing: 3) {
                    MarqueeText(snapshot.title, weight: .semibold)
                    MarqueeText(
                        snapshot.artist.isEmpty ? snapshot.album : snapshot.artist,
                        weight: .regular
                    )
                    .foregroundStyle(.white.opacity(0.6))

                    if let name = snapshot.sourceName {
                        Button {
                            service?.revealSource()
                        } label: {
                            Text(name)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Bring the playing app to the front"))
                    }
                }

                Spacer(minLength: 0)

                OutputDeviceButton()
            }

            Scrubber(
                progress: snapshot.progress,
                scrubbing: $scrubbing,
                onSeek: { service?.seek(to: $0) }
            )

            HStack(spacing: 26) {
                TransportButton(symbol: "backward.fill") { service?.previousTrack() }
                TransportButton(
                    symbol: snapshot.isPlaying ? "pause.fill" : "play.fill",
                    size: 20
                ) {
                    service?.togglePlayPause()
                }
                TransportButton(symbol: "forward.fill") { service?.nextTrack() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Trackpad swipe over the island skips (`docs/FEATURES.md` §1).
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard Defaults[.swipeToSkip] else { return }
                    guard abs(value.translation.width) > abs(value.translation.height)
                    else { return }
                    if value.translation.width < 0 {
                        service?.nextTrack()
                    } else {
                        service?.previousTrack()
                    }
                }
        )
    }
}

// MARK: - Pieces

private struct TransportButton: View {

    let symbol: String
    var size: CGFloat = 15
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(.white)
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var label: String {
        switch symbol {
        case "backward.fill": String(localized: "Previous track")
        case "forward.fill": String(localized: "Next track")
        case "pause.fill": String(localized: "Pause")
        default: String(localized: "Play")
        }
    }
}

private struct Artwork: View {

    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // A source with no artwork gets a placeholder, never a blank
                // frame and never a crash (TC-MED-004).
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}
