import Foundation

/// Moves preferences saved under their old names onto the new ones.
///
/// Up to 0.8.0 every key was dotted — `modules.enabled`, `gesture.clickToPin`.
/// The `Defaults` library observes keys through key-value observing, which
/// cannot see a key with a dot in it (KVO reads the dot as a key path), and it
/// logs a fault for each one. The visible result: a setting changed in one
/// place did not reach a view observing it somewhere else. The keys are now
/// the same names with `_` for `.`.
///
/// Runs once, at launch, before anything reads a preference. A value already
/// saved under the new name wins, so running it twice changes nothing.
public enum PreferenceMigration {

    /// The prefixes Perch has ever used. Anything else in the domain belongs
    /// to AppKit or a library and is left exactly where it is.
    static let ownedPrefixes = [
        "battery.", "calendar.", "camera.", "clipboard.", "focus.", "gesture.",
        "hideNotch.", "hud.", "island.", "modules.", "notifications.", "nowPlaying.",
        "shelf.", "shortcuts.", "systemstats."
    ]

    /// Returns the keys it moved, for the test.
    ///
    /// Reads the saved domain rather than `object(forKey:)`, because the
    /// registration domain answers `object(forKey:)` too: `Defaults`
    /// registers a default for every key, so "is there already a value under
    /// the new name" was always yes and nothing was ever moved. The test
    /// suite found that before a user did.
    @discardableResult
    public static func migrateDottedKeys(
        in defaults: UserDefaults = .standard,
        domain: String? = Bundle.main.bundleIdentifier
    ) -> [String] {
        guard let domain, let saved = defaults.persistentDomain(forName: domain) else { return [] }
        var moved: [String] = []

        for (key, value) in saved where ownedPrefixes.contains(where: key.hasPrefix) {
            let renamed = key.replacingOccurrences(of: ".", with: "_")
            if saved[renamed] == nil {
                defaults.set(value, forKey: renamed)
            }
            defaults.removeObject(forKey: key)
            moved.append(key)
        }

        return moved.sorted()
    }
}
