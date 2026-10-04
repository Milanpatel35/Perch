import Foundation

/// A site to keep closed during a focus session, as a bare host.
public struct BlockedSite: Hashable, Comparable, Sendable, Codable {

    public let host: String

    /// Takes whatever was typed — `reddit.com`, `www.reddit.com`,
    /// `https://reddit.com/r/all`, `  Reddit.com/  ` — and reduces it to a
    /// host that can be compared. `nil` when there is no host in it
    /// (TC-FOC-010).
    public init?(typed input: String) {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let scheme = text.range(of: "://") {
            text = String(text[scheme.upperBound...])
        }
        // Path, query and fragment first, so an `@` in a path is not read as
        // credentials; then credentials; then a port.
        text = String(text.prefix { !"/?#".contains($0) })
        if let at = text.lastIndex(of: "@") {
            text = String(text[text.index(after: at)...])
        }
        text = String(text.prefix { $0 != ":" })

        // `www.` is noise: blocking reddit.com blocks www.reddit.com anyway,
        // and keeping both would read as a duplicate.
        if text.hasPrefix("www.") {
            text = String(text.dropFirst(4))
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: ".-"))
        guard
            text.contains("."),
            !text.contains(".."),
            text.unicodeScalars.allSatisfy(allowed.contains)
        else { return nil }

        self.host = text
    }

    public init(host: String) {
        self.host = host.lowercased()
    }

    /// The host itself, or any subdomain of it — but never a host that only
    /// *ends* with the same letters. A plain suffix match would block
    /// `notreddit.com` for `reddit.com` (TC-FOC-011).
    public func matches(host candidate: String) -> Bool {
        let candidate = candidate.lowercased()
        return candidate == host || candidate.hasSuffix("." + host)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.host < rhs.host }
}

/// What counts as a distraction while a focus session runs
/// (`docs/FEATURES.md` §4).
///
/// Advisory, and the settings pane says so. Apps are *hidden*, never quit:
/// hiding is reversible and loses no work. Sites are handled one tab at a
/// time, by asking the browser in front what it is showing, because blocking
/// them for real needs root or a network extension — neither of which a free
/// notch app should ask for.
public struct DistractionBlocklist: Equatable, Sendable, Codable {

    public var blocksApps: Bool
    public var blocksSites: Bool

    /// Bundle identifiers.
    public var apps: Set<String>
    public var sites: Set<BlockedSite>

    public init(
        blocksApps: Bool = false,
        blocksSites: Bool = false,
        apps: Set<String> = [],
        sites: Set<BlockedSite> = []
    ) {
        self.blocksApps = blocksApps
        self.blocksSites = blocksSites
        self.apps = apps
        self.sites = sites
    }

    public var watchesApps: Bool { blocksApps && !apps.isEmpty }
    public var watchesSites: Bool { blocksSites && !sites.isEmpty }
    public var isEmpty: Bool { !watchesApps && !watchesSites }

    /// Whether the app that just came to the front should be hidden
    /// (TC-FOC-012).
    ///
    /// A browser never is, listed or not: hiding Safari because one tab is
    /// a distraction takes away the whole browser. Its tabs are the site
    /// rule's job. Perch itself never is either — hiding the island that
    /// shows the countdown would be the opposite of the point.
    public func blocksApp(_ bundleID: String, ownBundleID: String?) -> Bool {
        let id = bundleID.lowercased()
        guard watchesApps, id != ownBundleID?.lowercased() else { return false }
        guard Browser.isBrowser(id) == false else { return false }
        return apps.contains { $0.lowercased() == id }
    }

    /// Whether a page should be taken off the screen. Only ordinary web
    /// pages: a blocklist must never navigate away from a file or a
    /// browser's own pages (TC-FOC-011).
    public func blocksPage(_ address: String) -> Bool {
        guard
            watchesSites,
            let url = URL(string: address),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host
        else { return false }
        return sites.contains { $0.matches(host: host) }
    }

    /// Offered as one click in the settings pane.
    public static let suggestedSites: [BlockedSite] = [
        "youtube.com", "instagram.com", "reddit.com", "x.com",
        "facebook.com", "tiktok.com", "news.ycombinator.com"
    ].map(BlockedSite.init(host:))

    public static let suggestedApps: [String] = [
        "com.hnc.Discord", "com.tinyspeck.slackmacgap", "com.apple.MobileSMS",
        "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram", "com.valvesoftware.steam"
    ]
}

/// The browsers whose front tab Perch knows how to read, and how.
///
/// **Every word of every script comes from this table** (TC-FOC-017). The
/// application name is a constant here, the destination is a constant, and
/// nothing a page or a person typed is ever put into a script — so there is
/// no string to escape and nothing to inject.
public enum Browser: Equatable, Sendable {
    case safari(name: String)
    case chromium(name: String)

    /// Where a blocked tab goes. A blank page rather than one of Perch's
    /// own: a page that explains itself would have to be served from
    /// somewhere, and the honest answer to "where" is nowhere.
    public static let blockedDestination = "about:blank"

    public static func scriptable(_ bundleID: String) -> Self? {
        scriptable[bundleID.lowercased()]
    }

    /// Browsers Perch recognises but cannot read: neither publishes its
    /// front tab to AppleScript. The settings pane names them rather than
    /// letting somebody wonder why reddit still opens in Firefox.
    public static let unsupported: [String: String] = [
        "org.mozilla.firefox": "Firefox",
        "company.thebrowser.browser": "Arc"
    ]

    public static func isBrowser(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        return scriptable[id] != nil || unsupported[id] != nil
    }

    private static let scriptable: [String: Self] = [
        "com.apple.safari": .safari(name: "Safari"),
        "com.apple.safaritechnologypreview": .safari(name: "Safari Technology Preview"),
        "com.google.chrome": .chromium(name: "Google Chrome"),
        "com.google.chrome.canary": .chromium(name: "Google Chrome Canary"),
        "com.microsoft.edgemac": .chromium(name: "Microsoft Edge"),
        "com.brave.browser": .chromium(name: "Brave Browser"),
        "com.vivaldi.vivaldi": .chromium(name: "Vivaldi"),
        "com.operasoftware.opera": .chromium(name: "Opera")
    ]

    public var name: String {
        switch self {
        case .safari(let name), .chromium(let name): name
        }
    }

    /// Returns the front tab's address, or an empty string with no window.
    public var readFrontTab: String {
        """
        with timeout of 2 seconds
            tell application "\(name)"
                if (count of windows) is 0 then return ""
                return \(frontTab)
            end tell
        end timeout
        """
    }

    /// Sends the front tab to `blockedDestination`.
    public var blankFrontTab: String {
        """
        with timeout of 2 seconds
            tell application "\(name)"
                if (count of windows) is 0 then return
                set \(frontTab) to "\(Self.blockedDestination)"
            end tell
        end timeout
        """
    }

    private var frontTab: String {
        switch self {
        case .safari: "URL of front document"
        case .chromium: "URL of active tab of front window"
        }
    }
}

public extension DistractionBlocklist {

    /// Whether blocking should be running right now (TC-FOC-013).
    ///
    /// Only a work phase that is actually counting down. A break is the time
    /// you are *meant* to open reddit; a paused session is one you stepped
    /// away from on purpose; and with nothing listed there is nothing to do,
    /// so not even an observer is added.
    func isEnforced(during timer: PomodoroTimer) -> Bool {
        !isEmpty && timer.isRunning && timer.phase == .work
    }
}
