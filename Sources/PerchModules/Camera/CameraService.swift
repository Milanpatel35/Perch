import AVFoundation
import AppKit
import Combine
import Defaults
import KeyboardShortcuts
import PerchCore
import SwiftUI

/// Module 9 — the camera.
///
/// **The device is open only while the preview is on screen.** Switching the
/// module on opens nothing, launching the app opens nothing, and enabling
/// the pre-call check opens nothing (TC-CAM-009). `CameraSession` holds the
/// promises; this decides when to ask it for them.
///
/// Nothing here polls. The preview is opened by a gesture, by the shortcut,
/// or by the pre-call check — which is itself driven by the calendar
/// module's own wake-up rather than by a timer of its own.
@MainActor
final class CameraService: ObservableObject, PerchModule {

    static let moduleID: ModuleID = .camera

    @Published private(set) var presentation = CameraPresentation()
    @Published private(set) var devices: [CameraDevice] = []
    @Published private(set) var isPreviewing = false
    @Published private(set) var failure: CameraSession.Failure?
    @Published private(set) var preCall = PreCallCheck()

    private(set) var isActive = false

    /// The live session. Handed to the preview view, and to nothing else.
    let session = CameraSession()

    private let island: IslandController

    /// Where a snapshot goes, when the shelf module is on
    /// (`docs/FEATURES.md` §9). Wired by the registry; `nil` or a refusal
    /// means the shelf is not there and the image goes to Pictures instead.
    ///
    /// Takes a file rather than an image because that is the shelf's own
    /// API, and because a snapshot is a file — the one file this module
    /// ever creates.
    var onSnapshot: ((URL) -> Bool)?

    /// The pinned floating pill, when there is one. A panel of its own
    /// rather than the island's, because it has to outlive the island being
    /// collapsed — that is what "detaches" means (TC-CAM-005).
    private var pinnedPanel: CameraPinPanel?

    private var reason: CameraActivity.Reason = .opened
    private var autoCloseTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    /// Injected so tests can pin the clock. Not private: the snapshot half
    /// lives in `CameraSnapshot.swift` and names its files from it.
    let now: @MainActor () -> Date

    init(island: IslandController, now: @escaping @MainActor () -> Date = { Date() }) {
        self.island = island
        self.now = now
        self.presentation = Defaults[.cameraPresentation]
        self.preCall = PreCallCheck(configuration: Defaults[.preCallCheck])
    }

    // MARK: - PerchModule

    func activate() {
        guard !isActive else { return }
        isActive = true

        // No device is opened here. Listing cameras does not open one, and
        // permission is asked for at the first preview rather than now —
        // a green light on "switch the module on" is exactly the behaviour
        // this module promises not to have (TC-CAM-009, TC-PRV-002).
        devices = session.devices()

        session.onDeviceLost = { [weak self] id in
            self?.deviceLost(id)
        }

        observeIslandCollapse()
        registerShortcut()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        closePreview()
        unpin()

        session.onDeviceLost = nil
        cancellables.removeAll()
        devices = []
        preCall.reset()

        KeyboardShortcuts.disable(.cameraPreview)
        island.withdrawAll(from: .camera)
    }

    // MARK: - Opening and closing

    /// Opens the preview. The only path that opens a device.
    func openPreview(reason: CameraActivity.Reason = .opened) {
        guard isActive else { return }

        self.reason = reason

        guard session.authorization == .authorized else {
            requestAccessThenOpen(reason: reason)
            return
        }

        failure = session.start(deviceID: Defaults[.cameraDeviceID])
        isPreviewing = failure == nil

        devices = session.devices()
        present()

        // Opened on purpose, so it opens open — a camera preview squeezed
        // into a peek beside the notch is not a preview.
        island.send(.clicked)

        if case .preCallCheck = reason {
            scheduleAutoClose()
        }
    }

    /// Closes the preview and, with it, the camera.
    ///
    /// Called by the island collapsing, by the toggle, by the module being
    /// switched off, and by the pre-call check timing out. Every one of them
    /// ends in `session.stop()`, which is synchronous (TC-CAM-006).
    func closePreview() {
        autoCloseTask?.cancel()
        autoCloseTask = nil

        session.stop()
        isPreviewing = false
        failure = nil

        island.withdraw(CameraActivity.identifier)
    }

    func togglePreview() {
        guard isActive else { return }
        if isPreviewing {
            closePreview()
        } else {
            openPreview()
        }
    }

    private func requestAccessThenOpen(reason: CameraActivity.Reason) {
        // Requested here — at the first preview, with the reason on screen —
        // and never on enabling the module (`CLAUDE.md` §5.3, TC-CAM-001).
        Task { [weak self] in
            guard let self else { return }
            let granted = await session.requestAccess()
            guard isActive else { return }

            guard granted else {
                failure = .denied
                present()
                return
            }
            openPreview(reason: reason)
        }
    }

