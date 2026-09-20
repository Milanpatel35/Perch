import AppKit
import Combine
import PerchCore
import SwiftUI

/// Translates a `IslandMotion.Token` into an actual SwiftUI animation.
///
/// `PerchCore` decides *what kind* of motion a transition gets; this decides
/// how SwiftUI spells it. Keeping the decision in Core is what makes
/// TC-ISL-012 a unit test instead of a screen recording.
public enum IslandAnimation {

    /// The animation for a token, given the current Reduce Motion state.
    public static func animation(
        for token: IslandMotion.Token,
        reduceMotion: Bool
    ) -> Animation {
        switch IslandMotion.resolve(token, reduceMotion: reduceMotion) {
        case .spring(let spring):
            .spring(
                response: spring.response,
                dampingFraction: spring.dampingFraction
            )
        case .fade(let fade):
            .easeInOut(duration: fade.duration.seconds)
        }
    }
}

/// Publishes the system's Reduce Motion flag.
///
/// One observer for the whole app. A module that reads the flag itself is a
/// bug — it is how one transition ends up springing while the rest cross-fade
/// (`CLAUDE.md` §9).
@MainActor
public final class MotionPreferences: ObservableObject {

    @Published public private(set) var reduceMotion: Bool

    private var cancellable: AnyCancellable?

    public init() {
        let workspace = NSWorkspace.shared
        self.reduceMotion = workspace.accessibilityDisplayShouldReduceMotion

        // Event-driven, not polled. `CLAUDE.md` §5.1.
        cancellable = workspace.notificationCenter
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reduceMotion =
                    NSWorkspace.shared
                    .accessibilityDisplayShouldReduceMotion
            }
    }

    public func animation(for token: IslandMotion.Token) -> Animation {
        IslandAnimation.animation(for: token, reduceMotion: reduceMotion)
    }
}
