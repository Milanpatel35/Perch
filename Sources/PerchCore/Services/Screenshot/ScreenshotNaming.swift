import Foundation

/// What a saved capture is called, and where it goes.
public enum ScreenshotNaming {

    /// Matches the shape macOS gives its own screenshots —
    /// "Screenshot 2026-10-03 at 14.32.05.png" — so Perch's sort beside
    /// them (TC-SCR-007).
    ///
    /// A fixed locale, because a file name is not interface text: a
    /// localised one sorts differently per person. Full stops in the time
    /// rather than colons, which Finder shows as slashes.
    public static func filename(
        for date: Date,
        timeZone: TimeZone = .current,
        fileExtension: String = "png"
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: date)).\(fileExtension)"
    }

    /// `name`, or `name (2)`, `name (3)` … — the first one not in `taken`.
    /// Two captures inside one second would otherwise share a name, and the
    /// second would overwrite the first.
    public static func unique(_ name: String, avoiding taken: (String) -> Bool) -> String {
        guard taken(name) else { return name }

        let url = URL(fileURLWithPath: name)
        let stem = url.deletingPathExtension().lastPathComponent
        let suffix = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"

        var counter = 2
        while taken("\(stem) (\(counter))\(suffix)") {
            counter += 1
        }
        return "\(stem) (\(counter))\(suffix)"
    }
}

/// The folder macOS saves its own screenshots to.
///
/// Perch's go to the same place, so nobody has two screenshot folders. The
/// setting is whatever the Screenshot app's Options menu last chose — read,
/// never written (TC-SCR-006).
public enum ScreenshotLocation {

    /// The defaults domain and key the Screenshot app stores it under.
    public static let domain = "com.apple.screencapture"
    public static let key = "location"

    /// - Parameters:
    ///   - stored: The raw stored value, which may start with `~`.
    ///   - home: The home directory, for expanding `~` and the fallback.
    ///   - isDirectory: Whether a path is a directory that exists.
    public static func resolve(
        stored: String?,
        home: URL,
        isDirectory: (URL) -> Bool
    ) -> URL {
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)

        guard let stored = stored?.trimmingCharacters(in: .whitespacesAndNewlines),
            !stored.isEmpty
        else { return desktop }

        let candidate: URL
        if stored == "~" {
            candidate = home
        } else if stored.hasPrefix("~/") {
            candidate = home.appendingPathComponent(String(stored.dropFirst(2)), isDirectory: true)
        } else {
            candidate = URL(fileURLWithPath: stored, isDirectory: true)
        }

        // A folder that was renamed or a disk that is not plugged in. The
        // Desktop is where macOS itself falls back to.
        return isDirectory(candidate) ? candidate : desktop
    }
}
