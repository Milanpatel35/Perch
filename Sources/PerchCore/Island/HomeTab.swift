/// The tabs across the top of the opened island.
///
/// Every notch app worth comparing with — NotchNook, boring.notch, Alcove —
/// splits its surface into a few tabs rather than stacking everything in
/// one column, and Perch's single column had grown past what a glance can
/// take in. Home is the default, and the island goes back to it each time
/// it closes.
public enum HomeTab: String, CaseIterable, Sendable {
    case home
    case media
    case calendar
    case shelf
    case tools

    /// The number key that switches to this tab while the island is open
    /// from the keyboard. Numbers, so they never collide with the letters
    /// in `HomeKeymap`.
    public var key: Character {
        switch self {
        case .home: "1"
        case .media: "2"
        case .calendar: "3"
        case .shelf: "4"
        case .tools: "5"
        }
    }

    public static func tab(for key: String) -> Self? {
        guard key.count == 1, let typed = key.first else { return nil }
        return Self.allCases.first { $0.key == typed }
    }

    /// The module a tab shows, if it belongs to one. Home and Tools draw
    /// from several and are always there.
    public var module: ModuleID? {
        switch self {
        case .home, .tools: nil
        case .media: .nowPlaying
        case .calendar: .calendar
        case .shelf: .shelf
        }
    }
}
