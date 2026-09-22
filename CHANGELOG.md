# Changelog

All notable changes to Perch. Format follows [Keep a Changelog]; versions
follow [Semantic Versioning]. Entries are generated from Conventional Commit
subjects, so the commit prefix matters — see CONTRIBUTING.md.

The release process that moves `Unreleased` into a version is in RELEASE.md.

## [Unreleased]

Phases 2.4 and 2.5 — the machine's own interruptions, answered in the notch,
and the two modules nobody else in the field has.

### Added

- **Calendar and meetings** (module 5). The next event with a live countdown
  at a lead time you choose, one-click join for Meet, Zoom, Teams, Webex,
  Around and Whereby, the agenda for today and tomorrow in the expanded
  island, and reminders completed from it. All-day events and invitations you
  have not answered are kept out of the countdown; a cancelled event is taken
  off the island rather than merely stopped from appearing.

  Nothing in the countdown ticks. `Agenda.nextChange(after:)` computes the
  exact next moment the answer can change — a lead time beginning, an event
  starting, an event ending — and the module sleeps until it. Between two
  meetings it runs no code at all.

- **In-call mute, camera and leave**, driven through the meeting client's own
  menu bar. `Meeting ▸ Unmute Audio` is the control and the state in one, so
  muting inside Zoom and muting from the island cannot disagree.
  [ADR 0006](docs/adr/0006-menu-bar-accessibility-for-meeting-controls.md)
  records the choice and the module's one polling exception: while a call is
  running and on the island, its menu is re-read every two seconds.

  **Zoom is verified.** Teams and Webex ship title tables matching their
  published menus and are best effort — an unrecognised title reads as
  "controls unavailable" rather than performing the wrong action. Meet,
  Around and Whereby get no controls: they run in a browser tab, which has no
  menu bar. Accessibility is asked for the first time you press a control,
  never on switching the module on.

- **Notifications** (module 8). Mirrored into the island grouped by app —
  nine messages from one person is one entry saying nine, not nine fighting
  over the notch. Inline reply types into the banner's own reply field, so it
  works wherever macOS offers one rather than only for apps Perch knows
  about. The per-app list works both ways round: everything except these, or
  only these. Notifications that arrive during a focus session are held, not
  dropped, and released grouped by app when it ends.

  There is no API for this — macOS hands an app its own notifications and
  nobody else's. Perch reads the banner through Accessibility rather than the
  notification database, which sits behind Full Disk Access.
  [ADR 0007](docs/adr/0007-reading-the-banner-for-notifications.md) records
  why. It follows that Perch mirrors what is on screen and nothing more: no
  history, nothing read from disk, and Do Not Disturb needs no handling at
  all, because a banner macOS does not draw is one Perch never sees.

- **Camera** (module 9). A live preview under the notch — mirror, four
  shapes, scroll to resize, opacity, a device picker that covers Continuity
  Camera, snapshot straight into the shelf, and a floating pill you can pin
  and drag while you present. The **pre-call check** opens it by itself just
  before a meeting starts and closes itself if you do nothing; nobody in the
  paid field has that.

  The privacy promises hold by construction rather than by discipline. A
  running preview has no output attached to the capture session at all — only
  a preview layer, which renders from the device and hands Perch nothing — so
  there is no frame to keep and none to write. Closing removes the session's
  inputs rather than only stopping it, because stopping alone leaves the
  device held and the green light on. And nothing opens a device except the
  preview appearing: switching the module on, launching the app and enabling
  the pre-call check all open nothing, which TC-CAM-009 checks by running the
  whole lifecycle five times.

  Camera permission is asked for at the first preview, with the reason on
  screen. Never on switching the module on.

