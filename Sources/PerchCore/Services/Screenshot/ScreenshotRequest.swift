import Foundation

/// What the screenshot module is asked to capture (`docs/FEATURES.md` §16).
public enum CaptureKind: String, CaseIterable, Sendable, Codable {
    /// A rectangle somebody drags out.
    case area
    /// One window, picked by clicking it.
    case window
    /// The whole display the pointer is on.
    case screen
}

/// What happens to a capture once it is taken.
public enum ScreenshotAction: Equatable, Sendable {
    /// Kept as an image, wherever `ScreenshotDestination` says.
    case save(CaptureKind)
    /// Read for text on this Mac; the text is kept and the image is not.
    case copyText
    /// Floated above everything as a reference card; nothing is kept on disk.
    case pin
}

/// Where a saved capture goes.
public enum ScreenshotDestination: String, CaseIterable, Sendable, Codable {
    /// Into the shelf, where it can be dragged out, shared or converted.
    /// Falls back to `folder` when the shelf is switched off.
    case shelf
    /// Onto the clipboard only, as macOS does with Control held.
    case clipboard
    /// The folder macOS saves its own screenshots to.
    case folder
}

/// The module's preferences.
public struct ScreenshotConfiguration: Equatable, Sendable, Codable {

    public var destination: ScreenshotDestination
    public var playsSound: Bool

    public init(destination: ScreenshotDestination = .shelf, playsSound: Bool = true) {
        self.destination = destination
        self.playsSound = playsSound
    }
}

/// The arguments for `/usr/sbin/screencapture`.
///
/// The tool rather than ScreenCaptureKit, for three reasons that are all
/// about other people's Macs. Its area and window pickers are the ones
/// everybody already knows from ⌘⇧4, Escape and the space bar included;
/// they are correct across displays without Perch converting a single
/// coordinate (`CLAUDE.md` §5.4); and they work on macOS 13, where
/// ScreenCaptureKit has no screenshot call at all.
///
/// An array of separate arguments, never a string handed to a shell, so a
/// file name can never become a command (TC-SCR-003).
public enum ScreenCaptureArguments {

    /// - Parameters:
    ///   - kind: What to capture.
    ///   - display: For `.screen`, the display under the pointer, numbered
    ///     the way the tool numbers them — 1 is the main display.
    ///   - output: The file to write. Always a file, even when the image is
    ///     bound for the clipboard: whether the file appeared is the one
    ///     reliable sign that a capture happened (`CaptureResult`).
    ///   - playsSound: Whether the shutter sound plays.
    public static func make(
        kind: CaptureKind,
        display: Int?,
        output: URL,
        playsSound: Bool
    ) -> [String] {
        var arguments: [String] = []

        switch kind {
        case .area:
            arguments += ["-i", "-s"]
        case .window:
            arguments += ["-i", "-w"]
        case .screen:
            arguments += ["-D", String(max(display ?? 1, 1))]
        }

        if !playsSound {
            arguments.append("-x")
        }

        arguments.append(output.path)
        return arguments
    }

    /// The tool's number for a display: its place in the active display
    /// list, counting from 1, which is the main display. `nil` when the
    /// display has gone — unplugged between the press and the capture.
    public static func displayNumber(of display: UInt32, in active: [UInt32]) -> Int? {
        active.firstIndex(of: display).map { $0 + 1 }
    }
}

/// How a capture ended, decided from what the tool left behind.
public enum CaptureResult: Equatable, Sendable {
    case captured
    /// Escape pressed, or a click on nothing. Not a failure, and not worth
    /// a message (TC-SCR-004).
    case cancelled
    case failed(reason: String)

    /// The tool exits non-zero both when it fails and when somebody presses
    /// Escape, so the exit code alone cannot tell the two apart. What can is
    /// whether it wrote anything, and whether it said why not.
    public static func from(exitCode: Int32, producedOutput: Bool, error: String) -> Self {
        if producedOutput { return .captured }

        let reason = error.trimmingCharacters(in: .whitespacesAndNewlines)
        if exitCode != 0, !reason.isEmpty {
            return .failed(reason: reason)
        }
        return .cancelled
    }
}
