import Foundation

/// The Shortcuts that appear as buttons on the island (`docs/FEATURES.md` §13).
///
/// Kept by name, because a name is all the `shortcuts` tool gives out and
/// all it takes back. Ordered, because the order is the order of the buttons.
public struct ShortcutFavourites: Equatable, Sendable, Codable {

    /// Six fit on one row of the home surface at a readable size. A seventh
    /// would mean scrolling a row of buttons, which is a menu with worse
    /// manners.
    public static let capacity = 6

    public private(set) var names: [String] = []

    public init(names: [String] = []) {
        for name in names {
            add(name)
        }
    }

    public var isFull: Bool { names.count >= Self.capacity }

    public func contains(_ name: String) -> Bool { names.contains(name) }

    /// Adds to the end. Ignored when full, blank, or already there — the
    /// last one so that ticking a box twice does not make two buttons.
    @discardableResult
    public mutating func add(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isFull, !names.contains(trimmed) else { return false }
        names.append(trimmed)
        return true
    }

    public mutating func remove(_ name: String) {
        names.removeAll { $0 == name }
    }

    /// Moves a favourite one place towards the front (`-1`) or back (`+1`).
    public mutating func move(_ name: String, by offset: Int) {
        guard let index = names.firstIndex(of: name) else { return }
        let target = min(max(index + offset, 0), names.count - 1)
        guard target != index else { return }
        names.remove(at: index)
        names.insert(name, at: target)
    }

    /// Which favourites no longer exist in the Shortcuts library.
    ///
    /// Reported rather than removed: a shortcut renamed in the Shortcuts app
    /// is gone as far as a name can tell, and silently dropping a button
    /// somebody chose is worse than showing it greyed out with the reason.
    /// An empty library means "could not read it", not "you have none", so it
    /// reports nothing missing.
    public func missing(from library: [String]) -> [String] {
        guard !library.isEmpty else { return [] }
        let available = Set(library)
        return names.filter { !available.contains($0) }
    }
}

/// What a Shortcut run came to, in one line the island can draw.
public enum ShortcutOutcome: Equatable, Sendable {
    case succeeded(output: String?)
    case failed(reason: String)

    /// Longest line the island shows.
    public static let maximumLength = 80

    /// Turns the `shortcuts` tool's exit status and output into an outcome.
    ///
    /// The first non-blank line only: a shortcut that returns a document
    /// would otherwise put the document in the notch. A failure with nothing
    /// on stderr still says *something*, because "failed" and silence look
    /// identical from across the room.
    public static func from(exitCode: Int32, output: String, error: String) -> Self {
        if exitCode == 0 {
            return .succeeded(output: firstLine(of: output))
        }
        return .failed(
            reason: firstLine(of: error) ?? String(localized: "Stopped with code \(exitCode)")
        )
    }

    private static func firstLine(of text: String) -> String? {
        let line =
            text
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }

        guard let line else { return nil }
        guard line.count > maximumLength else { return line }
        return String(line.prefix(maximumLength - 1)) + "…"
    }
}
