import Foundation

/// A join link found in an event, and which service it belongs to.
///
/// Six services, because that is what `docs/FEATURES.md` §5 promises and
/// what the paid field covers between them. The detector is pure and every
/// pattern has a test (TC-CAL-004); a service nobody matched is no link at
/// all rather than a button that opens a browser tab and shrugs
/// (TC-CAL-005).
public struct MeetingLink: Equatable, Sendable, Hashable {

    public enum Service: String, Equatable, Sendable, CaseIterable {
        case meet
        case zoom
        case teams
        case webex
        case around
        case whereby

        public var displayName: String {
            switch self {
            case .meet: "Google Meet"
            case .zoom: "Zoom"
            case .teams: "Microsoft Teams"
            case .webex: "Webex"
            case .around: "Around"
            case .whereby: "Whereby"
            }
        }

        /// The bundle identifier of the native client, where the join button
        /// should land. `nil` means the service is browser-only, which is
        /// true of Around and Whereby.
        ///
        /// Used by module 5's meeting controls to know which app to talk to
        /// once the call is running (TC-CAL-008).
        public var bundleID: String? {
            switch self {
            case .zoom: "us.zoom.xos"
            case .teams: "com.microsoft.teams2"
            case .webex: "Cisco-Systems.Spark"
            case .meet, .around, .whereby: nil
            }
        }
    }

    public let service: Service

    /// The link exactly as it was written in the event. Opened as-is unless
    /// `appURL` offers something better.
    public let url: URL

    public init(service: Service, url: URL) {
        self.service = service
        self.url = url
    }

    /// The URL that opens the native client directly, skipping the browser
    /// bounce page.
    ///
    /// Only Zoom publishes a documented scheme worth using — `zoommtg://`,
    /// which its own web page redirects to anyway. Everything else opens
    /// the https URL and lets macOS route it: Teams and Webex both register
    /// as handlers for their own domains, so the native app gets it when it
    /// is installed and the browser gets it when it is not, which is the
    /// right answer either way.
    public var appURL: URL? {
        guard service == .zoom else { return nil }
        guard let identifier = Self.zoomConferenceID(in: url) else { return nil }

        var components = URLComponents()
        components.scheme = "zoommtg"
        components.host = "zoom.us"
        components.path = "/join"
        components.queryItems = [URLQueryItem(name: "confno", value: identifier)]

        if let password = Self.queryValue("pwd", in: url) {
            components.queryItems?.append(URLQueryItem(name: "pwd", value: password))
        }

        return components.url
    }

    /// Where to send the click. The native client if there is one, the web
    /// link otherwise.
    public var launchURL: URL { appURL ?? url }

    // MARK: - Detection

    /// Finds the first join link across an event's three text fields.
    ///
    /// The order matters and is not alphabetical. `url` is the field Google
    /// Calendar, Zoom's own plugin and Teams all fill in, so it is the most
    /// likely to hold the real link rather than a link to the recording, the
    /// agenda document or somebody's profile. `location` is next, because
    /// Outlook puts the join link there. `notes` is last and is the messiest
    /// — it usually holds the whole invitation boilerplate, dial-in numbers
    /// and a second link to a support page.
    public static func detect(
        location: String?,
        notes: String?,
        url: URL?
    ) -> Self? {
        if let url, let link = detect(in: url.absoluteString) { return link }
        if let location, let link = detect(in: location) { return link }
        if let notes, let link = detect(in: notes) { return link }
        return nil
    }

    /// Finds the first join link in a block of text.
    ///
    /// Every candidate is matched against the service patterns in the order
    /// the text presents them, so an invitation that names Zoom in the first
    /// line and links a Google Doc in the second joins the Zoom call.
    public static func detect(in text: String) -> Self? {
        for candidate in urls(in: text) {
            if let service = service(for: candidate) {
                return Self(service: service, url: candidate)
            }
        }
        return nil
    }

    /// Classifies one URL, or refuses it.
    ///
    /// Host and path both have to agree. `zoom.us/download` is not a
    /// meeting, and neither is `teams.microsoft.com` on its own — matching
    /// on the host alone put a dead join button on every invitation that
    /// linked to a vendor's home page.
    public static func service(for url: URL) -> Service? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path

        if host == "meet.google.com" {
            // Meet codes are three-four-three letters. The lobby page
            // (`meet.google.com/` with no code) is not a meeting.
            return path.count > 1 ? .meet : nil
        }

        if host.hasSuffix("zoom.us") || host.hasSuffix("zoomgov.com") {
            return zoomConferenceID(in: url) != nil ? .zoom : nil
        }

        if host == "teams.microsoft.com" || host == "teams.live.com" {
            return path.contains("/meetup-join/") || path.contains("/meet/") ? .teams : nil
        }

        if host.hasSuffix("webex.com") {
            // Personal room, scheduled meeting, and the `j.php` form its
            // invitations actually send.
            let isMeeting =
                path.contains("/meet/") || path.contains("/join/") || path.contains("/j.php")
            return isMeeting ? .webex : nil
        }

        if host == "meet.around.co" || host.hasSuffix(".around.co") {
            return path.count > 1 ? .around : nil
        }

        if host == "whereby.com" || host.hasSuffix(".whereby.com") {
            return path.count > 1 ? .whereby : nil
        }

        return nil
    }

    // MARK: - Plumbing

    /// Pulls http(s) URLs out of free text.
    ///
    /// `NSDataDetector` rather than a regular expression: it already knows
    /// where a URL stops when a full stop, a bracket or a line break follows
    /// it, and invitation boilerplate is full of all three.
    private static func urls(in text: String) -> [URL] {
        guard !text.isEmpty else { return [] }

        guard
            let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range).compactMap { match in
            guard let url = match.url, url.scheme == "https" || url.scheme == "http" else {
                return nil
            }
            return url
        }
    }

    /// The numeric conference id in a Zoom URL, from either shape its
    /// invitations use: `/j/123`, `/wc/join/123`, or `?confno=123`.
    static func zoomConferenceID(in url: URL) -> String? {
        if let confno = queryValue("confno", in: url), !confno.isEmpty {
            return confno
        }

        let components = url.path.split(separator: "/").map(String.init)
        guard let last = components.last else { return nil }

        // A meeting id is nine to eleven digits. Anything else on the end of
        // a zoom.us path — `download`, `signin`, `my` — is not one.
        let isConferenceID = last.count >= 9 && last.allSatisfy(\.isNumber)
        return isConferenceID ? last : nil
    }

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}