- **System stats** (module 10). CPU total, per core and the busiest process;
  memory with Activity Monitor's own pressure level; free space per volume;
  network throughput and VPN state; GPU load on Apple Silicon; fan speeds;
  uptime, load average and battery health. A two-glyph micro-gauge beside the
  notch, a grid of 60-second sparklines when it opens, alert thresholds that
  fire once rather than once per sample, and click-through to Activity
  Monitor. Nobody else in the field has a system monitor at all.

  The performance trap `CLAUDE.md` §4 warns about is closed by construction.
  The sampler's lifetime belongs to the view, and `SamplerPolicy` returns
  `nil` for "do not sample" rather than a long interval, so a caller cannot
  treat it as a default. Collapsed with no gauge showing, no timer exists —
  not a slower one, none.

  Three rows are refusals rather than gaps. Temperature needs a private
  interface, so fans read and the temperature row is hidden rather than
  guessed at. GPU load does not exist on Intel, where the tile is replaced
  rather than zeroed. Per-volume disk throughput would attribute to devices
  rather than volumes, and a number that disagrees with the row beside it is
  worse than no number.

  The public-IP readout is the one network request in Perch outside the
  update feed. It is off, it is asked once rather than on a schedule, it
  carries no identifier, and its own pane says so.

Phase 2.5 is complete. Next up: weather, windows, Shortcuts and
hide-the-notch — the P1 tier that closes Phase 2.

## [0.5.0] — 2026-09-21

Phase 2.3: the three modules that make the island answer the machine rather
than just the apps on it. Three of the eighteen, taking the built count to six.

### Added
- **Battery and accessories** (module 7). The Mac's charge, power source and
  time remaining; AirPods left, right and case; every mouse, keyboard and
  trackpad that reports a level. A low warning once per discharge cycle, a
  charging-complete announcement, and a tile on the island's home surface
  that is where the module actually lives — the alerts are rare by design.
  Each announcement is individually switchable, and the warning threshold is
  configurable.

  There is no timer in this module. `IOPSNotificationCreateRunLoopSource`
  pushes the Mac's battery and `IOServiceAddMatchingNotification` pushes
  accessory connects; the one thing nothing publishes — a level moving while
  a device stays connected — is re-read when the island is opened rather
  than sampled. [ADR 0004](docs/adr/0004-ioregistry-for-accessory-levels.md)
  records why the accessory levels come from the IO registry, and what
  happens when Apple renames the keys.

- **HUD replacement** (module 6). Six overlays in the notch instead of
  stamped over the screen: volume and mute, display brightness, charging,
  Bluetooth connect and disconnect, Focus — Do Not Disturb is a Focus — and a
  camera-and-microphone-in-use indicator that needs neither permission. Each
  is individually switchable. The macOS overlay is suspended while the module
  is on and restored the instant it is switched off or Perch quits; nothing is
  killed and nothing is changed on disk.

  Every rule about what reaches the island lives in `HUDPolicy`, which is pure
  — a held brightness key coalescing into one smooth HUD, a change Perch made
  itself not being announced back, and one HUD switched off leaving the others
  alone are all unit tests rather than things to check by eye.

  Brightness and the suppression need private interfaces;
  [ADR 0005](docs/adr/0005-private-apis-for-the-hud.md) records what is used,
  how each half degrades, and the one cost: after the macOS overlay agent
  starts, one stock overlay appears before Perch catches it, and none after.

  **Keyboard backlight and AirDrop are not included.** macOS publishes no
  change notification for either, at any level, so a switch for them would be
  a switch that never does anything. Both are recorded in `FEATURES.md` §6.

- **Focus timer** (module 4). Pomodoro with configurable work and break
  lengths, the countdown in the collapsed island rather than in a window or a
  menu-bar string, session and streak counts, and a finished alert that
  pre-empts Now Playing through the existing priority ladder rather than a
  special case.

  **Nothing ticks.** The timer is wall-clock — a running phase is the `Date`
  it ends at — so a Mac asleep for forty minutes wakes to a session that is
  simply over, with no accounting, because nothing was ever counting. The
  countdown is drawn by `Text(timerInterval:)`, which macOS renders itself,
  and completion is a single scheduled wake-up rather than a repeating timer.

  The streak counts **days, not sessions**: four on Tuesday is one day.

  **Auto-enabling a macOS Focus during a session is not included.** Nothing at
  any level can set a Focus — the entitlement is Apple's own — so Perch can
  read which one is on and show it, but not turn one on. `FEATURES.md` §4
  records it and the Preferences pane says so.

