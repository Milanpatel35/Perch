import AppKit
import CoreGraphics
import Foundation
import PerchCore
import Vision

/// Everything the screenshot module touches outside itself, in one place.
///
/// The module's tests swap every piece of this for a fake, which is how they
/// prove what was *not* captured, copied or written as well as what was.
@MainActor
struct ScreenshotSystem {

    /// Runs `/usr/sbin/screencapture`.
    var capturer: any ScreenCapturing

    /// Screen Recording: whether Perch has it, and asking for it.
    var permission: any ScreenRecordingPermission

    /// Reads the text in an image file, on this Mac.
    var recognise: @Sendable (URL) async -> String

    /// Floats captures above everything.
    var pins: any ScreenshotPinning

    /// Puts text or an image on the clipboard.
    var copy: (ScreenshotClipboardItem) -> Void

    /// The tool's number for the display under the pointer.
    var displayUnderPointer: () -> Int?

    /// The folder macOS saves its own screenshots to.
    var screenshotFolder: () -> URL

    /// Waits for the island to finish closing before the shot is taken.
    var settle: @Sendable (Duration) async -> Void

    static var live: Self {
        Self(
            capturer: ScreenCaptureCommandLine(),
            permission: SystemScreenRecordingPermission(),
            recognise: { await TextRecogniser.recognise(imageAt: $0) },
            pins: ScreenshotPinBoard(),
            copy: { $0.write(to: .general) },
            displayUnderPointer: { NSScreen.captureDisplayNumberUnderPointer },
            screenshotFolder: {
                ScreenshotLocation.resolve(
                    stored: UserDefaults(suiteName: ScreenshotLocation.domain)?
                        .string(forKey: ScreenshotLocation.key),
                    home: FileManager.default.homeDirectoryForCurrentUser,
                    isDirectory: { url in
                        var isDirectory: ObjCBool = false
                        return FileManager.default.fileExists(
                            atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
                    }
                )
            },
            settle: { try? await Task.sleep(for: $0) }
        )
    }
}

/// What ends up on the clipboard.
enum ScreenshotClipboardItem: Equatable {
    case text(String)
    case image(URL)

    func write(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        switch self {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .image(let url):
            // Read into memory first: the staged file is deleted the moment
            // this returns, and a pasteboard holding a file URL would then
            // point at nothing.
            if let image = NSImage(contentsOf: url) {
                pasteboard.writeObjects([image])
            }
        }
    }
}

// MARK: - The capture tool

/// Talks to `/usr/sbin/screencapture`. See `ScreenCaptureArguments` for why
/// the tool rather than ScreenCaptureKit.
protocol ScreenCapturing: Sendable {
    /// Runs the tool and waits for it — which, for an area or a window, is
    /// as long as somebody takes to choose one.
    func capture(_ arguments: [String]) async -> (status: Int32, error: String)

    /// Ends a capture in progress, taking its crosshair off the screen.
    /// Called when the module switches off.
    func cancelAll()
}

final class ScreenCaptureCommandLine: ScreenCapturing, @unchecked Sendable {

    private static let tool = URL(fileURLWithPath: "/usr/sbin/screencapture")

    /// Guarded by `lock`, and only for the length of an insert, a remove or
    /// a terminate.
    private var running: [ObjectIdentifier: Process] = [:]
    private let lock = NSLock()

    func capture(_ arguments: [String]) async -> (status: Int32, error: String) {
        let process = Process()
        process.executableURL = Self.tool
        process.arguments = arguments

        let error = Pipe()
        process.standardError = error
        process.standardOutput = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let key = ObjectIdentifier(process)

        return await withCheckedContinuation { continuation in
            // A termination handler rather than `waitUntilExit`, so no
            // thread sits blocked while somebody lines up a selection.
            process.terminationHandler = { [weak self] finished in
                let stderr = error.fileHandleForReading.readDataToEndOfFile()
                self?.forget(key)
                continuation.resume(
                    returning: (
                        finished.terminationStatus, String(bytes: stderr, encoding: .utf8) ?? ""
                    )
                )
            }

            do {
                remember(process, as: key)
                try process.run()
            } catch {
                forget(key)
                process.terminationHandler = nil
                continuation.resume(returning: (126, error.localizedDescription))
            }
        }
    }

    func cancelAll() {
        lock.lock()
        let processes = Array(running.values)
        lock.unlock()

        for process in processes where process.isRunning {
            process.terminate()
        }
    }

    private func remember(_ process: Process, as key: ObjectIdentifier) {
        lock.lock()
        running[key] = process
        lock.unlock()
    }

    private func forget(_ key: ObjectIdentifier) {
        lock.lock()
        running[key] = nil
        lock.unlock()
    }
}

// MARK: - Permission

@MainActor
protocol ScreenRecordingPermission {
    var isGranted: Bool { get }

    /// Shows the system's prompt. macOS shows it once per app, ever; after
    /// that this does nothing, which is why the module opens System
    /// Settings instead from the second time on.
    func request()

    func openSettings()
}

struct SystemScreenRecordingPermission: ScreenRecordingPermission {

    /// Checking never prompts — that is the point of the preflight call, and
    /// why the pane can show the state before anybody presses anything.
    var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    func request() {
        CGRequestScreenCaptureAccess()
    }

    func openSettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Text

/// Reads text out of a capture with Vision.
///
/// **On this Mac and nowhere else.** Vision has no network path, so the text
/// on somebody's screen — which could be anything — never leaves it
/// (TC-SCR-009, TC-PRV-008).
enum TextRecogniser {

    static func recognise(imageAt url: URL) async -> String {
        await Task.detached(priority: .userInitiated) {
            RecognisedText.assemble(lines(in: url))
        }.value
    }

    private static func lines(in url: URL) -> [RecognisedLine] {
        let request = VNRecognizeTextRequest()
        // Accurate rather than fast: this runs once, when somebody asked,
        // and small interface text is most of what a screen holds.
        request.recognitionLevel = .accurate
        // Correction "fixes" exactly what people copy off a screen most —
        // codes, paths, identifiers — into dictionary words.
        request.usesLanguageCorrection = false

        do {
            try VNImageRequestHandler(url: url, options: [:]).perform([request])
        } catch {
            return []
        }

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognisedLine(
                text: candidate.string,
                boundingBox: observation.boundingBox,
                confidence: candidate.confidence
            )
        }
    }
}

// MARK: - Displays

extension NSScreen {

    /// `screencapture -D`'s number for the display the pointer is on, which
    /// is the one somebody pressing a button on the island is looking at.
    static var captureDisplayNumberUnderPointer: Int? {
        let pointer = NSEvent.mouseLocation
        guard
            let screen = screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }),
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber
        else { return nil }

        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var active = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &active, &count)

        return ScreenCaptureArguments.displayNumber(
            of: number.uint32Value, in: Array(active.prefix(Int(count))))
    }
}
