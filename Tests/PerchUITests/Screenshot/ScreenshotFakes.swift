import Foundation
import PerchCore

@testable import PerchUI

// The screenshot module's edges, faked. The capture tool writes a small file
// or does not — which is a cancel — and records what it was asked.

final class FakeScreenCapturer: ScreenCapturing, @unchecked Sendable {
    enum Behaviour {
        case write
        case cancel
        case fail(String)
        case hold
    }

    var behaviour = Behaviour.write
    private(set) var calls: [[String]] = []
    private(set) var cancelled = 0
    private var gate: CheckedContinuation<Void, Never>?

    func capture(_ arguments: [String]) async -> (status: Int32, error: String) {
        calls.append(arguments)
        switch behaviour {
        case .write:
            let output = URL(fileURLWithPath: arguments.last ?? "")
            FileManager.default.createFile(atPath: output.path, contents: Data("png".utf8))
            return (0, "")
        case .cancel:
            return (1, "")
        case .fail(let reason):
            return (1, reason)
        case .hold:
            await withCheckedContinuation { gate = $0 }
            return (1, "")
        }
    }

    func cancelAll() {
        cancelled += 1
        gate?.resume()
        gate = nil
    }
}

final class FakeScreenRecordingPermission: ScreenRecordingPermission {
    var isGranted = true
    private(set) var requests = 0
    private(set) var settingsOpened = 0

    func request() { requests += 1 }
    func openSettings() { settingsOpened += 1 }
}

final class FakeScreenshotPins: ScreenshotPinning {
    private(set) var count = 0
    private(set) var closed = 0

    func pin(imageAt url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        count += 1
        return true
    }

    func closeAll() {
        closed += 1
        count = 0
    }
}

final class FakeScreenshotClipboard {
    var items: [ScreenshotClipboardItem] = []
}

/// A screenshot service over the fakes, and what the tests read back.
@MainActor
struct ScreenshotHarness {
    let service: ScreenshotService
    let island: IslandController
    let capturer: FakeScreenCapturer
    let permission: FakeScreenRecordingPermission
    let pins: FakeScreenshotPins
    let clipboard: FakeScreenshotClipboard
    /// Stands in for the system screenshot folder. The caller deletes it.
    let folder: URL

    static func make(recognised: String) throws -> Self {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let capturer = FakeScreenCapturer()
        let permission = FakeScreenRecordingPermission()
        let pins = FakeScreenshotPins()
        let clipboard = FakeScreenshotClipboard()

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotModuleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let system = ScreenshotSystem(
            capturer: capturer,
            permission: permission,
            recognise: { _ in recognised },
            pins: pins,
            copy: { clipboard.items.append($0) },
            displayUnderPointer: { 2 },
            screenshotFolder: { folder },
            settle: { _ in }
        )

        return Self(
            service: ScreenshotService(island: island, system: system),
            island: island,
            capturer: capturer,
            permission: permission,
            pins: pins,
            clipboard: clipboard,
            folder: folder
        )
    }

    var outcome: ScreenshotActivity.Outcome? {
        (island.presented?.base as? ScreenshotActivity)?.outcome
    }

    var savedFiles: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    var stagedFiles: [String] {
        (try? FileManager.default.contentsOfDirectory(
            atPath: ScreenshotService.stagingDirectory.path)) ?? []
    }

    /// Waits for a capture to run to the end. The fake tool runs off the
    /// main actor, so a fixed number of yields is not a wait — the
    /// condition is, with a ceiling so a broken test fails rather than hangs.
    func settle() async {
        for _ in 0..<200 where service.isCapturing {
            try? await Task.sleep(for: .milliseconds(10))
        }
        for _ in 0..<5 {
            await Task.yield()
        }
    }
}
