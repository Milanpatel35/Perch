import AVFoundation
import AppKit
import PerchCore
import SwiftUI

extension CameraActivity: IslandActivityPresenting {

    var peekSize: CGSize { CGSize(width: 300, height: 34) }

    var expandedSize: CGSize {
        CGSize(
            width: max(presentation.size.width + 32, 320),
            height: presentation.size.height + 78
        )
    }

    func peekView() -> AnyView {
        AnyView(CameraPeek(reason: reason))
    }

    func expandedView() -> AnyView {
        AnyView(
            CameraPanel(
                presentation: presentation,
                deviceName: deviceName,
                reason: reason,
                failure: failure
            )
        )
    }
}

/// The collapsed state says the camera is on and why. It draws no frames —
/// a preview squeezed into the width of a notch is not a preview, and
/// rendering one there would mean the device stayed open for a peek nobody
/// asked for.
private struct CameraPeek: View {

    let reason: CameraActivity.Reason

    @Environment(\.notchMetrics) private var metrics

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: 120, alignment: .leading)
            .padding(.leading, 12)

            Spacer(minLength: metrics.collapsedSize.width)

            Image(systemName: "camera.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
    }

    private var label: String {
        switch reason {
        case .opened: String(localized: "Camera")
        case .preCallCheck: String(localized: "Before you join")
        }
    }
}

/// The preview itself, with the four things worth reaching for.
private struct CameraPanel: View {

    let presentation: CameraPresentation
    let deviceName: String
    let reason: CameraActivity.Reason
    let failure: CameraSession.Failure?

    @EnvironmentObject private var modules: ModuleHost

    private var service: CameraService? { modules.service(CameraService.self) }

    var body: some View {
        VStack(spacing: 8) {
            if let failure {
                explanation(for: failure)
            } else {
                preview
            }

            controls
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var preview: some View {
        Group {
            if let session = service?.session {
                CameraPreviewLayer(session: session, isMirrored: presentation.isMirrored)
            } else {
                Color.black
            }
        }
        .frame(width: presentation.size.width, height: presentation.size.height)
        .clipShape(
            RoundedRectangle(
                cornerRadius: presentation.size.height * presentation.shape.cornerFraction,
                style: .continuous
            )
        )
        .opacity(presentation.opacity)
        .overlay(alignment: .top) {
            if case .preCallCheck(let title) = reason {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(.top, 6)
            }
        }
        // Scroll to resize while hovering (`docs/FEATURES.md` §9). The
        // clamping is in Core, so a flick cannot lose the preview.
        .onContinuousHover { phase in
            guard case .active = phase else { return }
        }
        .modifier(ScrollToResize { service?.resize(byScroll: $0) })
        .accessibilityLabel(Text("Camera preview"))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            control("camera.rotate", label: "Mirror", isOn: presentation.isMirrored) {
                service?.toggleMirror()
            }

            Menu {
                ForEach(CameraPresentation.Shape.allCases, id: \.self) { shape in
                    Button(shape.displayName) { service?.setShape(shape) }
                }
            } label: {
                Image(systemName: "square.on.circle")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .foregroundStyle(.white.opacity(0.8))
            .accessibilityLabel(Text("Shape"))

            control("pin.fill", label: "Pin", isOn: presentation.isPinned) {
                service?.togglePin()
            }

            control("camera.shutter.button", label: "Snapshot", isOn: false) {
                service?.snapshot()
            }

            Spacer(minLength: 0)

            if !deviceName.isEmpty {
                Text(deviceName)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
    }

    private func control(
        _ symbol: String,
        label: LocalizedStringKey,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOn ? .white : .white.opacity(0.55))
                .frame(width: 22, height: 22)
                .background(
                    isOn ? .white.opacity(0.16) : .clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    /// A camera that silently does not open reads as a broken app. Every
    /// failure says what happened and what to do about it.
    @ViewBuilder
    private func explanation(for failure: CameraSession.Failure) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "video.slash")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.5))

            Text(message(for: failure))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            if failure == .denied {
                Button("Open Privacy Settings…") {
                    let url = URL(string: Self.privacyPane)
                    if let url { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
            }
        }
        .frame(height: presentation.size.height)
    }

    private static let privacyPane =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"

    private func message(for failure: CameraSession.Failure) -> String {
        switch failure {
        case .denied:
            String(localized: "Camera access is off. Everything else in Perch still works.")
        case .noDevice:
            String(localized: "No camera is connected.")
        case .inUse:
            String(localized: "Another app is using the camera.")
        case .unavailable:
            String(localized: "The camera would not start.")
        }
    }
}

/// Scroll-to-resize, as its own modifier so both the island preview and the
/// pinned pill can use it and cannot drift apart.
private struct ScrollToResize: ViewModifier {

    let onScroll: (Double) -> Void

    init(_ onScroll: @escaping (Double) -> Void) {
        self.onScroll = onScroll
    }

    func body(content: Content) -> some View {
        content.background(ScrollCatcher(onScroll: onScroll))
    }
}

/// `NSView` rather than a SwiftUI gesture: SwiftUI has no scroll-wheel
/// gesture on macOS that does not also scroll something.
private struct ScrollCatcher: NSViewRepresentable {

    let onScroll: (Double) -> Void

    func makeNSView(context: Context) -> ScrollCatchingView {
        let view = ScrollCatchingView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: ScrollCatchingView, context: Context) {
        view.onScroll = onScroll
    }
}

final class ScrollCatchingView: NSView {

    var onScroll: ((Double) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScroll?(Double(event.scrollingDeltaY))
    }
}

/// The preview layer itself.
///
/// `AVCaptureVideoPreviewLayer` renders straight from the session and hands
/// nothing back — there is no sample-buffer delegate here, which is what
/// makes TC-CAM-007 and TC-CAM-008 true by construction rather than by
/// discipline.
struct CameraPreviewLayer: NSViewRepresentable {

    let session: CameraSession
    let isMirrored: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer = CALayer()
        attach(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        attach(to: view)
    }

    private func attach(to view: NSView) {
        guard let capture = session.session else {
            view.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
            return
        }

        let existing = view.layer?.sublayers?
            .compactMap { $0 as? AVCaptureVideoPreviewLayer }
            .first

        let layer = existing ?? AVCaptureVideoPreviewLayer(session: capture)
        layer.session = capture
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds

        // A mirror is a transform on the layer, not a flipped image — no
        // frame is touched, which is the only way to flip a preview that
        // never produces one.
        layer.setAffineTransform(
            isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        )

        if existing == nil {
            view.layer?.addSublayer(layer)
        }
        layer.frame = view.bounds
    }
}
