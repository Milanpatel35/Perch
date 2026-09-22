# Perch — build plan

Last updated: 20 September 2026 — restructured from nine phases into three.
The work did not change; the grouping did. Nine phases made every milestone
feel equally weighted, which they are not. Three phases match how the project
actually divides: **build the spine, fill it with modules, then make it
shippable.**

Sequenced so that every stage ends with something you can run and show.
Estimates assume one developer working evenings; halve them for full-time.

The full module list this plan delivers is [FEATURES.md](FEATURES.md) — 18
modules, P0 through P2. This file says *when*; that file says *what*.
[RELEASE.md](../RELEASE.md) says how each one ships.

---

# Phase 1 — The spine (weeks 1–3)

Nothing user-facing. This is the whole product's foundation, and every notch
app that feels janky got that way by building features on a shaky panel layer.

## 1.1 — Foundations

The boring week that saves you three later ones.

1. Create the GitHub repo, push `main`, branch `dev`, protect both per
   `RELEASE.md`.
2. `LICENSE` (MIT), `README.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`,
   `SECURITY.md`, `CLAUDE.md`, `CHANGELOG.md`, issue and PR templates.
3. `project.yml` for XcodeGen; the `Makefile`; gitignore the `.xcodeproj`.
4. SwiftLint + swift-format config, wired into `make lint`.
5. GitHub Actions: lint, build, test on macOS 14 and 15 runners.
6. Decide the bundle identifier and register the app group / keychain items.

**Done when:** a fresh clone runs `make bootstrap && make test` green on
someone else's Mac.

## 1.2 — Geometry

Get this wrong and every module inherits the bug. Multi-display correctness is
the most common complaint across the entire field — see `COMPARISON.md`.

1. `NotchMetrics` — read `NSScreen.safeAreaInsets` for real notch width and
   height. No hardcoded constants; notch size differs per model.
2. Handle every case: notched built-in, non-notched built-in, external
   display, arrangement change at runtime, hot-plug, resolution and scale
   change, rotation, Sidecar.
3. Virtual pill fallback for Macs with no notch.

**Tests:** TC-GEO-001 … TC-GEO-010.

**Done when:** metrics are correct on every display configuration you can
find, and the unit tests cover the ones you cannot.

## 1.3 — The panel

1. `IslandPanel` — borderless, non-activating `NSPanel` above the menu bar at
   `.statusBar + 1`, ignoring mouse events when idle, joining all Spaces,
   surviving full screen.
2. Re-anchoring on display change without a crash or a flicker.

**Tests:** TC-ISL-008, TC-ISL-010, TC-ISL-011, TC-GEO-005 … TC-GEO-008.

## 1.4 — The state machine

1. `IslandState` reducer in `PerchCore`: `idle → peek → expanded → idle`.
2. The priority queue from `CLAUDE.md` §3, bounded, with pre-emption and
   re-queueing.
3. `IslandActivity` protocol — the contract every one of the 18 modules
   implements.

**Tests:** TC-ISL-001 … TC-ISL-007, TC-ISL-009, TC-ISL-012.

**This is the most important code in the project.** Eighteen modules will be
written against it. Get the protocol right before anything depends on it.

## 1.5 — Motion

1. `IslandSpring` tokens, shared by every module so everything moves
   identically.
2. The Reduce Motion cross-fade path — a real path, not a disabled one.
3. Hover, click and drag-hover entry gestures.

**Tests:** TC-ISL-004, TC-ISL-005, TC-ISL-012, TC-A11Y-004.

**Phase 1 is done when:** an empty black island expands and collapses smoothly
on hover, on every display configuration you can find, at ~0% idle CPU, and
with Reduce Motion on it cross-fades instead. Tag `v0.1.0`.

**Status: done.** The panel sits at `.statusBar + 1`, centred on the notch,
re-anchoring on every display change. The island's resting state is a real
`ambient` activity — the home surface — rather than a special case in the
reducer, which is what makes hover-to-open take the same path a module's
activity takes. `.idle` keeps its honest meaning: every module off, nothing to
show, panel inert.

