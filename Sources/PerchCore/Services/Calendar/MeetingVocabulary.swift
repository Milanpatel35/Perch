import Foundation

/// The menu titles each meeting client uses, and what they mean.
///
/// **Perch drives the menu bar, not the window.** A meeting client's window
/// is a canvas of custom-drawn controls that move every release; its menu
/// bar is a titled, documented list that the vendor cannot change without
/// changing its own keyboard shortcuts. Reading `Meeting ▸ Unmute Audio`
/// tells you both that the control exists *and* that the call is currently
/// muted, which is what keeps the island and the app from ever disagreeing
/// (TC-CAL-009). ADR 0006 records the choice.
///
/// The vocabulary is pure data so that the matching rules are unit-testable
/// without Accessibility, a running client, or a meeting. The AX plumbing
/// that uses it lives in `MeetingControls` in the module layer.
public struct MeetingVocabulary: Equatable, Sendable {

    /// What a menu item does when pressed.
    public enum Action: Equatable, Sendable, CaseIterable {
        case mute
        case unmute
        case startVideo
        case stopVideo
        case leave
    }

    /// The menu that only exists while a call is running. Its presence is
    /// how Perch knows you are in one without asking the client anything —
    /// and without launching it to find out.
    public let callMenuTitles: [String]

    /// Title → action. Matched case-insensitively and by prefix, because
    /// every one of these clients appends a keyboard-shortcut hint or an
    /// ellipsis to some of them, and does so inconsistently between
    /// releases.
    public let items: [String: Action]

    public init(callMenuTitles: [String], items: [String: Action]) {
        self.callMenuTitles = callMenuTitles
        self.items = items
    }

    /// What this menu title means, if anything.
    ///
    /// Prefix matching, longest first: "Stop Video" and "Stop Video Preview"
    /// must not resolve to each other, and the more specific title is the
    /// one the vendor meant.
    public func action(for title: String) -> Action? {
        let cleaned = Self.normalise(title)
        guard !cleaned.isEmpty else { return nil }

        let matches = items.keys
            .filter { cleaned.hasPrefix(Self.normalise($0)) }
            .sorted { $0.count > $1.count }

        return matches.first.flatMap { items[$0] }
    }

    public func isCallMenu(_ title: String) -> Bool {
        let cleaned = Self.normalise(title)
        return callMenuTitles.contains { cleaned == Self.normalise($0) }
    }

    /// Strips the decoration vendors put on menu titles: the trailing
    /// ellipsis, the shortcut hint in parentheses, and stray whitespace.
    static func normalise(_ title: String) -> String {
        var cleaned = title.lowercased()

        if let parenthesis = cleaned.firstIndex(of: "(") {
            cleaned = String(cleaned[cleaned.startIndex..<parenthesis])
        }

        return
            cleaned
            .replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - The clients

    /// The vocabulary for a service, or `nil` if Perch cannot drive it.
    ///
    /// Meet, Around and Whereby run in a browser. A browser tab has no menu
    /// bar of its own, its mute button is a `<div>`, and driving it would
    /// mean reaching into whichever browser you use and guessing at a web
    /// page's element tree. That is not a control Perch can promise, so it
    /// does not offer one — `docs/FEATURES.md` §5 says so plainly.
    public static func vocabulary(for service: MeetingLink.Service) -> Self? {
        switch service {
        case .zoom: zoom
        case .teams: teams
        case .webex: webex
        case .meet, .around, .whereby: nil
        }
    }

    /// Zoom. The best documented of the three: its `Meeting` menu appears
    /// only in a call, and every title below is one of its own published
    /// keyboard shortcuts.
    public static let zoom = Self(
        callMenuTitles: ["Meeting"],
        items: [
            "Mute Audio": .mute,
            "Unmute Audio": .unmute,
            "Start Video": .startVideo,
            "Stop Video": .stopVideo,
            "End Meeting": .leave,
            "Leave Meeting": .leave
        ]
    )

    /// Microsoft Teams. Best effort, and recorded as such — see
    /// `docs/FEATURES.md` §5. Teams ships a thin menu bar and has changed
    /// it between the classic and the 2.x client, so a title miss here
    /// resolves to `.unsupported` rather than to a button that does nothing
    /// (TC-CAL-011).
    public static let teams = Self(
        callMenuTitles: ["Meeting", "Call"],
        items: [
            "Mute": .mute,
            "Mute Microphone": .mute,
            "Unmute": .unmute,
            "Unmute Microphone": .unmute,
            "Turn Camera On": .startVideo,
            "Turn Camera Off": .stopVideo,
            "Leave": .leave,
            "Leave Meeting": .leave,
            "Hang Up": .leave
        ]
    )

    /// Webex. Best effort, as Teams is.
    public static let webex = Self(
        callMenuTitles: ["Meeting", "Call"],
        items: [
            "Mute Me": .mute,
            "Mute My Audio": .mute,
            "Unmute Me": .unmute,
            "Unmute My Audio": .unmute,
            "Start My Video": .startVideo,
            "Stop My Video": .stopVideo,
            "Leave Meeting": .leave,
            "End Meeting": .leave
        ]
    )

    // MARK: - Reading state out of the titles

    /// Whether the call is muted, judged from which titles the menu offers.
    ///
    /// The trick, and the reason the island never disagrees with the app: a
    /// client that offers "Unmute Audio" is muted, and one that offers
    /// "Mute Audio" is not. The state is read from the app every time
    /// rather than remembered, so muting inside the meeting window shows up
    /// in the island without Perch being told (TC-CAL-009).
    ///
    /// `nil` when neither title is present — unknown, which is not the same
    /// as unmuted.
    public static func isMuted(given actions: Set<Action>) -> Bool? {
        if actions.contains(.unmute) { return true }
        if actions.contains(.mute) { return false }
        return nil
    }

    /// Same reading, for the camera. "Start Video" offered means the camera
    /// is off.
    public static func isCameraOn(given actions: Set<Action>) -> Bool? {
        if actions.contains(.stopVideo) { return true }
        if actions.contains(.startVideo) { return false }
        return nil
    }
}
