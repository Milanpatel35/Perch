import Foundation

/// The shared motion vocabulary. Every module animates with these, so the
/// whole island moves as one object rather than as a pile of views
/// (`CLAUDE.md` §9).
///
/// Deliberately expressed as plain values in `PerchCore` rather than as
/// SwiftUI `Animation`s: it keeps the Reduce Motion decision testable without
/// a view, and it stops modules inventing their own durations. `PerchUI`
/// translates a token into an actual animation at the point of use.
public enum IslandMotion {

    /// A spring, described the way SwiftUI describes one.
    public struct Spring: Equatable, Sendable {
        public let response: Double
        public let dampingFraction: Double

        public init(response: Double, dampingFraction: Double) {
            self.response = response
            self.dampingFraction = dampingFraction
        }
    }

    /// A cross-fade, used wherever motion is not allowed.
    public struct Fade: Equatable, Sendable {
        public let duration: Duration

        public init(duration: Duration) {
            self.duration = duration
        }
    }

    /// What the UI should actually perform for a given transition.
    public enum Resolved: Equatable, Sendable {
        case spring(Spring)
        case fade(Fade)
    }

    /// The transitions the island can make. One token each — if you find
    /// yourself wanting a new one, you probably want an existing one.
    public enum Token: Equatable, Sendable, CaseIterable {
        /// idle → peek, and peek → idle.
        case peek
        /// peek → expanded, and expanded → peek.
        case expand
        /// Content changing inside an unchanged container.
        case content
        /// Collapsing all the way to idle.
        case collapse
    }

    /// The spring for each token.
    ///
    /// `response: 0.5, damping: 0.8` is the island's signature curve, and the
    /// value the website's `--ease-island` cubic-bezier approximates
    /// (`WEBSITE-PLAN.md` §2). Keep the two in step.
    public static func spring(for token: Token) -> Spring {
        switch token {
        case .peek: Spring(response: 0.42, dampingFraction: 0.82)
        case .expand: Spring(response: 0.50, dampingFraction: 0.80)
        case .content: Spring(response: 0.26, dampingFraction: 0.90)
        case .collapse: Spring(response: 0.38, dampingFraction: 0.86)
        }
    }

    /// The cross-fade used when Reduce Motion is on.
    ///
    /// Shorter than the spring it replaces. A fade that lasts as long as the
    /// spring reads as lag rather than as motion the user asked to remove.
    public static func fade(for token: Token) -> Fade {
        switch token {
        case .peek: Fade(duration: .milliseconds(180))
        case .expand: Fade(duration: .milliseconds(200))
        case .content: Fade(duration: .milliseconds(120))
        case .collapse: Fade(duration: .milliseconds(160))
        }
    }

    /// Resolves a token against the system's Reduce Motion setting.
    ///
    /// This is the **only** place that decision is made. A module that
    /// branches on Reduce Motion itself is a bug — it is how one transition
    /// ends up springing while the rest cross-fade (TC-ISL-012, TC-A11Y-004).
    public static func resolve(
        _ token: Token,
        reduceMotion: Bool
    ) -> Resolved {
        reduceMotion ? .fade(fade(for: token)) : .spring(spring(for: token))
    }

    /// The token for a transition between two presentations.
    public static func token(
        from old: IslandPresentation,
        to new: IslandPresentation
    ) -> Token {
        switch (old, new) {
        case (.idle, _): .peek
        case (_, .idle): .collapse
        case (.peek, .expanded), (.expanded, .peek): .expand
        case (.peek, .peek), (.expanded, .expanded): .content
        }
    }
}