---

# Phase 2 — The modules (weeks 4–14)

Eighteen modules against a paid field that averages six. Each one is an
`IslandActivity` conformer plus a view, per `CLAUDE.md` §4 — you are almost
never changing the reducer.

Ship a release at the end of each stage. Tags create momentum and give testers
something to break.

## 2.1 — Now Playing (week 4)

First because every competitor has it, so it is the honest benchmark for
whether your animation quality is acceptable.

Media adapter, collapsed artwork + visualiser, expanded transport and
scrubber, AirPlay picker, Up Next queue, synced lyrics, sneak peek on track
change, swipe to skip. **Tests:** MED.

**Done when:** you would rather use Perch than the stock Now Playing widget.

**Status: done**, apart from Up Next and lyrics, which no local API exposes
for an arbitrary source — see the status note in `FEATURES.md` §1 and
[ADR 0002](adr/0002-mediaremote-for-now-playing.md). The module also proved
what it was picked first to prove: the panel and the motion tokens carry a
real module without changes to either.

## 2.2 — Shelf and clipboard (weeks 5–7)

The two features that turn this from a toy into a tool. Clipboard history is
the single biggest gap in the paid field.

Drag detection and drop target, persistence, AirDrop and share sheet, quick
file conversion, then the clipboard: text, rich text, image, colour and file
paths, search, pinning, retention, exclusions, and OCR on copied images.
**Tests:** SHF, CLP.

**Done when:** you have stopped using a separate shelf app, and the clipboard
beats the $9 app's tray in a way you can demonstrate in ten seconds.

**Status: done.** Both halves. The clipboard needed the one exception to
§5.1 in the whole project — `NSPasteboard` has no notification, so it polls —
and that is written down in ADR 0003 rather than left for somebody to
discover in Activity Monitor.

## 2.3 — HUDs, battery, focus (weeks 8–9)

The full Alcove HUD set — volume, brightness, backlight, charging, Bluetooth,
Focus mode, AirDrop, screen recording — each individually switchable. Battery
for the Mac and every connected accessory. Pomodoro timer in the collapsed
island. **Tests:** HUD, BAT, FOC.

**Done when:** the stock macOS HUD never appears again.

**Status: battery done.** Module 7 shipped in 0.5.0 — the Mac's battery,
charge state and time remaining, AirPods left/right/case, every BLE device
that reports a level, the low warning once per discharge cycle and the
charging-complete alert. No timer anywhere in it: IOKit pushes the Mac's
battery and pushes accessory connects, and the one thing nothing publishes —
a level moving while a device stays connected — is re-read when somebody
opens the island rather than sampled. [ADR 0004](adr/0004-ioregistry-for-accessory-levels.md)
records why the accessory levels come from the IO registry. The permission
table was wrong about this module: it needs none.

**Status: the HUDs done too.** Module 6 shipped in 0.5.0 — six of the eight
HUDs, each individually switchable, with the stock overlay suspended while the
module is on and restored the moment it is not.
[ADR 0005](adr/0005-private-apis-for-the-hud.md) records the two private
interfaces it needs and how each degrades. Keyboard backlight and AirDrop are
recorded in `FEATURES.md` §6 as not done: macOS publishes no change
notification for either, and a HUD that can never fire is not a feature.

**Status: 2.3 complete.** Module 4 shipped in 0.5.0 too — Pomodoro with
configurable lengths, the countdown in the collapsed island, session and
streak counts, and a finished alert that pre-empts Now Playing through the
existing priority ladder rather than a special case. No ticking: the timer is
wall-clock, the countdown is rendered by macOS, and completion is a single
scheduled wake-up. Auto-enabling a macOS Focus is recorded in `FEATURES.md` §4
as not done — nothing at any level can set one.

**Phase 2.3 is done.** Next is 2.4: calendar, meetings and notifications.

**Also starts here: the website.** It is 24 working days (`WEBSITE-PLAN.md`
§9) and cannot be compressed into launch week. Run it in parallel from now on.

