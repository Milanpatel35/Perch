import Foundation

/// Which notifications reach the island, and what they look like when they
/// get there.
///
/// Every rule in `docs/FEATURES.md` §8 lives here: the per-app list, silent
/// mode during a focus session, de-duplication, and the coalescing that
/// turns nine messages from one person into one activity saying nine. It is
/// a value with no clock and no AX, which is what makes the whole of
/// `TEST-PLAN.md` § NTF a unit block.
public struct NotificationPolicy: Equatable, Sendable {

    /// Whether the list names what is mirrored or what is dropped.
    ///
    /// Deny by default: a mirroring module that starts by showing nothing is
    /// useless, and one that starts by showing everything is at least honest
    /// about what it does. Allow mode is for people who want two apps and
    /// silence from the rest.
    public enum Mode: String, Equatable, Sendable, Codable, CaseIterable {
        case denyListed
        case allowListedOnly
    }

    public struct Configuration: Equatable, Sendable, Codable {
        public var mode: Mode = .denyListed

        /// Bundle identifiers. The meaning depends on `mode`.
        public var apps: Set<String> = []

        /// Hold notifications while a focus session is running, and release
        /// them when it ends (`docs/FEATURES.md` §8).
        ///
        /// Held, not dropped. A notification the island swallowed entirely
        /// is a notification you never find out about, and that is a bug
        /// report rather than a feature (TC-NTF-005, TC-NTF-006).
        public var silentDuringFocus = true

        /// How long two notifications from one app may be apart and still
        /// count as one arrival.
        ///
        /// Eight seconds. Long enough to catch a burst of messages typed as
        /// one thought, short enough that a reply half a minute later is its
        /// own event.
        public var coalescingWindow: Duration = .seconds(8)

        public init() {}
    }

    public private(set) var configuration: Configuration

    /// Fingerprints already seen, newest last. Bounded — see `remember`.
    private var seen: [String] = []

    /// Notifications held while a focus session runs, in arrival order.
    public private(set) var held: [MirroredNotification] = []

    /// What is on the island now, if anything.
    public private(set) var current: Burst?

    /// One app's recent notifications, presented as a single activity.
    ///
    /// The count is what makes this worth having: nine messages from one
    /// person is one island entry saying nine, not nine entries fighting
    /// over the notch (TC-NTF-004).
    public struct Burst: Equatable, Sendable {
        public var latest: MirroredNotification
        public var count: Int
        public var firstAt: Date

        public var appName: String { latest.appName }
        public var bundleID: String? { latest.bundleID }
    }

    /// Perch does not mirror Perch. The island announcing its own
    /// announcements is a loop with a UI (TC-NTF-012).
    public static let ownBundleIDs: Set<String> = ["app.perch.Perch"]

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public mutating func setConfiguration(_ configuration: Configuration) {
        self.configuration = configuration
    }

    // MARK: - The decision

    /// What the module should do about a notification that just arrived.
    public enum Outcome: Equatable, Sendable {
        /// Put this burst on the island.
        case present(Burst)

        /// Keep it until the focus session ends.
        case hold

        /// Not ours to show.
        case drop
    }

    /// The whole filter, in the order the rules have to be applied.
    ///
    /// Order matters and is not arbitrary. Perch's own notifications go
    /// first because nothing else should even consider them; the app list
    /// goes before de-duplication so that a dropped app never fills the seen
    /// list; and focus mode goes last, because a notification held through a
    /// session must be one that would genuinely have been shown.
    public mutating func receive(
        _ notification: MirroredNotification,
        isFocusSessionRunning: Bool = false,
        isDoNotDisturbOn: Bool = false
    ) -> Outcome {
        guard !isOwn(notification) else { return .drop }
        guard allows(notification) else { return .drop }

        // TC-NTF-007. The system already decided you did not want to be
        // interrupted; mirroring the banner would be Perch overruling it.
        guard !isDoNotDisturbOn else { return .drop }

        guard !hasSeen(notification) else { return .drop }
        remember(notification)

        guard !(isFocusSessionRunning && configuration.silentDuringFocus) else {
            held.append(notification)
            return .hold
        }

        return .present(add(notification))
    }

    /// Releases everything held, coalesced per app, oldest first.
    ///
    /// Called when a focus session ends. Returns one burst per app rather
    /// than one per notification: coming out of an hour of focus to fourteen
    /// island activities queued up would be its own kind of interruption
    /// (TC-NTF-006).
    public mutating func releaseHeld() -> [Burst] {
        guard !held.isEmpty else { return [] }

        var bursts: [Burst] = []
        var indexByApp: [String: Int] = [:]

        for notification in held {
            let key = notification.bundleID ?? notification.appName

            if let index = indexByApp[key] {
                bursts[index].latest = notification
                bursts[index].count += 1
            } else {
                indexByApp[key] = bursts.count
                bursts.append(
                    Burst(latest: notification, count: 1, firstAt: notification.receivedAt)
                )
            }
        }

        held.removeAll()
        current = bursts.last
        return bursts
    }

    /// Drops what is on the island. The module calls this when the activity
    /// is dismissed or times out, so the next notification from the same app
    /// starts a fresh count rather than continuing an invisible one.
    public mutating func clearCurrent() {
        current = nil
    }

    public mutating func reset() {
        seen.removeAll()
        held.removeAll()
        current = nil
    }

    // MARK: - The rules

    private func isOwn(_ notification: MirroredNotification) -> Bool {
        guard let bundleID = notification.bundleID else { return false }
        return Self.ownBundleIDs.contains(bundleID)
    }

    /// TC-NTF-001 and TC-NTF-002.
    ///
    /// A notification whose banner named no app can never be on a list, so
    /// deny mode shows it and allow mode does not. That is the reading that
    /// keeps allow mode's promise: *only* these apps.
    public func allows(_ notification: MirroredNotification) -> Bool {
        switch configuration.mode {
        case .denyListed:
            guard let bundleID = notification.bundleID else { return true }
            return !configuration.apps.contains(bundleID)
        case .allowListedOnly:
            guard let bundleID = notification.bundleID else { return false }
            return configuration.apps.contains(bundleID)
        }
    }

    private func hasSeen(_ notification: MirroredNotification) -> Bool {
        seen.contains(notification.fingerprint)
    }

    /// Bounded at 64. The list exists to catch a banner redrawn seconds ago,
    /// not to remember yesterday — and an unbounded set in a module that
    /// runs all day is a leak with a nice name.
    private mutating func remember(_ notification: MirroredNotification) {
        seen.append(notification.fingerprint)
        if seen.count > 64 {
            seen.removeFirst(seen.count - 64)
        }
    }

    /// Adds to the current burst, or starts a new one.
    ///
    /// Same app and inside the window: the count goes up and the newest
    /// message is what is shown. Anything else replaces it.
    private mutating func add(_ notification: MirroredNotification) -> Burst {
        let key = notification.bundleID ?? notification.appName
        let currentKey = current.map { $0.bundleID ?? $0.appName }

        let isSameBurst =
            currentKey == key
            && current.map {
                notification.receivedAt.timeIntervalSince($0.latest.receivedAt)
                    <= configuration.coalescingWindow.seconds
            } == true

        if isSameBurst, var burst = current {
            burst.latest = notification
            burst.count += 1
            current = burst
            return burst
        }

        let burst = Burst(latest: notification, count: 1, firstAt: notification.receivedAt)
        current = burst
        return burst
    }
}
