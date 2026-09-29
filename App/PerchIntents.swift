import AppIntents
import AppKit
import PerchCore

// Perch's actions in the Shortcuts app (`docs/FEATURES.md` §13).
//
// In the app target because that is where App Intents have to live on the
// macOS 13 floor — frameworks only gained them in 14. Each one builds a
// `perch://` URL and opens it, so an action from the Shortcuts app arrives
// through exactly the same front door as a link or the CLI, and is checked
// by exactly the same code (`PerchURL.parse`). There is no second path to
// get wrong.

struct ShowMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Message in Island"
    static let description = IntentDescription(
        "Shows a line of text in Perch's island, with an optional second line."
    )

    @Parameter(title: "Message")
    var message: String

    @Parameter(title: "Detail")
    var detail: String?

    @Parameter(title: "Urgent", default: false)
    var isUrgent: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        open(
            .notify(
                .init(title: message, body: detail, urgency: isUrgent ? .high : .normal)
            )
        )
        return .result()
    }
}

struct AddToShelfIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Shelf"
    static let description = IntentDescription("Puts a file on Perch's shelf.")

    @Parameter(title: "File")
    var file: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let url = file.fileURL else {
            throw PerchIntentError.notAFileOnThisMac
        }
        open(.addToShelf(url))
        return .result()
    }
}

struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Focus Session"
    static let description = IntentDescription(
        "Starts a focus session in Perch, with the lengths set in Preferences."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        open(.startFocus)
        return .result()
    }
}

enum PerchIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notAFileOnThisMac

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notAFileOnThisMac: "That file is not on this Mac, so it cannot go on the shelf."
        }
    }
}

/// Opened in the background so the Shortcuts app keeps focus.
@MainActor
private func open(_ command: PerchCommand) {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    NSWorkspace.shared.open(PerchURL.url(for: command), configuration: configuration)
}