## 2.4 — Calendar, meetings, notifications (weeks 10–11)

EventKit, countdown, one-click join for Meet / Zoom / Teams / Webex / Around /
Whereby. In-call mute, camera and leave — the most technically awkward thing
in this phase, so budget for it breaking when Zoom ships an update.
Notification mirroring with inline reply. **Tests:** CAL.

**Done when:** you have joined a real meeting from the notch, muted from the
notch, and left from the notch, without ever finding the window.

**Status: calendar done.** Module 5 shipped in 0.6.0 — the next event with a
live countdown at a configurable lead time, one-click join for all six
services, the agenda for today and tomorrow, all-day and unanswered events
excluded, and reminders completed from the island. Nothing in the countdown
half ticks: `Agenda.nextChange(after:)` computes the exact next moment the
answer can change and the service sleeps until it, so between two meetings
the module runs no code at all.

The call controls went in through the **menu bar** rather than the meeting
window — `Meeting ▸ Unmute Audio` is the control and the state in one, which
is what settles TC-CAL-009 for free.
[ADR 0006](adr/0006-menu-bar-accessibility-for-meeting-controls.md) records
it, along with the module's one polling exception. Zoom is verified; Teams
and Webex are best effort and say so; Meet, Around and Whereby get no
controls at all, because a browser tab has no menu bar.

**Status: 2.4 complete.** Module 8 shipped in 0.6.0 too — notifications
mirrored into the island grouped by app, inline reply through the banner's
own field, a per-app list that works either way round, and everything that
arrives during a focus session held rather than dropped and released when it
ends.

Read from the **banner** through Accessibility, not from the notification
database, which sits behind Full Disk Access.
[ADR 0007](adr/0007-reading-the-banner-for-notifications.md) records that
choice and what follows from it: Perch mirrors what is on screen and nothing
more, so Do Not Disturb needs no handling at all and a notification history
is not something this module can grow.

**Phase 2.4 done.** Next is 2.5: camera and system stats.

## 2.5 — Camera and System stats (weeks 12–13)

The two modules nobody in the field has, and the two the launch argument rests
on. Built together because they share the same hard problem: a live view that
must cost nothing the moment it is off screen.

Camera preview, mirror, shapes, device picker, pin-as-floating-pill, snapshot
to shelf, and the automatic pre-call check. Then the privacy work, which is
most of the module — write TC-CAM-006 … 009 first, they are the promise.

System stats: CPU, GPU, memory, disk, network, thermals; collapsed
micro-gauge; expanded grid with sparklines; alert thresholds firing through
the existing priority queue. The sampler belongs to the *view*, not the module
— TC-SYS-009 enforces it.

**Tests:** CAM, SYS.

**Done when:** you have watched a build peg every core in the notch, and
checked your hair before a standup, and Activity Monitor still says Perch is
using effectively nothing when neither is on screen.

**Status: camera done.** Module 9 shipped in 0.6.0 — live preview, the
pre-call check, mirror, four shapes, the floating pinned pill, scroll to
resize, the device picker and snapshot to the shelf.

The privacy promises are kept by construction rather than by discipline: a
running preview has **no output attached to the session**, only a preview
layer, so there is no frame to keep and none to write. Closing removes the
session's inputs rather than only stopping it, because stopping alone leaves
the device held and the light on. And nothing opens a device except the
preview appearing — TC-CAM-009 runs the whole lifecycle five times to say so.

The pinned pill is the one window in the app that is not `IslandPanel`; it
has to outlive the island collapsing, which is what pinning means.

**Status: 2.5 complete.** Module 10 shipped in 0.6.0 too — CPU, memory, disk,
network, GPU, fans, uptime, load average and battery health, a two-glyph
micro-gauge beside the notch, a grid of 60-second sparklines when it opens,
alert thresholds with hysteresis, and click-through to Activity Monitor.

**The performance trap is closed by construction rather than by care.** The
sampler's lifetime belongs to the view — `beginSampling` on appear,
`endSampling` on disappear — and `SamplerPolicy.interval(for:)` returns
`nil` rather than a long number, so "do not sample" cannot be mistaken for a
default. TC-SYS-009 asserts it through five lifecycle paths.

