# Changelog

All notable changes to Perch. Format follows [Keep a Changelog]; versions
follow [Semantic Versioning]. Entries are generated from Conventional Commit
subjects, so the commit prefix matters — see CONTRIBUTING.md.

The release process that moves `Unreleased` into a version is in RELEASE.md.

## [Unreleased]

Nothing yet. Next up is Phase 2.3 — HUDs, battery and the focus timer.

## [0.3.0] — 2026-09-20

Three of eighteen modules. The two that turn Perch from a toy into a tool.

### Added
- **Clipboard history** (module 3) — the single biggest gap in the paid
  field. Text, rich text, images, file paths and colours; a searchable picker
  on a global shortcut; pinning; retention by count and age; paste as plain
  text; and on-device OCR of copied images. Password managers are excluded
  out of the box, and a concealed pasteboard type is never recorded at all.
- **Shelf** (module 2). Drag a file to the notch and it waits there: across
  app switches, Space changes and relaunches. Drag it back out to anywhere.
  Folders count as one item, text and image selections become clippings, and
  the share sheet — which is where AirDrop lives — is one click away.
- **File conversion in the shelf.** HEIC, PNG, TIFF and WebP to JPEG, PNG or
  HEIC; MOV to MP4. ImageIO and AVFoundation only: no ffmpeg, no bundled
  binary, nothing extra to notarise. There is a test that asserts no
  ffmpeg-shaped library is linked into the process.
- The island is a drop target whatever is currently on it, so dragging a file
  to the notch works while music is playing.

### Notes
- The clipboard contains Perch's **only polling loop**, and it is the
  documented exception to `CLAUDE.md` §5.1 — `NSPasteboard` has no
  notification of any kind. 600ms, only while the module is on, suspended on
  screen lock and on sleep. See
  [ADR 0003](docs/adr/0003-polling-the-pasteboard.md).
- The clipboard's global shortcut has **no default**. One that claims a
  hotkey without being asked will collide with something, silently.
- Files are **copied** into Perch's own folder, never moved. The original
  stays where you dragged it from.
- Clear-on-quit is **off** by default. A shelf that empties itself without
  being asked has lost somebody's file.

## [0.2.0] — 2026-09-20

First release with something on screen. The island exists, it moves, and one
of the eighteen modules is in it.

### Added
- **Now Playing** (module 1). Artwork, title and artist beside the notch, a
  visualiser that stops dead on pause, expanded transport with a working seek
  scrubber, the output-device picker, per-app source switching, a two-second
  sneak peek on track change, and swipe to skip. Built on `MediaRemote`
  through a `dlopen`'d bridge that degrades to "unavailable" rather than
  breaking the app — [ADR 0002](docs/adr/0002-mediaremote-for-now-playing.md).
- `PerchModule` and `ModuleHost` — the lifecycle every module is switched on
  and off through, and the thing that guarantees an off module costs nothing.
- `MarqueeText` — a title that scrolls only when it has to, only while it is
  on screen, and not at all with Reduce Motion on.
- A Preferences window with a sidebar, one pane per module, that does not need
  a list of panes kept in step with the list of modules.
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

### Changed
- Now Playing takes its source as a parameter (`NowPlayingSourcing`) rather
  than reaching for MediaRemote directly. The module's rules are tested
  against a fake, deterministically; the private-framework path is verified
  on a Mac that is playing something (TC-MED-011). A unit test that opens a
  private system framework is an integration test wearing a unit test's name.

### Fixed
- Reading from MediaRemote could trap the process. Closures written inside
  the `@MainActor` bridge were *inferred* to be main-actor isolated, so Swift
  put an isolation assertion at the top of each one — and MediaRemote invokes
  them on its own XPC reply queue, where that assertion fires. They are
  `@Sendable` now, which says the true thing.
- A MediaRemote read that never came back left its continuation suspended
  forever, holding everything the awaiting task had captured. Every read now
  answers exactly once, with a one-shot watchdog behind it.
- `deinit` no longer uses `MainActor.assumeIsolated` anywhere. It traps if the
  last reference is released on another thread, which with modules handing
  references to background callbacks is a matter of timing. Teardown is
  explicit and called from `applicationWillTerminate`.
- Switching the Now Playing module off and on twice crashed the app. The
  MediaRemote bridge `dlclose`d the framework, and unloading that image out
  from under its process-wide notification registration is not survivable.
  The handle is now kept for the life of the process; what teardown actually
  needs — dropping the registration and every function pointer — is unchanged.
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

[0.3.0]: https://github.com/Milanpatel35/Perch/releases/tag/v0.3.0
[0.2.0]: https://github.com/Milanpatel35/Perch/releases/tag/v0.2.0

[Keep a Changelog]: https://keepachangelog.com/en/1.1.0/
[Semantic Versioning]: https://semver.org/spec/v2.0.0.html
