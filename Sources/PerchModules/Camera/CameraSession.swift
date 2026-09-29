import AVFoundation
import AppKit
import PerchCore

/// The capture device, and the promises made about it.
///
/// `CLAUDE.md` §4 singles this module out: the device is released — green
/// light off — within 500ms of the island collapsing, and no frame reaches
/// disk without an explicit snapshot. Those are promises made on the
/// website, so they are tests (TC-CAM-006 … TC-CAM-009) rather than
/// intentions. Everything in this file exists to keep them.
///
/// Three rules it follows, and each one is a thing it deliberately does not
/// do:
///
/// - **It never opens the device to warm up.** Constructing this, switching
///   the module on and launching the app all open nothing. `start` is called
///   from one place: the preview appearing (TC-CAM-009).
/// - **It keeps no buffer.** There is no photo output and no video data
///   output in the running session — only a preview layer, which renders
///   from the device and hands nothing back. A snapshot adds an output, uses
///   it once and removes it (TC-CAM-008).
/// - **It stops synchronously.** `stop` tears the session down on the
///   calling turn rather than posting work for later, because "within
///   500ms" is not a thing you can promise about a queue you do not control
///   (TC-CAM-006).
@MainActor
final class CameraSession: NSObject {

    enum Failure: Equatable {
        /// Camera permission was refused, or has been revoked (TC-CAM-016).
        case denied

        /// No camera at all — unplugged, or a Mac with none (TC-CAM-012).
        case noDevice

        /// Another app has the device and will not share it (TC-CAM-011).
        case inUse

        /// The device answered, but the session would not run.
        case unavailable
    }

    /// The running session, or `nil`. Its existence is the whole of "is the
    /// camera on": there is no separate flag that could disagree with it.
    private(set) var session: AVCaptureSession?

    private(set) var device: AVCaptureDevice?

    var isRunning: Bool { session?.isRunning ?? false }

    /// Called when the device being used goes away — an unplugged webcam, an
    /// iPhone that went to sleep (TC-CAM-012, TC-CAM-013).
    var onDeviceLost: ((String) -> Void)?

    private var lostObserver: NSObjectProtocol?

    // MARK: - Permission

    var authorization: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Asks for camera access. Prompting is the only thing this does — it
    /// opens no device, which is what makes TC-CAM-009 true even on the
    /// first run.
    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    // MARK: - Devices

    /// Every camera macOS will offer. Deliberately rebuilt on each call
    /// rather than cached: a discovery session that is kept alive is a
    /// resource a switched-off module would be holding.
    func devices() -> [CameraDevice] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]

        // `.external` and `.continuityCamera` arrived in macOS 14, and the
        // 13 spelling of the first one is deprecated in the 14 SDK. Both
        // spellings, so a USB webcam works on Ventura too.
        if #available(macOS 14.0, *) {
            types.append(contentsOf: [.external, .continuityCamera])
        } else {
            types.append(.externalUnknown)
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        )

        return discovery.devices.map { device in
            CameraDevice(
                id: device.uniqueID,
                name: device.localizedName,
                isContinuity: Self.isContinuity(device),
                isBuiltIn: device.deviceType == .builtInWideAngleCamera
            )
        }
    }

    private static func isContinuity(_ device: AVCaptureDevice) -> Bool {
        guard #available(macOS 14.0, *) else { return false }
        return device.deviceType == .continuityCamera
    }

    // MARK: - Running

    /// Opens the device and starts the session.
    ///
    /// The only caller is the preview appearing. Adding a second one is how
    /// TC-CAM-009 stops being true, so if you are about to: don't.
    func start(deviceID: String?) -> Failure? {
        guard authorization != .denied && authorization != .restricted else { return .denied }
        guard session == nil else { return nil }

        let available = devices()
        guard let chosen = CameraSelection.resolve(preferred: deviceID, from: available),
            let device = AVCaptureDevice(uniqueID: chosen.id)
        else { return .noDevice }

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            // The documented reason an input refuses a device that exists.
            return .inUse
        }

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return .unavailable
        }

        session.addInput(input)
        session.commitConfiguration()

        // There is no output here, and that is the point. A preview layer
        // renders straight from the session; nothing hands Perch a frame, so
        // there is no frame for Perch to keep or to write (TC-CAM-007,
        // TC-CAM-008).
        self.session = session
        self.device = device

        observeLoss(of: device)

        // Starting blocks for as long as the device takes to answer, which
        // is why it is off the main thread — but the session object itself
        // is already built, so the view can attach to it immediately and the
        // preview appears as soon as frames do (TC-CAM-002).
        let starting = Unsafely(session)
        Task.detached(priority: .userInitiated) {
            starting.value.startRunning()
        }

        return nil
    }

    /// Stops the session and releases the device.
    ///
    /// Synchronous on the calling turn: inputs removed, session stopped,
    /// references dropped. "Within 500ms" cannot be promised about work
    /// posted to a queue somebody else owns (TC-CAM-006).
    func stop() {
        if let lostObserver {
            NotificationCenter.default.removeObserver(lostObserver)
        }
        lostObserver = nil

        guard let session else { return }

        session.stopRunning()

        // Removing the input is what actually closes the device and puts the
        // green light out. Stopping the session alone leaves it held.
        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }
        session.commitConfiguration()

        self.session = nil
        self.device = nil
    }

    /// TC-CAM-012 and TC-CAM-013. A webcam unplugged and an iPhone that went
    /// to sleep produce the same notification, and both are normal.
    private func observeLoss(of device: AVCaptureDevice) {
        let id = device.uniqueID

        lostObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: device,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onDeviceLost?(id)
            }
        }
    }

    // MARK: - Snapshot

    /// Captures one image, and only when asked.
    ///
    /// The photo output is added here, used once, and removed — so a running
    /// preview holds nothing that could produce a frame, and the one frame
    /// that exists is the one somebody pressed a button for (TC-CAM-010).
    ///
    /// Returns `nil` rather than throwing: there is one thing the caller can
    /// do about a failed snapshot, and it is to say so.
    func snapshot() async -> NSImage? {
        guard let session, session.isRunning else { return nil }

        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else { return nil }

        session.beginConfiguration()
        session.addOutput(output)
        session.commitConfiguration()

        defer {
            session.beginConfiguration()
            session.removeOutput(output)
            session.commitConfiguration()
        }

        let delegate = SnapshotDelegate()
        let data: Data? = await withCheckedContinuation { continuation in
            delegate.completion = { continuation.resume(returning: $0) }
            // Held by the output only for the duration of the capture, so
            // the delegate has to be kept alive here.
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
        }

        guard let data else { return nil }
        return NSImage(data: data)
    }
}

/// A value promised safe to cross an isolation boundary, said once.
///
/// `AVCaptureSession` is documented as safe to use from any thread and is
/// not annotated `Sendable` in every SDK Perch builds against — the macOS 14
/// one is not, which is why this built locally and on one CI runner and not
/// the other. A box states the promise in a place it can be read, and it
/// works on every compiler; `nonisolated(unsafe)` on a local does not,
/// because the closure it is captured into is itself a `sending` parameter.
private struct Unsafely<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// One capture, one callback, then gone.
///
/// `AVCapturePhotoOutput` holds its delegate weakly for the duration of a
/// capture and no longer, which is why this is a separate object rather than
/// the session itself: a session that conformed would keep the photo
/// plumbing alive for as long as the preview.
private final class SnapshotDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {

    var completion: ((Data?) -> Void)?

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        completion?(error == nil ? photo.fileDataRepresentation() : nil)
        completion = nil
    }
}