Three rows are refusals rather than gaps, and `FEATURES.md` §10 records each:
temperature needs a private interface, GPU load does not exist on Intel, and
per-volume disk throughput would attribute to devices rather than volumes.
The public-IP readout is the one network request in the app and is off.

**Phase 2.5 done.** Next is 2.6: weather, windows, Shortcuts and
hide-the-notch — the P1 tier, and the last of Phase 2.

## 2.6 — Weather, windows, Shortcuts, hide-the-notch (week 14)

The P1 tier. Individually small, collectively the difference between "as good
as the paid apps" and "more than all of them". Weather (off by default, it
touches the network). Window snapping and layouts. Shortcuts in both
directions, plus `perch://` and a CLI. TopNotch's entire product as one
settings toggle. **Tests:** WIN, SHC, HID.

**Done when:** a TopNotch user has no reason to keep TopNotch installed.

---

# Phase 3 — Shippable (weeks 15–17)

## 3.1 — Polish

1. Onboarding: a three-screen first run explaining each permission. With
   eighteen modules this matters more than it used to — the first run must not
   present eighteen switches. Ship four presets (Music, Work, Everything, Just
   hide the notch) and a link to the full list.
2. Preferences window, per-module toggles, keyboard shortcuts.
3. Launch at login, Sparkle updates, appcast on GitHub Pages.
4. Accessibility pass: VoiceOver labels, keyboard navigation, Reduce Motion,
   Increase Contrast. **Tests:** A11Y.
5. Localisation scaffolding, English complete.

## 3.2 — Release engineering

1. Code sign, notarise, staple. Homebrew cask submission.
2. Performance audit: an hour idle in Activity Monitor, energy impact, the
   eight-hour memory check. **Tests:** PRF, PRV, UPD.
3. The manual release checklist at the bottom of `TEST-PLAN.md` — the full
   hardware and display matrix.

**Done when:** `brew install --cask perch` works for a stranger.

## 3.3 — Launch

1. Marketing site live on the custom domain — finished weeks ago, not this
   week. Run the `WEBSITE-PLAN.md` §10 checklist first, especially the copy
   audit.
2. Show HN, r/macapps, r/MacOS, Product Hunt, Mac Twitter/Mastodon.
3. `good first issue` backlog stocked **before** launch day, not after — the
   contributor window opens and closes fast.
4. Respond to every issue in the first week, even the rude ones.
5. Lead with the two things nobody else has. "Another notch app" is a scroll
   past; "the notch app with a system monitor in it" is a click.

---

## Backlog (post-1.0)

The P2 tier from `FEATURES.md`, in rough order of how often people will ask:

- Voice to text, on-device (Seam's and NotchBay's differentiator, and the
  single biggest piece of work left — Whisper via Core ML)
- Screenshot capture and annotation, straight into the shelf
- Notes / scratchpad pinned to the island
- Lock Screen presence
- Developer module: CI status, PR review queue, `perch notify` piped from a
  build script
- Per-display island placement rules
- Additional localisations

Explicitly **not** on the backlog, and PRs will be declined: cloud sync of any
kind, an iPhone companion, AI summarisation of anything, and any feature that
implies an account. Reasons in `FEATURES.md`.

## Sequencing rules

- Never start a module before Phase 1 is genuinely stable.
- Ship a release at the end of each stage, even a pre-1.0 one.
- Write the test cases before the code — IDs are in `TEST-PLAN.md`.
- **Scope is the risk, not capability.** Eighteen modules is ambitious for one
  developer working evenings, and 17 weeks assumes nothing goes wrong. If a
  stage slips, cut 2.6 out of 1.0 and ship it as 1.1 — it is designed to be
  droppable in one piece. Do not cut 2.5; Camera and System stats are the
  launch argument.
- Every new module is a permission, a settings pane, an onboarding line and a
  row in four documents. The marginal cost of module eighteen is far higher
  than module two. Re-read this before adding a nineteenth.
