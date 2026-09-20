import PerchCore
import SwiftUI
import UniformTypeIdentifiers

/// Everything the panel draws.
///
/// The panel itself never resizes — see `IslandLayout`. This view is the full
/// size of the panel, transparent except for the island, which it anchors to
/// the top edge and animates between the three presentation sizes.
public struct IslandRootView: View {

    @ObservedObject private var controller: IslandController
    @ObservedObject private var motion: MotionPreferences
    @ObservedObject private var modules: ModuleHost

    private let layout: IslandLayout

    public init(
        controller: IslandController,
        motion: MotionPreferences,
        modules: ModuleHost,
        layout: IslandLayout
    ) {
        self.controller = controller
        self.motion = motion
        self.modules = modules
        self.layout = layout
    }

    public var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The panel is mostly empty space. Without this the hosting view
        // would swallow clicks meant for the app underneath.
        .allowsHitTesting(controller.acceptsMouseEvents)
        // Two things every module's view needs, and neither of which may be
        // a global: the geometry it is being drawn in, and the way back to
        // the service that owns its resources.
        .environment(\.notchMetrics, layout.metrics)
        .environmentObject(modules)
    }

    private var island: some View {
        ZStack {
            shape
                .fill(Color.black)
                .shadow(
                    color: .black.opacity(shadowOpacity),
                    radius: 12,
                    y: 6
                )

            content
                .frame(width: size.width, height: size.height)
                .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(shape)
        .onHover { hovering in
            controller.send(hovering ? .hoverBegan : .hoverEnded)
        }
        .onTapGesture {
            controller.send(.clicked)
        }
        // The island is a drop target whatever is currently on it. Dragging
        // a file to the notch has to work while music is playing, which
        // means the handler belongs here rather than inside the shelf's own
        // view — that view does not exist until the shelf is presented
        // (TC-SHF-001).
        .onDrop(of: Self.acceptedDropTypes, isTargeted: dropTargeted) { providers in
            guard let shelf = modules.shelf else { return false }
            Task { await shelf.accept(providers) }
            return true
        }
        .animation(motion.animation(for: controller.transition), value: size)
        .animation(
            motion.animation(for: controller.transition),
            value: controller.state.presentation
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    /// What the island will take from a drag. Files first: a drag out of
    /// Finder carries a file URL *and* a plain-text copy of its path, and
    /// accepting the text would turn every dropped file into a clipping.
    private static let acceptedDropTypes: [UTType] = [.fileURL, .image, .text]

    /// Reports drag-hover straight to the shelf, which is what opens the drop
    /// target. Written as a binding rather than an `onChange` because
    /// `onChange(of:perform:)` is deprecated on newer SDKs and its
    /// replacement does not exist on the macOS 13 floor this app builds for.
    private var dropTargeted: Binding<Bool> {
        Binding(
            get: { modules.shelf?.isDropTarget ?? false },
            set: { isTargeted in
                guard let shelf = modules.shelf else { return }
                if isTargeted {
                    shelf.beginDrag()
                } else {
                    shelf.endDrag()
                }
            }
        )
    }

    private var shape: NotchShape {
        NotchShape(
            bottomRadius: isOpen ? 22 : layout.metrics.cornerRadius,
            topRadius: layout.metrics.mode == .hardware ? 10 : 0
        )
    }

    @ViewBuilder
    private var content: some View {
        switch controller.state.presentation {
        case .idle:
            Color.clear

        case .peek:
            presenting?.peekView() ?? AnyView(Color.clear)

        case .expanded:
            presenting?.expandedView() ?? AnyView(Color.clear)
        }
    }

    // MARK: - Geometry

    private var presenting: (any IslandActivityPresenting)? {
        controller.presented?.base as? any IslandActivityPresenting
    }

    private var isOpen: Bool {
        if case .expanded = controller.state.presentation { return true }
        return false
    }

    private var size: CGSize {
        let requested: CGSize =
            switch controller.state.presentation {
            case .idle: layout.metrics.collapsedSize
            case .peek: presenting?.peekSize ?? layout.metrics.collapsedSize
            case .expanded: presenting?.expandedSize ?? layout.metrics.collapsedSize
            }

        return layout.islandFrame(contentSize: requested).size
    }

    /// No shadow while idle. On a notched Mac the island *is* the cutout when
    /// nothing is happening, and a cutout does not cast a shadow.
    private var shadowOpacity: Double {
        controller.state.presentation.isIdle ? 0 : 0.35
    }

    private var accessibilityLabel: String {
        controller.state.presentation.isIdle
            ? String(localized: "Perch island, idle")
            : String(localized: "Perch island")
    }
}