    /// **TC-CAM-006.** The island collapsing is what closes the camera, and
    /// it has to be the island that says so rather than the view
    /// disappearing: a view is torn down whenever SwiftUI feels like it, and
    /// "green light out within 500ms" is not a promise you can hang on that.
    ///
    /// A pinned preview is exempt by design — it detached from the island,
    /// which is the whole point of pinning (TC-CAM-005).
    private func observeIslandCollapse() {
        island.$state
            .map { $0.presentation.activityID == CameraActivity.identifier }
            .removeDuplicates()
            .sink { [weak self] isShowingCamera in
                guard let self else { return }
                guard !isShowingCamera, isPreviewing, !presentation.isPinned else { return }
                closePreview()
            }
            .store(in: &cancellables)
    }

    private func present() {
        island.submit(
            CameraActivity(
                presentation: presentation,
                deviceName: session.device?.localizedName ?? "",
                reason: reason,
                failure: failure
            )
        )
    }

    // MARK: - The pre-call check

    /// Called by the registry when the calendar module says a meeting is
    /// coming up. Nothing calls it when the calendar is off, which is the
    /// whole of TC-CAM-015.
    func meetingApproaching(eventID: String, title: String, startsAt: Date, hasLink: Bool) {
        guard isActive, !isPreviewing else { return }

        let shouldOpen = preCall.shouldCheck(
            eventID: eventID,
            startsAt: startsAt,
            hasMeetingLink: hasLink,
            now: now()
        )
        guard shouldOpen else { return }

        openPreview(reason: .preCallCheck(eventTitle: title))
    }

    /// The pre-call preview closes itself. One scheduled wake-up, cancelled
    /// by anything that closes the preview first — the focus timer's pattern,
    /// for the same reason.
    private func scheduleAutoClose() {
        autoCloseTask?.cancel()

        let duration = preCall.configuration.duration
        autoCloseTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.closePreview()
        }
    }

    // MARK: - Devices

    private func deviceLost(_ id: String) {
        guard isActive, isPreviewing else { return }

        devices = session.devices()
        session.stop()

        guard let next = CameraSelection.fallback(after: id, from: devices) else {
            // Nothing left to show. Collapse rather than hold an empty
            // session open (TC-CAM-012).
            closePreview()
            return
        }

        Defaults[.cameraDeviceID] = next.id
        failure = session.start(deviceID: next.id)
        isPreviewing = failure == nil
        present()
    }

    func selectDevice(_ device: CameraDevice) {
        Defaults[.cameraDeviceID] = device.id
        guard isPreviewing else { return }

        session.stop()
        failure = session.start(deviceID: device.id)
        isPreviewing = failure == nil
        present()
    }

    func refreshDevices() {
        devices = session.devices()
    }

    var selectedDeviceID: String? { Defaults[.cameraDeviceID] }

    // MARK: - Presentation

    func setPresentation(_ presentation: CameraPresentation) {
        self.presentation = presentation
        Defaults[.cameraPresentation] = presentation

        pinnedPanel?.update(presentation: presentation)
        guard isPreviewing, !presentation.isPinned else { return }
        present()
    }

    func toggleMirror() {
        var updated = presentation
        updated.isMirrored.toggle()
        setPresentation(updated)
    }

    func setShape(_ shape: CameraPresentation.Shape) {
        var updated = presentation
        updated.shape = shape
        setPresentation(updated)
    }

    func resize(byScroll delta: Double) {
        var updated = presentation
        updated.resize(byScroll: delta)
        setPresentation(updated)
    }

    func setPreCallConfiguration(_ configuration: PreCallCheck.Configuration) {
        preCall.setConfiguration(configuration)
        Defaults[.preCallCheck] = configuration
    }

    // MARK: - Pinning

    /// Detaches the preview into a floating pill that survives the island
    /// collapsing and a Space switch (TC-CAM-005).
    func togglePin() {
        if presentation.isPinned {
            unpin()
        } else {
            pin()
        }
    }

    private func pin() {
        guard isActive else { return }

        if !isPreviewing {
            openPreview()
            guard isPreviewing else { return }
        }

        var updated = presentation
        updated.isPinned = true
        presentation = updated
        Defaults[.cameraPresentation] = updated

        let panel = CameraPinPanel(session: session, presentation: updated)
        panel.onMove = { [weak self] origin in
            guard let self else { return }
            var moved = presentation
            moved.pinnedOrigin = origin
            presentation = moved
            Defaults[.cameraPresentation] = moved
        }
        panel.onClose = { [weak self] in self?.unpin() }
        panel.show()
        pinnedPanel = panel

        // The island's copy goes away; the pill is the preview now.
        island.withdraw(CameraActivity.identifier)
    }

    private func unpin() {
        pinnedPanel?.close()
        pinnedPanel = nil

        guard presentation.isPinned else { return }

        var updated = presentation
        updated.isPinned = false
        presentation = updated
        Defaults[.cameraPresentation] = updated

        // Unpinning while the module is going away must not re-open the
        // island's preview behind it.
        guard isActive, isPreviewing else { return }
        present()
    }

    private func registerShortcut() {
        KeyboardShortcuts.onKeyUp(for: .cameraPreview) { [weak self] in
            MainActor.assumeIsolated {
                self?.togglePreview()
            }
        }
        KeyboardShortcuts.enable(.cameraPreview)
    }
}

extension KeyboardShortcuts.Name {
    /// No default, for the reason every other module gives: an unrequested
    /// global hotkey collides with something, silently.
    static let cameraPreview = Self("cameraPreview")
}
