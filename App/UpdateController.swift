import AppKit
import PerchUI
import Sparkle

/// Sparkle, and the one network request Perch makes by default
/// (`CLAUDE.md` §5.2).
///
/// The feed is `SUFeedURL` in Info.plist — the site's `appcast.xml`, built
/// from the GitHub releases by `Scripts/appcast.sh`. An update is installed
/// only if its EdDSA signature matches `SUPublicEDKey`: a feed or a download
/// that has been tampered with is refused, not installed (TC-UPD-001).
///
/// Sparkle draws its own windows — "a new version is available", the notes,
/// the progress — so this class only starts it and keeps `SoftwareUpdates`
/// told, for the line in Settings.
@MainActor
final class UpdateController: NSObject {

    let updates: SoftwareUpdates

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    override init() {
        // Placeholder closures until `controller` exists; replaced below.
        updates = SoftwareUpdates(
            checksAutomatically: false,
            lastChecked: nil,
            check: {},
            setChecksAutomatically: { _ in }
        )
        super.init()
    }

    /// Starts the updater. A failure — no key, an unreadable feed URL — is
    /// logged by Sparkle and leaves the app running without updates, never
    /// stopped.
    func start() {
        controller.startUpdater()
        let updater = controller.updater
        updates.replace(
            checksAutomatically: updater.automaticallyChecksForUpdates,
            lastChecked: updater.lastUpdateCheckDate,
            check: { [weak self] in self?.checkForUpdates() },
            setChecksAutomatically: { updater.automaticallyChecksForUpdates = $0 }
        )
    }

    @objc func checkForUpdates() {
        updates.began()
        controller.checkForUpdates(nil)
    }
}

extension UpdateController: SPUUpdaterDelegate {

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in self.updates.finished(.available(version: version)) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in self.updates.finished(.upToDate) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let reason = error.localizedDescription
        let isNoUpdate = (error as NSError).code == Int(SUError.noUpdateError.rawValue)
        Task { @MainActor in
            self.updates.finished(isNoUpdate ? .upToDate : .failed(reason: reason))
        }
    }

    nonisolated func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        Task { @MainActor in self.updates.settle() }
    }
}
