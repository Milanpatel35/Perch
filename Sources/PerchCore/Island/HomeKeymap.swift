/// Everything the home surface can do with one key.
///
/// The island opened from the keyboard takes single letters: C for the
/// clipboard, A for an area, and so on. Every button on the home surface
/// shows its letter, so the keys are learnt by looking rather than from a
/// list.
public enum HomeAction: String, CaseIterable, Sendable {
    case clipboard
    case focus
    case camera
    case calendar
    case captureArea
    case captureWindow
    case captureScreen
    case copyText
    case pin
    case colour
    case measure
    case scan
}

public enum HomeKeymap {

    /// One letter per action, chosen to be the word's own first letter
    /// wherever two did not collide. The ones that could not be — Camera
    /// (C is the clipboard), Calendar, Colour, Measure, Scan (S is the
    /// screen) — took the most memorable letter left: caMera, Kalendar,
    /// cOlour, Ruler, Qr.
    public static func key(for action: HomeAction) -> Character {
        switch action {
        case .clipboard: "C"
        case .focus: "F"
        case .camera: "M"
        case .calendar: "K"
        case .captureArea: "A"
        case .captureWindow: "W"
        case .captureScreen: "S"
        case .copyText: "T"
        case .pin: "P"
        case .colour: "O"
        case .measure: "R"
        case .scan: "Q"
        }
    }

    /// The action for a typed key, in either case. Nothing for any key that
    /// is not on the map — the island ignores it rather than guessing.
    public static func action(for key: String) -> HomeAction? {
        guard key.count == 1, let typed = key.uppercased().first else { return nil }
        return HomeAction.allCases.first { self.key(for: $0) == typed }
    }
}
