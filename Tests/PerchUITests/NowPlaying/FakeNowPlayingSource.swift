import Foundation
import PerchCore

@testable import PerchUI

/// A `NowPlayingSourcing` that reports whatever a test tells it to.
///
/// This is what makes the Now Playing tests level **U** in the sense
/// `docs/TEST-PLAN.md` means it — no real system services, no sleeping, and
/// the same answer every run on every machine.
@MainActor
final class FakeNowPlayingSource: NowPlayingSourcing {

    var isAvailable = true

    /// What the next read returns.
    var snapshot: NowPlayingSnapshot?

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var readCount = 0
    private(set) var commands: [NowPlayingCommand] = []
    private(set) var seeks: [Duration] = []

    /// Whether the source currently holds anything. A module that is off must
    /// leave this false (TC-MED-007).
    var isRunning: Bool { startCount > stopCount }

    private var onChange: (@MainActor () -> Void)?

    func start(onChange: @escaping @MainActor () -> Void) {
        startCount += 1
        self.onChange = onChange
    }

    func stop() {
        stopCount += 1
        onChange = nil
    }

    func readSnapshot() async -> NowPlayingSnapshot? {
        readCount += 1
        return snapshot
    }

    func perform(_ command: NowPlayingCommand) {
        commands.append(command)
    }

    func seek(to position: Duration) {
        seeks.append(position)
    }

    /// Pretends the outside world changed, the way a real source would.
    func emitChange(_ snapshot: NowPlayingSnapshot?) {
        self.snapshot = snapshot
        onChange?()
    }
}
