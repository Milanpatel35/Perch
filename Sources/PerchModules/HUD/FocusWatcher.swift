import Foundation
import PerchCore

/// Watches Focus modes, Do Not Disturb included.
///
/// Do Not Disturb has been a Focus since Monterey, so this is one HUD rather
/// than the two `docs/FEATURES.md` §6 lists — the second row is the first row
/// with a different name on it.
///
/// **Two event sources, both push, because neither alone is reliable.**
/// macOS posts a distributed notification when the state changes, and it also
/// rewrites `~/Library/DoNotDisturb/DB/Assertions.json`. The notification is
/// undocumented and has been renamed before; the file is where the state
/// actually lives. Watching the file with a kqueue is public API and costs
/// nothing when nothing is happening, so both are used and `HUDPolicy` drops
/// the duplicate.
@MainActor
final class FocusWatcher {

    /// Undocumented, and the reason the file watch exists as well.
    private static let notificationName = "com.apple.donotdisturb.state"

    private static var databaseDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
    }

    private var onChange: (@MainActor (HUDReading) -> Void)?
    private var observer: NSObjectProtocol?
    private var fileSource: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1

    func start(onChange: @escaping @MainActor (HUDReading) -> Void) {
        guard observer == nil, fileSource == nil else { return }
        self.onChange = onChange

        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(Self.notificationName),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { self.report() }
        }

        watchDatabase()
    }

    func stop() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observer = nil

        fileSource?.cancel()
        fileSource = nil

        onChange = nil
    }

    /// Whether any Focus — Do Not Disturb included — is on right now.
    ///
    /// Read on demand rather than watched. The notification module asks once
    /// per banner, which is as event-driven as a question gets, and it means
    /// only one thing in the app ever holds the kqueue (TC-NTF-007).
    var isFocusOn: Bool { activeFocus() != nil }

    /// The current state, for seeding the policy at activation.
    func reading() -> HUDReading {
        guard let focus = activeFocus() else {
            return HUDReading(kind: .focus, title: "Focus off")
        }
        return HUDReading(kind: .focus, title: focus, detail: "Focus on")
    }

    // MARK: - Internals

    private func report() {
        onChange?(reading())
    }

    /// A kqueue on the directory rather than on the file.
    ///
    /// macOS replaces `Assertions.json` rather than editing it in place, and
    /// a descriptor held on the old file goes deaf the first time that
    /// happens. Watching the directory survives the swap.
    private func watchDatabase() {
        let directory = Self.databaseDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { return }

        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.report() }
        }
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        source.resume()

        fileSource = source
    }

    /// The name of the Focus currently on, or `nil` when none is.
    ///
    /// The shape of `Assertions.json` is macOS's own and undocumented, so
    /// every step is optional and a file that does not parse means "no Focus"
    /// rather than a crash. The worst case is a HUD that says "Focus on"
    /// without naming it.
    private func activeFocus() -> String? {
        let directory = Self.databaseDirectory
        guard
            let data = try? Data(
                contentsOf: directory.appendingPathComponent("Assertions.json")
            ),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let records = root["data"] as? [[String: Any]]
        else { return nil }

        let assertions =
            records
            .compactMap { $0["storeAssertionRecords"] as? [[String: Any]] }
            .flatMap { $0 }

        guard let assertion = assertions.first else { return nil }

        let details = assertion["assertionDetails"] as? [String: Any]
        let identifier =
            details?["assertionDetailsModeIdentifier"] as? String
            ?? assertion["modeIdentifier"] as? String

        guard let identifier else { return "Focus" }
        return name(forMode: identifier) ?? friendly(identifier)
    }

    private func name(forMode identifier: String) -> String? {
        guard
            let data = try? Data(
                contentsOf: Self.databaseDirectory
                    .appendingPathComponent("ModeConfigurations.json")
            ),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let configurations = root["data"] as? [[String: Any]]
        else { return nil }

        for configuration in configurations {
            guard let modes = configuration["modeConfigurations"] as? [String: Any] else {
                continue
            }
            guard
                let mode = modes[identifier] as? [String: Any],
                let details = mode["mode"] as? [String: Any],
                let name = details["name"] as? String,
                !name.isEmpty
            else { continue }

            return name
        }
        return nil
    }

    /// `com.apple.donotdisturb.mode.default` → "Do Not Disturb". A fallback
    /// for when the configuration file cannot be read; better than showing
    /// somebody a reverse-DNS string.
    private func friendly(_ identifier: String) -> String {
        switch identifier {
        case "com.apple.donotdisturb.mode.default": "Do Not Disturb"
        case "com.apple.sleep.sleep-mode": "Sleep"
        case "com.apple.focus.work": "Work"
        case "com.apple.focus.personal": "Personal"
        case "com.apple.focus.reading": "Reading"
        case "com.apple.focus.mindfulness": "Mindfulness"
        case "com.apple.focus.fitness": "Fitness"
        case "com.apple.focus.gaming": "Gaming"
        case "com.apple.donotdisturb.mode.driving": "Driving"
        default: "Focus"
        }
    }
}
