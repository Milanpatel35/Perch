import AppKit
import PerchCore
import SwiftUI

/// Floats captures above everything, as reference cards.
@MainActor
protocol ScreenshotPinning {
    /// Reads the image at `url` into memory and pins it. Returns false when
    /// there was no image to read. The file is the caller's to delete.
    func pin(imageAt url: URL) -> Bool

    /// How many are up.
    var count: Int { get }

    /// Takes every one down. Called when the module switches off.
    func closeAll()
}

/// Owns the pinned cards.
@MainActor
final class ScreenshotPinBoard: ScreenshotPinning {

    private var panels: [ScreenshotPinPanel] = []

    var count: Int { panels.count }

    func pin(imageAt url: URL) -> Bool {
        guard let image = NSImage(contentsOf: url) else { return false }

        let panel = ScreenshotPinPanel(image: image)
        panel.onClose = { [weak self, weak panel] in
            guard let panel else { return }
            panel.orderOut(nil)
            self?.panels.removeAll { $0 === panel }
        }
        panel.show(after: panels.last)
        panels.append(panel)
        return true
    }

    func closeAll() {
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }
}

/// One pinned capture.
///
/// The third window in Perch that is not `IslandPanel` (`CLAUDE.md` §9),
/// for the camera pill's reasons: a pin has to outlive the island closing,
/// go anywhere on screen, and stay while you work beside it — comparing a
/// design with the build, a figure with the table it came from
/// (TC-SCR-010). Non-activating, so clicking it never takes focus from the
/// app you are comparing it with.
@MainActor
final class ScreenshotPinPanel: NSPanel {

    var onClose: (() -> Void)?

    /// The longest side a card opens at. A full-screen capture pinned at
    /// its own size would cover the screen it is meant to sit beside.
    private static let maximumSide: CGFloat = 480

    init(image: NSImage) {
        let size = Self.size(for: image.size)

        super.init(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false

        contentView = FirstMouseHostingView(
            rootView: ScreenshotPinView(image: image) { [weak self] in self?.onClose?() }
        )
    }

    /// Key, so its close button takes a click; never main, so the app beside
    /// it keeps its title bar active.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Opens under the notch, where the capture was asked for, and steps
    /// down and right from the last card so a run of pins does not stack
    /// into one.
    func show(after previous: NSWindow?) {
        if let previous {
            setFrameOrigin(CGPoint(x: previous.frame.minX + 24, y: previous.frame.minY - 24))
        } else if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            setFrameOrigin(
                CGPoint(x: visible.midX - frame.width / 2, y: visible.maxY - frame.height - 12))
        }
        orderFrontRegardless()
    }

    static func size(for image: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return CGSize(width: 200, height: 200) }
        let scale = min(1, maximumSide / max(image.width, image.height))
        return CGSize(
            width: (image.width * scale).rounded(), height: (image.height * scale).rounded())
    }
}

/// A pinned card answers its first click. A non-activating panel in a
/// background app otherwise swallows it, and the close button reads as dead
/// — the first-run window's lesson (TC-ONB-006).
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct ScreenshotPinView: View {

    let image: NSImage
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.15))
            )
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .accessibilityLabel(Text("Unpin"))
                }
            }
            .onHover { isHovering = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Pinned screenshot"))
    }
}
