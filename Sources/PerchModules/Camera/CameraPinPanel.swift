import AppKit
import PerchCore
import SwiftUI

/// The floating pill the preview detaches into.
///
/// The one place in Perch that is allowed a window of its own rather than
/// `IslandPanel` (`CLAUDE.md` §9). The reason is specific: a pinned preview
/// has to survive the island collapsing, has to be draggable anywhere on
/// screen, and has to stay up while you present — three things the island's
/// own panel is deliberately not (TC-CAM-005).
///
/// It borrows the island's rules where they still apply: non-activating, so
/// clicking it does not take focus from what you are presenting, and joined
/// to every Space so a Space switch does not lose it.
@MainActor
final class CameraPinPanel: NSPanel {

    var onMove: ((CGPoint) -> Void)?
    var onClose: (() -> Void)?

    private let session: CameraSession
    private var presentation: CameraPresentation
    private var moveObserver: NSObjectProtocol?

    init(session: CameraSession, presentation: CameraPresentation) {
        self.session = session
        self.presentation = presentation

        super.init(
            contentRect: CGRect(origin: .zero, size: presentation.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false

        contentView = NSHostingView(
            rootView: CameraPinView(
                session: session,
                presentation: presentation,
                onClose: { [weak self] in self?.onClose?() }
            )
        )

        observeMoves()
    }

    /// Borderless panels are not key by default, and this one must be able
    /// to become key for its close button to take a click — but never main,
    /// so the app you are presenting keeps its title bar active.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show() {
        setFrame(CGRect(origin: origin(), size: presentation.size), display: true)
        orderFrontRegardless()
    }

    func update(presentation: CameraPresentation) {
        self.presentation = presentation

        contentView = NSHostingView(
            rootView: CameraPinView(
                session: session,
                presentation: presentation,
                onClose: { [weak self] in self?.onClose?() }
            )
        )
        setContentSize(presentation.size)
        alphaValue = presentation.opacity
    }

    func close(andNotify: Bool = false) {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
        moveObserver = nil

        orderOut(nil)
        if andNotify { onClose?() }
    }

    /// `windowDidMove` belongs to `NSWindowDelegate`, not to `NSWindow`.
    /// The notification is the same event without needing a delegate the
    /// panel would then have to own.
    private func observeMoves() {
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onMove?(self.frame.origin)
            }
        }
    }

    /// Where it opens the first time: centred under the notch, which is
    /// where it was a moment ago. Anywhere else looks like it jumped.
    private func origin() -> CGPoint {
        if let remembered = presentation.pinnedOrigin { return remembered }

        guard let screen = NSScreen.main else { return .zero }
        let frame = screen.visibleFrame

        return CGPoint(
            x: frame.midX - presentation.size.width / 2,
            y: frame.maxY - presentation.size.height - 12
        )
    }
}

/// What the pill draws: the preview, and a close button that only appears
/// when the pointer is over it.
private struct CameraPinView: View {

    let session: CameraSession
    let presentation: CameraPresentation
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        CameraPreviewLayer(session: session, isMirrored: presentation.isMirrored)
            .frame(width: presentation.size.width, height: presentation.size.height)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: presentation.size.height * presentation.shape.cornerFraction,
                    style: .continuous
                )
            )
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.white, .black.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .accessibilityLabel(Text("Unpin the camera"))
                }
            }
            .opacity(presentation.opacity)
            .onHover { isHovering = $0 }
    }
}
