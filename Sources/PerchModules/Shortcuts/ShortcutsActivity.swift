import Foundation
import PerchCore

/// What the Shortcuts module puts on the island: a message somebody sent,
/// or a Shortcut running and then finished.
///
/// One id for all of it. A script that sends ten messages in a second
/// updates one activity ten times rather than queueing ten, which is also
/// what keeps a web page opening `perch://notify` in a loop from burying
/// everything else on the island.
struct ShortcutsActivity: IslandActivity {

    static let identifier = ActivityID("shortcuts.message")

    let id = Self.identifier
    let source: ModuleID = .shortcuts

    let kind: Kind
    let priority: ActivityPriority

    enum Kind: Equatable, Sendable {
        /// "Show message in island", from the Shortcuts app, a URL or the CLI.
        case message(PerchCommand.Message)

        /// A favourite pressed on the island, still going.
        case running(name: String)

        /// A favourite finished.
        case finished(name: String, outcome: ShortcutOutcome)
    }

    /// A running Shortcut stays until it finishes; everything else says its
    /// piece and goes.
    var timeToLive: Duration? {
        switch kind {
        case .running: nil
        case .message, .finished: .seconds(4)
        }
    }

    var isExpandable: Bool {
        if case .message(let message) = kind { return message.body != nil }
        return false
    }

    static func message(_ message: PerchCommand.Message) -> Self {
        Self(kind: .message(message), priority: message.urgency.priority)
    }

    /// Something a person pressed. Answered at the same priority as a
    /// normal message: above the music, below anything that is an alarm.
    static func run(_ kind: Kind) -> Self {
        Self(kind: kind, priority: PerchCommand.Urgency.normal.priority)
    }
}
