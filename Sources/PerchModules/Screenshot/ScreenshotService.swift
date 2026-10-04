import Combine
import Defaults
import Foundation
import PerchCore

/// Module 16 — Screenshots.
///
/// An area, a window or the screen, from the island; the text in an area,
/// read on this Mac; an area pinned above everything (`docs/FEATURES.md`
/// §16). Captures go into the shelf when it is on, so the shelf's drag-out,
/// share and convert work on them for free.
///
/// **Nothing runs until somebody presses a button.** Switching the module on
/// starts no process, adds no observer and asks for no permission
/// (TC-SCR-001); Screen Recording is asked for on the first capture, with
/// the reason in the prompt (TC-SCR-002).
@MainActor
final class ScreenshotService: ObservableObject, PerchModule {

    static let moduleID: ModuleID = .screenshot

    @Published private(set) var configuration: ScreenshotConfiguration
    @Published private(set) var isCapturing = false
    @Published private(set) var hasPermission = false

    private(set) var isActive = false

    /// Where a saved capture goes when the shelf is on. Wired by the
    /// registry; returning false — or not being wired — means the shelf is
    /// off, and the capture goes to the screenshot folder instead.
    var onSave: ((URL) -> Bool)?

    private let island: IslandController
    private let system: ScreenshotSystem
    private var captureTask: Task<Void, Never>?

    /// Long enough for the island's close to finish, so it is not in a
    /// full-screen shot (TC-SCR-013).
    static let settleDelay: Duration = .milliseconds(300)

    init(island: IslandController, system: ScreenshotSystem? = nil) {
        self.island = island
        self.system = system ?? .live
        self.configuration = Defaults[.screenshotConfiguration]
    }

    // MARK: - PerchModule

    func activate() {
        guard !isActive else { return }
        isActive = true
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        captureTask?.cancel()
        captureTask = nil
        system.capturer.cancelAll()
        system.pins.closeAll()

        isCapturing = false
        island.withdrawAll(from: .screenshot)
    }

    // MARK: - Settings

    func setConfiguration(_ configuration: ScreenshotConfiguration) {
        self.configuration = configuration
        Defaults[.screenshotConfiguration] = configuration
    }

    /// Re-read when the pane appears. Checking never prompts.
    func refreshPermission() {
        hasPermission = system.permission.isGranted
    }

    func openPermissionSettings() {
        system.permission.openSettings()
    }

    var pinCount: Int { system.pins.count }

    var screenshotFolder: URL { system.screenshotFolder() }

    // MARK: - Capturing

    /// One capture at a time. A second press while a crosshair is already
    /// up is ignored rather than stacking a second crosshair on the first.
    func perform(_ action: ScreenshotAction) {
        guard isActive, !isCapturing else { return }

        guard system.permission.isGranted else {
            askForPermission()
            return
        }
        hasPermission = true
        isCapturing = true

        // Closed before the shot, so the island is never in it (TC-SCR-013).
        island.send(.collapseRequested)

        let staged = stagingURL()
        let arguments = ScreenCaptureArguments.make(
            kind: Self.kind(for: action),
            display: Self.kind(for: action) == .screen ? system.displayUnderPointer() : nil,
            output: staged,
            playsSound: configuration.playsSound
        )

        captureTask = Task { [weak self, system] in
            await system.settle(Self.settleDelay)
            guard !Task.isCancelled else { return Self.discard(staged) }

            let tool = await system.capturer.capture(arguments)
            let result = CaptureResult.from(
                exitCode: tool.status,
                producedOutput: FileManager.default.fileExists(atPath: staged.path),
                error: tool.error
            )
            await self?.finish(action, result, staged)
            Self.discard(staged)
        }
    }

    private static func kind(for action: ScreenshotAction) -> CaptureKind {
        if case .save(let kind) = action { return kind }
        return .area
    }

    private func askForPermission() {
        hasPermission = false
        // macOS prompts once per app, ever. After that the request is
        // silent, so the second press goes where the switch actually is.
        if Defaults[.screenshotAskedForPermission] {
            system.permission.openSettings()
        } else {
            Defaults[.screenshotAskedForPermission] = true
            system.permission.request()
        }
        say(.needsPermission)
    }

    private func finish(_ action: ScreenshotAction, _ result: CaptureResult, _ staged: URL) async {
        defer {
            isCapturing = false
            captureTask = nil
        }
        guard isActive, !Task.isCancelled else { return }

        switch result {
        case .cancelled:
            return
        case .failed(let reason):
            say(.failed(reason: reason))
        case .captured:
            await deliver(action, staged)
        }
    }

    private func deliver(_ action: ScreenshotAction, _ staged: URL) async {
        switch action {
        case .save:
            save(staged)

        case .copyText:
            let text = await system.recognise(staged)
            guard isActive else { return }
            if text.isEmpty {
                say(.noText)
            } else {
                system.copy(.text(text))
                say(.copiedText(characters: text.count))
            }

        case .pin:
            if !system.pins.pin(imageAt: staged) {
                say(.failed(reason: String(localized: "The capture could not be read")))
            }
        }
    }

    private func save(_ staged: URL) {
        switch configuration.destination {
        case .clipboard:
            system.copy(.image(staged))
            say(.copiedImage)

        case .shelf where onSave?(staged) == true:
            // The shelf copies it in and opens itself, which says it landed.
            break

        case .shelf, .folder:
            moveToFolder(staged)
        }
    }

    private func moveToFolder(_ staged: URL) {
        let folder = system.screenshotFolder()
        let name = ScreenshotNaming.unique(staged.lastPathComponent) { candidate in
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path)
        }

        do {
            try FileManager.default.moveItem(at: staged, to: folder.appendingPathComponent(name))
            say(.saved(filename: name, folder: folder.lastPathComponent))
        } catch {
            say(.failed(reason: error.localizedDescription))
        }
    }

    private func say(_ outcome: ScreenshotActivity.Outcome) {
        island.submit(ScreenshotActivity(outcome: outcome))
    }

    // MARK: - Staging

    /// Every capture is written here first, and whatever is left is deleted
    /// once it has been delivered — so the only image that survives is the
    /// one somebody chose to keep (TC-SCR-005, TC-SCR-009).
    static let stagingDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Perch Screenshots", isDirectory: true)

    private func stagingURL() -> URL {
        try? FileManager.default.createDirectory(
            at: Self.stagingDirectory, withIntermediateDirectories: true)
        let name = ScreenshotNaming.unique(ScreenshotNaming.filename(for: Date())) { candidate in
            FileManager.default.fileExists(
                atPath: Self.stagingDirectory.appendingPathComponent(candidate).path)
        }
        return Self.stagingDirectory.appendingPathComponent(name)
    }

    nonisolated private static func discard(_ staged: URL) {
        try? FileManager.default.removeItem(at: staged)
    }
}

extension ScreenshotConfiguration: Defaults.Serializable {}

extension Defaults.Keys {
    static let screenshotConfiguration = Key<ScreenshotConfiguration>(
        "screenshot_configuration",
        default: ScreenshotConfiguration()
    )

    /// Whether the system prompt has been shown. It only ever shows once.
    static let screenshotAskedForPermission = Key<Bool>(
        "screenshot_askedForPermission",
        default: false
    )
}
