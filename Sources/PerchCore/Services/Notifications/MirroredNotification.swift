import Foundation

/// One notification, as the island sees it.
///
/// Built by `NotificationWatcher` from the banner's accessibility tree and
/// nothing else. There is no public API that hands an app somebody else's
/// notifications, and the private database is behind Full Disk Access —
/// ADR 0007 records both, and why the banner is the honest way in.
///
/// A value, so every rule about which ones reach the island is a unit test.
public struct MirroredNotification: Equatable, Sendable, Identifiable {

    public let id: String

    /// The app that posted it. `bundleID` is `nil` when the banner does not
    /// name one, which happens for a handful of system notifications — they
    /// are still mirrored, they just cannot be filtered by app.
    public let appName: String
    public let bundleID: String?

    public let title: String

    /// The second line. Usually the sender for a message, the sender's
    /// address for mail, empty for most other things.
    public let subtitle: String?

    public let body: String

    /// When Perch saw it. Not when it was posted — a banner does not say.
    public let receivedAt: Date

    /// Whether the banner offered a reply field. Only Messages and Mail do,
    /// and only for some of their notifications (TC-NTF-010).
    public let canReply: Bool

    public init(
        id: String,
        appName: String,
        bundleID: String? = nil,
        title: String,
        subtitle: String? = nil,
        body: String,
        receivedAt: Date,
        canReply: Bool = false
    ) {
        self.id = id
        self.appName = appName
        self.bundleID = bundleID
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.receivedAt = receivedAt
        self.canReply = canReply
    }

    /// What makes two banners the same notification.
    ///
    /// macOS redraws a banner when it slides, when it is moved by another
    /// arriving behind it, and when it is re-posted after a Focus ends. All
    /// three produce a fresh AX window for the same message, so identity is
    /// the content rather than the window (TC-NTF-003).
    public var fingerprint: String {
        [bundleID ?? appName, title, subtitle ?? "", body].joined(separator: "\u{1}")
    }
}