### Changed
- The Battery module needs **no permission**. `FEATURES.md` listed Bluetooth,
  which was wrong: `CoreBluetooth` and `IOBluetooth` are what require it, and
  this module uses neither.

## [0.4.0] — 2026-09-20

The release that gave Perch a face, and something to download.

### Added
- **A comparison page per competitor** (#18), generated by `build.js` from
  `Website/data/comparison.json` — one source for the home page's matrix and
  all seven pages, so a price change cannot leave them disagreeing. Each page
  names something that competitor does better, because `WEBSITE-PLAN.md` §8
  rule 2 says never to rubbish the field and because the audience for these
  pages can tell an argument from a sales sheet.

### Fixed
- A folder on the shelf drew a document icon (#14). `NSWorkspace` hands back
  a generic icon for a path that is not there, cheerfully, for anything —
  and `TC-SHF-006` only checked the model, which was right all along.

### Changed
- User-facing text moved out of `PerchCore` (#16). `String(localized:)`
  resolves against the bundle of the module it is written in, and Core is a
  framework with no string catalog, so English held there could never be
  translated. Core owns what a conversion *is*; the interface owns what it is
  *called*.
- `make screenshots` re-renders the website's images from the app's own views
  (#15). The `TEST_RUNNER_` prefix that makes the capture work is not
  something anyone would guess.

### Added
- **An open-source section on the website**, and a GitHub link in the header
  — `WEBSITE-PLAN.md` §1 listed one and it was never built. Buttons to the
  repository, to `CONTRIBUTING.md` and to the good-first-issue list, plus
  what a contributor actually wants to know: no CLA, the roadmap is public,
  the awkward decisions have records, and bug reports from unusual display
  arrangements are the most useful thing anyone can send.
- `Website/build.js` — injects the version and the repository's issue count
  at **build** time. Fetching them from the visitor's browser would have the
  page contacting GitHub while claiming nothing leaves your Mac.
- Five good first issues, so the link leads somewhere. One of them is a real
  bug spotted in our own screenshot: a shelved folder draws a document icon.
- **Real screenshots on the website.** `IslandSnapshots` renders the app's
  own `IslandRootView` into PNGs — the shelf and the clipboard pictures on
  the site are the running UI, not mockups, and they cannot drift from what
  ships. It doubles as the groundwork for the snapshot cases in the test
  plan.
- **A logo.** A peacock perched inside a medallion whose top edge is cut by
  the notch — drawn in the register of Indian folk painting: heavy outlines,
  flat fills, no gradients, and pattern used as structure. It is the app
  icon, the menu-bar item, the island's home surface and the website's
  brand mark, all from the same two SVGs in `Resources/Logo`.
- A downloadable build. `build-0.3.0` is published as a pre-release with a
  universal, unsigned app attached, and the download buttons now point at
  the file rather than at an empty Releases page.

### Changed
- The website's hero said "eighteen modules" when three are built. It says
  three, and names the fifteen as on the way.

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

[0.4.0]: https://github.com/Milanpatel35/Perch/releases/tag/v0.4.0
[0.3.0]: https://github.com/Milanpatel35/Perch/releases/tag/v0.3.0
[0.2.0]: https://github.com/Milanpatel35/Perch/releases/tag/v0.2.0

[Keep a Changelog]: https://keepachangelog.com/en/1.1.0/
[Semantic Versioning]: https://semver.org/spec/v2.0.0.html
