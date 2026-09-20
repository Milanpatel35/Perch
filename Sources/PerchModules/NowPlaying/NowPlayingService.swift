import AppKit
import Combine
import Defaults
import Foundation
import PerchCore

/// Module 1 — Now Playing.
///
/// Owns the MediaRemote bridge, turns what it reports into a
/// `NowPlayingSnapshot`, and decides — through `NowPlayingTransition`, which
/// is pure and tested — whether that warrants a peek, an in-place update, or
/// taking the island back.
///
/// Costs nothing when off: the bridge is closed, MediaRemote is
/// unregistered, the observers are gone and the activity is withdrawn
/// (TC-MED-007).
@MainActor
final class NowPlayingService: ObservableObject, PerchModule {

    static let moduleID: ModuleID = .nowPlaying

    /// What is playing right now, for the views to read.
    @Published private(set) var snapshot: NowPlayingSnapshot?

    /// Every app seen holding the session this launch. Discovered rather than
    /// hardcoded — a browser tab is as valid a source as Music.app, and in
    /// practice is the common one.
    @Published private(set) var knownSources: [NowPlayingSource] = []

    /// False when MediaRemote is not available on this macOS. The view says
    /// so plainly rather than showing an empty island.
    @Published private(set) var isUnavailable = false

    private(set) var isActive = false

    private let island: IslandController
    private let source: any NowPlayingSourcing
    private var refreshTask: Task<Void, Never>?

    /// The source is injected so the module's rules can be tested without a
    /// private system framework in the loop — see `NowPlayingSourcing`.
    init(island: IslandController, source: (any NowPlayingSourcing)? = nil) {
        self.island = island
        self.source = source ?? MediaRemoteBridge()
    }

    // MARK: - PerchModule

    func activate() {
        guard !isActive else { return }
        isActive = true

        source.start { [weak self] in self?.refresh() }

        guard source.isAvailable else {
            isUnavailable = true
            return
        }

        isUnavailable = false
        refresh()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        refreshTask?.cancel()
        refreshTask = nil

        source.stop()

        snapshot = nil
        island.withdraw(NowPlayingActivity.identifier)
    }

    // MARK: - Transport
    //
    // Deliberately thin. MediaRemote is the source of truth for playback
    // state, so a command is sent and the resulting notification is what
    // updates the island. Optimistically updating here would make the island
    // disagree with the player whenever a command was refused.

    func togglePlayPause() { source.perform(.togglePlayPause) }
    func nextTrack() { source.perform(.nextTrack) }
    func previousTrack() { source.perform(.previousTrack) }

    /// Seeks. The scrubber's drag ends here.
    func seek(to position: Duration) {
        source.seek(to: position)
        refresh()
    }

    /// Brings the app that owns playback to the front. The expanded island's
    /// title is a way back to whatever is playing.
    func revealSource() {
        guard let bundleID = snapshot?.sourceBundleID else { return }
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleID
        )
        // `activate(options:)` rather than `activate()`: the no-argument
        // spelling is newer than the macOS 13 floor this app builds against.
        running.first?.activate(options: [.activateAllWindows])
    }

    // MARK: - Reading

    /// Reads the current state and applies it.
    ///
    /// Coalesced into a single task: a source reports two or three changes
    /// for one track change, and answering each of them separately would
    /// decode the artwork three times.
    private func refresh() {
        guard isActive else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let next = await self.source.readSnapshot()
            guard !Task.isCancelled, self.isActive else { return }
            self.apply(next)
        }
    }

    private func apply(_ next: NowPlayingSnapshot?) {
        let filtered = honouringPreferredSource(next)
        let transition = NowPlayingTransition.between(snapshot, filtered)

        if let filtered { remember(filtered) }
        snapshot = filtered

        switch transition {
        case .unchanged:
            break

        case .withdraw:
            island.withdraw(NowPlayingActivity.identifier)

        case .updateInPlace:
            guard let filtered else { return }
            island.submit(NowPlayingActivity(snapshot: filtered))

        case .peek:
            guard let filtered else { return }
            island.submit(
                NowPlayingActivity(
                    snapshot: filtered,
                    isSneakPeek: Defaults[.nowPlayingSneakPeek]
                )
            )
        }
    }

    /// Applies the per-app source preference (`docs/FEATURES.md` §1).
    ///
    /// Empty means "whichever macOS says is active", which is almost always
    /// right. A pinned source means the island ignores everything else —
    /// including, correctly, showing nothing when the pinned app is silent.
    private func honouringPreferredSource(
        _ snapshot: NowPlayingSnapshot?
    ) -> NowPlayingSnapshot? {
        let preferred = Defaults[.nowPlayingPreferredSource]
        guard !preferred.isEmpty else { return snapshot }
        guard snapshot?.sourceBundleID == preferred else { return nil }
        return snapshot
    }

    private func remember(_ snapshot: NowPlayingSnapshot) {
        guard let bundleID = snapshot.sourceBundleID,
            !knownSources.contains(where: { $0.bundleID == bundleID })
        else { return }

        knownSources.append(
            NowPlayingSource(
                bundleID: bundleID,
                name: snapshot.sourceName ?? bundleID
            )
        )
    }
}
