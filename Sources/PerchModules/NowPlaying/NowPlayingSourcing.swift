import Foundation
import PerchCore

/// Where "what is playing" comes from.
///
/// `NowPlayingService` depends on this rather than on `MediaRemoteBridge`
/// directly, for one reason: `docs/TEST-PLAN.md` defines a level **U** test as
/// having "no UI, no sleeping, **no real system services**", and a unit suite
/// that opens a private system framework is none of those things. It is an
/// integration test wearing a unit test's name, and it behaves like one — it
/// passed on the machine it was written on and crashed on a headless runner
/// with no media session.
///
/// With the source injected, the module's own rules — when to peek, when to
/// update in place, when to take the island back — are tested against a fake,
/// deterministically, in milliseconds. The real MediaRemote path is exercised
/// where it can only honestly be exercised: on a Mac that is playing
/// something. See `MediaRemoteBridgeTests` and the manual checklist.
@MainActor
protocol NowPlayingSourcing: AnyObject {

    /// False when the source cannot report anything on this machine. The
    /// module says so plainly rather than showing an empty island.
    var isAvailable: Bool { get }

    /// Begins watching. `onChange` fires whenever anything about playback
    /// changes, and the service reads afresh rather than trusting a payload.
    func start(onChange: @escaping @MainActor () -> Void)

    /// Stops watching and releases everything. Must be safe to call twice.
    func stop()

    /// The current state, or `nil` if nothing is playing.
    ///
    /// Must always return. A source that can hang is a source that wedges the
    /// module, because the module awaits this.
    func readSnapshot() async -> NowPlayingSnapshot?

    func perform(_ command: NowPlayingCommand)

    func seek(to position: Duration)
}

/// The transport commands the island offers.
///
/// A small enum rather than MediaRemote's raw numbers, so nothing outside the
/// bridge has to know what `4` means.
enum NowPlayingCommand: Equatable, Sendable {
    case togglePlayPause
    case nextTrack
    case previousTrack
}
