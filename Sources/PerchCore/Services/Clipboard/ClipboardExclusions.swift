import Foundation

/// What the clipboard refuses to remember.
///
/// Two separate mechanisms, and both matter.
///
/// **Concealed types.** `NSPasteboard` has a type
/// (`org.nspasteboard.ConcealedType`) that means "do not record this". Every
/// serious password manager sets it. Perch honours it unconditionally: there
/// is no setting, no override, and no way for a user to switch it off,
/// because the app that set it knows better than the person clicking a
/// checkbox (TC-CLP-007).
///
/// **Excluded applications.** A belt-and-braces list for apps that ought to
/// set the concealed type and do not, or set it only sometimes. Shipped
/// populated rather than empty — a clipboard manager whose defaults record
/// your password manager is not a neutral default, it is a bug you find
/// later (TC-CLP-006).
public struct ClipboardExclusions: Equatable, Sendable, Codable {

    /// Excluded out of the box.
    ///
    /// Bundle identifiers rather than names: a renamed or localised app must
    /// still be excluded, and a malicious app named "1Password" must not be
    /// included by accident.
    public static let defaultBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.1password.1password7",
        "com.agilebits.onepassword",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.lastpass.LastPass",
        "com.lastpass.lastpassmacdesktop",
        "com.dashlane.dashlanephonefinal",
        "in.sinew.Enpass-Desktop",
        "com.keepassium.mac",
        "org.keepassxc.keepassxc",
        "com.strongbox.mac.strongbox",
        "com.proton.pass.electron"
    ]

    public var bundleIDs: Set<String>

    public init(bundleIDs: Set<String> = Self.defaultBundleIDs) {
        self.bundleIDs = bundleIDs
    }

    public mutating func exclude(_ bundleID: String) {
        bundleIDs.insert(bundleID)
    }

    public mutating func include(_ bundleID: String) {
        bundleIDs.remove(bundleID)
    }

    /// Whether the clipboard may record something.
    ///
    /// - Parameters:
    ///   - bundleID: whatever was frontmost when the copy happened. `nil`
    ///     means the source could not be determined, which is not by itself a
    ///     reason to refuse — plenty of ordinary copies come from a process
    ///     Perch cannot name.
    ///   - isConcealed: whether the pasteboard carried a concealed type.
    public func allowsCapture(
        from bundleID: String?,
        isConcealed: Bool
    ) -> Bool {
        // Unconditional. Not a preference, and deliberately checked first.
        if isConcealed { return false }

        guard let bundleID else { return true }
        return !bundleIDs.contains(bundleID)
    }

    /// Whether this is one of the identifiers Perch ships excluded.
    ///
    /// The settings pane uses it to mark a row as "excluded by default", so
    /// somebody removing one can see they are removing a default rather than
    /// something they added.
    public func isDefault(_ bundleID: String) -> Bool {
        Self.defaultBundleIDs.contains(bundleID)
    }
}
