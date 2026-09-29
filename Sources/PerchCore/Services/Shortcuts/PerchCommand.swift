import Foundation

/// Something another program asked Perch to do.
///
/// The one vocabulary shared by all three ways in — the `perch://` URL
/// scheme, the actions Perch gives the Shortcuts app, and the `perch` CLI
/// (`docs/FEATURES.md` §13). The Shortcuts actions and the CLI both *build a
/// URL* and hand it to macOS, so every one of them goes through
/// `PerchURL.parse` and there is exactly one place input is checked.
///
/// **What is deliberately not on this list: running a Shortcut.** A URL
/// scheme can be opened by any web page, and a page that could make Perch
/// run "Delete Files" is an arbitrary-execution path with a pleasant name on
/// it (TC-SHC-003). Shortcuts run from the island's own buttons, which only a
/// person at the keyboard can press.
public enum PerchCommand: Equatable, Sendable {

    /// "Show message in island".
    case notify(Message)

    /// "Add to shelf". Always an absolute file URL.
    case addToShelf(URL)

    /// "Start focus session", with the durations already configured.
    case startFocus

    public struct Message: Equatable, Sendable {
        public let title: String
        public let body: String?
        public let urgency: Urgency

        public init(title: String, body: String? = nil, urgency: Urgency = .normal) {
            self.title = title
            self.body = body
            self.urgency = urgency
        }
    }

    /// How hard a message may push, from outside.
    ///
    /// Three levels, and none of them reaches the top two priorities. A
    /// script can beat the music; it can never pass itself off as a system
    /// alert or a timer finishing, because those are the two things a person
    /// has to be able to trust the island about (TC-SHC-002).
    public enum Urgency: String, Equatable, Sendable, CaseIterable {
        case low
        case normal
        case high

        public var priority: ActivityPriority {
            switch self {
            case .low: .ambient
            case .normal: .fileDrop
            case .high: .incomingCall
            }
        }
    }
}

/// Reads and writes `perch://` URLs.
///
///     perch://notify?title=Build%20ok&body=12s&urgency=high
///     perch://shelf?path=/Users/me/Desktop/report.pdf
///     perch://focus
///
/// Pure, so every malformed input is a unit test rather than something to
/// type into Safari (TC-SHC-003).
public enum PerchURL {

    public static let scheme = "perch"

    /// Longest title or body accepted. The island shows one line of each;
    /// anything longer is either a mistake or an attempt to make the parser
    /// do work, and neither is worth accepting.
    public static let maximumTextLength = 200

    public enum Rejection: Error, Equatable, Sendable {
        case notPerch
        case unknownAction(String)
        case missingTitle
        case textTooLong
        case badUrgency(String)
        case missingPath
        case notAnAbsoluteFilePath
    }

    public static func parse(_ url: URL) -> Result<PerchCommand, Rejection> {
        guard url.scheme?.lowercased() == scheme else { return .failure(.notPerch) }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // `perch://notify` puts the action in the host; `perch:notify` puts it
        // in the path. Both are what people type, so both are read.
        let action = (components?.host ?? components?.path ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()

        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] where query[item.name] == nil {
            query[item.name] = item.value
        }

        switch action {
        case "notify":
            return notify(query)
        case "shelf":
            return shelf(query)
        case "focus":
            return .success(.startFocus)
        default:
            return .failure(.unknownAction(action))
        }
    }

    /// The URL for a command — what the Shortcuts actions and the CLI open.
    /// `parse(url(for: x))` is `x`, and a test holds it to that.
    public static func url(for command: PerchCommand) -> URL {
        var components = URLComponents()
        components.scheme = scheme

        switch command {
        case .notify(let message):
            components.host = "notify"
            var items = [URLQueryItem(name: "title", value: message.title)]
            if let body = message.body {
                items.append(URLQueryItem(name: "body", value: body))
            }
            if message.urgency != .normal {
                items.append(URLQueryItem(name: "urgency", value: message.urgency.rawValue))
            }
            components.queryItems = items

        case .addToShelf(let file):
            components.host = "shelf"
            components.queryItems = [URLQueryItem(name: "path", value: file.path)]

        case .startFocus:
            components.host = "focus"
        }

        // Every piece above is set through `URLComponents`, which
        // percent-encodes it, so there is no input that fails to form a URL.
        return components.url ?? URL(fileURLWithPath: "/")
    }

    // MARK: - Actions

    private static func notify(_ query: [String: String]) -> Result<PerchCommand, Rejection> {
        let title = clean(query["title"] ?? query["text"])
        guard let title else { return .failure(.missingTitle) }

        let body = clean(query["body"])
        guard title.count <= maximumTextLength, (body?.count ?? 0) <= maximumTextLength else {
            return .failure(.textTooLong)
        }

        var urgency = PerchCommand.Urgency.normal
        if let raw = query["urgency"] {
            guard let parsed = PerchCommand.Urgency(rawValue: raw.lowercased()) else {
                return .failure(.badUrgency(raw))
            }
            urgency = parsed
        }

        return .success(.notify(.init(title: title, body: body, urgency: urgency)))
    }

    private static func shelf(_ query: [String: String]) -> Result<PerchCommand, Rejection> {
        guard let path = query["path"], !path.isEmpty else { return .failure(.missingPath) }

        // Absolute paths only. A relative one would resolve against whatever
        // directory Perch happens to be running in, which nobody means.
        guard path.hasPrefix("/"), !path.contains("\0") else {
            return .failure(.notAnAbsoluteFilePath)
        }

        return .success(.addToShelf(URL(fileURLWithPath: path).standardizedFileURL))
    }

    /// Trimmed, control characters removed, `nil` if nothing is left. The
    /// island draws one line; a newline in a title would draw half of one.
    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let scalars = value.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) ? " " : Character(scalar)
        }
        let cleaned = String(scalars).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }
}
