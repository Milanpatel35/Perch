# Changelog

All notable changes to Perch. Format follows [Keep a Changelog]; versions
follow [Semantic Versioning]. Entries are generated from Conventional Commit
subjects, so the commit prefix matters — see CONTRIBUTING.md.

The release process that moves `Unreleased` into a version is in RELEASE.md.

## [Unreleased]

### Added
- `IslandPanel` — the borderless, non-activating panel the island lives in,
  above the menu bar, on every Space, over full-screen apps, and never
  taking key focus from the app in front.
- `IslandPanelController` — places the panel and re-anchors it on every
  display change, hot-plug, arrangement change and wake, by recomputing
  rather than patching.
- `IslandLayout` — the panel's frame, sized once per screen so the island
  animates inside a fixed window instead of resizing one sixty times a
  second.
- `IslandController` — the runtime around the reducer. Turns effects into
  work, and guarantees exactly one pending collapse.
- `AnyIslandActivity` — the box all seventeen modules' activities travel in.
- The island's home surface: a real `ambient` activity rather than a special
  case in the reducer, so hover-to-open works through the same path a module
  does.
- The app itself — menu-bar item, settings window, module switchboard, and
  the permission strings every module will ask with.
- The island state machine (`IslandReducer`) — pure, effect-returning, and
  the layer all eighteen modules are written against.
- `ActivityQueue` — bounded and priority-ordered. A flood of low-priority
  activities cannot evict a system alert.
- `NotchMetrics` — notch geometry derived entirely from the screen's own
  safe-area insets, with a virtual pill for Macs that have no notch.
- `IslandMotion` — the shared spring tokens, and the Reduce Motion
  cross-fade path resolved in exactly one place.
- `project.yml` and `.swiftlint.yml`, including custom rules that block
  AppKit imports inside `PerchCore` and tool attribution anywhere.

### Fixed
- `.swiftlint.yml` custom rules used `include:` where SwiftLint expects
  `included:`, so the "PerchCore must stay UI-free" rule silently applied to
  every file in the repository instead of to Core.
- Debug builds no longer force a universal binary. Only the release
  configuration does, which is the one that ships.
- Framework targets now generate an `Info.plist`, without which a macOS
  framework bundle cannot be code-signed at all.

### Notes
- **Phase 1 of `docs/PLAN.md` is complete.** The island is on screen, at
  `.statusBar + 1`, centred on the notch, and collapses and expands with the
  shared motion tokens.

[Keep a Changelog]: https://keepachangelog.com/en/1.1.0/
[Semantic Versioning]: https://semver.org/spec/v2.0.0.html
