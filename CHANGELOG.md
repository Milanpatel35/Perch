# Changelog

All notable changes to Perch. Format follows [Keep a Changelog]; versions
follow [Semantic Versioning]. Entries are generated from Conventional Commit
subjects, so the commit prefix matters — see CONTRIBUTING.md.

The release process that moves `Unreleased` into a version is in RELEASE.md.

## [Unreleased]

### Added
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

### Notes
- Phase 1.2, 1.4 and 1.5 of `docs/PLAN.md` are complete. 1.1 is complete
  apart from CI running on a real remote; 1.3 (the `IslandPanel`) is next.

[Keep a Changelog]: https://keepachangelog.com/en/1.1.0/
[Semantic Versioning]: https://semver.org/spec/v2.0.0.html
