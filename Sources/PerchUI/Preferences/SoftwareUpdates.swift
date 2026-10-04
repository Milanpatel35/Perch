import Combine
import Foundation

/// What Settings knows about updates, and the two things it can ask for.
///
/// Sparkle lives in the app target, where it is linked; `PerchUI` never
/// imports it. The app makes one of these, drives it from Sparkle's
/// callbacks, and hands it to the preferences window — so the pane can show
/// "up to date" or "0.13.0 is available" without knowing how either was
/// found out.
///
/// The update feed is the one request Perch makes by default
/// (`CLAUDE.md` §5.2), and this is where it can be turned off.
@MainActor
public final class SoftwareUpdates: ObservableObject {

    public enum Status: Equatable, Sendable {
        /// Never checked in this run of the app.
        case unknown
        case checking
        case upToDate
        case available(version: String)
        /// The feed could not be reached or read. Said, never alarming:
        /// an offline Mac is not an error (TC-UPD-002).
        case failed(reason: String)
    }

    @Published public private(set) var status: Status = .unknown
    @Published public private(set) var lastChecked: Date?

    /// Whether a check can start now — false while one is already running.
    @Published public private(set) var canCheck = true

    /// Daily, in the background. Off means Perch makes no request at all
    /// unless somebody presses the button.
    @Published public var checksAutomatically: Bool {
        didSet {
            guard checksAutomatically != oldValue else { return }
            setChecksAutomatically(checksAutomatically)
        }
    }

    private var check: () -> Void
    private var setChecksAutomatically: (Bool) -> Void

    /// - Parameters:
    ///   - checksAutomatically: The current setting, as the updater has it.
    ///   - check: Starts a check that shows its own window — the found
    ///     update, or "you're up to date".
    ///   - setChecksAutomatically: Writes the setting back to the updater.
    public init(
        checksAutomatically: Bool,
        lastChecked: Date?,
        check: @escaping () -> Void,
        setChecksAutomatically: @escaping (Bool) -> Void
    ) {
        self.checksAutomatically = checksAutomatically
        self.lastChecked = lastChecked
        self.check = check
        self.setChecksAutomatically = setChecksAutomatically
    }

    /// Connects to the updater once it has started. The app has to make
    /// this object before the updater exists — the updater's delegate is
    /// the thing that owns it — so the first closures are placeholders.
    public func replace(
        checksAutomatically: Bool,
        lastChecked: Date?,
        check: @escaping () -> Void,
        setChecksAutomatically: @escaping (Bool) -> Void
    ) {
        self.check = check
        self.setChecksAutomatically = setChecksAutomatically
        self.checksAutomatically = checksAutomatically
        self.lastChecked = lastChecked
    }

    public func checkNow() {
        guard canCheck else { return }
        check()
    }

    // MARK: - Driven by the updater

    public func began() {
        status = .checking
        canCheck = false
    }

    public func finished(_ status: Status, at date: Date = Date()) {
        self.status = status
        lastChecked = date
        canCheck = true
    }

    /// For a check that ended without saying how — a window closed, a
    /// download cancelled.
    public func settle() {
        if status == .checking { status = .unknown }
        canCheck = true
    }
}
