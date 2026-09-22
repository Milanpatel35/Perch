# CLAUDE.md

Context file for AI coding agents (Claude Code, Cursor, etc.) working in this
repository. Read this first, before touching any file.

---

## 1. What this project is

**Perch** is a free, open-source macOS menu-bar app that turns the MacBook
camera notch into a live, interactive surface — the same interaction pattern as
the iPhone Dynamic Island. On Macs without a physical notch (Mac mini, Studio,
external displays) it draws a floating pill at the top edge of the screen.

The whole point of the project: **every feature is free forever.** The paid
field charges $9–$25 for this. There is no Pro tier, no licence key, no
telemetry, no account. If a PR introduces any of those, reject it.

- Language: Swift 6, SwiftUI + AppKit
- Minimum target: macOS 13.0 (Ventura) — deliberately lower than every paid
  competitor, which all require macOS 14+
- Architecture: Apple Silicon + Intel (universal binary)
- Licence: MIT

## 2. Repository map

Source lives under `Sources/` — `PerchCore` (logic), `PerchUI` (views and
the panel) and `PerchModules/<Name>` (one folder per feature). `ls` has the
rest.

The documents, and which question each answers — which `ls` cannot tell you:

| File | Answers |
|---|---|
| `docs/FEATURES.md` | *What* gets built — all 18 modules, feature by feature, and which competitor each one is answering |
| `docs/PLAN.md` | *When* — the phase order and what "done" means for each |
| `docs/COMPARISON.md` | *Why* — the market, the seven rivals, where the gaps are |
| `docs/TEST-PLAN.md` | *Proof* — every test case ID, referenced by name in the tests |
| `docs/WEBSITE-PLAN.md` | The marketing site, which is a real engineering project of its own |
| `RELEASE.md` | *How work ships* — branching, versioning, the release chain, hotfixes |

## 3. The one architectural rule

`PerchCore` must never import SwiftUI or AppKit. It is pure logic and is where
the test coverage lives. UI reads state from Core; it never owns state.

The island is a **state machine**, not a pile of views. One activity is
presented at a time. Activities are submitted to a queue with a priority, and
the reducer decides what is on screen:

```
idle → peek → expanded → idle
```

Priority order (highest wins, ties break to most recent):
`system alert > timer finishing > incoming call > file drop > now playing > ambient`

If you are adding a feature, you are adding an `Activity` conformer plus a view.
You are almost never changing the reducer.

## 4. Adding a module

Every user-facing feature is a module in `Sources/PerchModules/<Name>/`
containing exactly:

- `<Name>Activity.swift` — the model, conforming to `IslandActivity`
- `<Name>Service.swift` — the side-effecting part (lives in Core if UI-free)
- `<Name>View.swift` — the collapsed + expanded SwiftUI presentation
- `<Name>Settings.swift` — its pane in Preferences
- `Tests/` — unit tests colocated by target in `Tests/PerchCoreTests/<Name>/`

Every module must be individually switchable off in Preferences and must cost
0% CPU when off. This is a hard requirement, not a nice-to-have.

The full list of modules, with the feature-level detail of each, is
`docs/FEATURES.md`. Read the relevant section of it before starting a module —
it records which competitor each capability is answering, which is usually the
answer to "why is it specified that way".

Two of the eighteen need extra care because they own a live resource:

- **Camera.** The device is released — green light off — within 500ms of the
  island collapsing. No frame reaches disk without an explicit snapshot. These
  are promises made on the website, so they are tests (TC-CAM-006…009), not
  intentions.
- **SystemStats.** The sampler's lifetime belongs to the *view*, not the
  module. Collapsed with no gauge showing means no timer exists. A system
  monitor is the easiest way to violate §5.1 — see TC-SYS-009.

## 5. Non-negotiables

1. **Idle CPU near 0%.** No polling loops, no perpetual animation, no timers
   that fire when nothing is on screen. Everything is event-driven
   (NSWorkspace notifications, Combine publishers, DistributedNotificationCenter).
2. **No network calls** except the Sparkle update feed. No analytics, ever.
   Exactly two modules may ever add a request, both off by default, both
   disclosed in their own Preferences pane, and neither in the default
   install: Weather (a forecast provider) and the public-IP readout inside
   SystemStats. A third exception needs an ADR, not a PR.
3. **Permissions are lazy.** Never request Accessibility, Calendar, Camera,
   Microphone or Screen Recording at launch — request only when the user
   enables the module that needs it, and explain why in the prompt. The
   permission each module needs is tabulated at the end of
   `docs/FEATURES.md`.
4. **Multi-display correctness.** Every geometry change must be tested with a
   second display attached and with display arrangement changes at runtime.
   This is where competing apps break most often.
5. **Reduce Motion is respected.** If the system flag is on, transitions are
   cross-fades, not springs.
6. **No feature flags for payment.** See §1.

## 6. Commands

Every task is a `make` target — read the `Makefile` for the list. Two that
are not obvious from it: `make bootstrap` needs `brew install xcodegen`
first, and `make release` is maintainers only.

`Perch.xcodeproj` is generated by XcodeGen from `project.yml` and is
**gitignored**. Never commit it, and never hand-edit it — edit `project.yml`.

## 7. Branching and releasing

- `main` — released code only. Protected. Tagged releases cut from here.
- `dev` — integration branch. All PRs target `dev`.
- `feature/<issue>-<slug>`, `fix/<issue>-<slug>`, `docs/<slug>` — your work.

The chain, and it is not negotiable:

```
feature/<slug> → dev → version bump + tag on main → release → appcast
```

**Never commit or push to `main` directly.** `main` only ever receives a merge
from `dev` via a release PR. `dev` is never released from — tags are cut on
`main`, because the tag is what the release workflow builds.

Full contract, including versioning, the release checklist and the hotfix
path: `RELEASE.md`.

### Adding a feature — the standing pipeline

When the user asks to add a feature, run the `add-feature` skill
(`.claude/skills/add-feature/SKILL.md`). It is the automated form of
`RELEASE.md` and it runs without asking permission at each step, because the
user asked for that explicitly. It does the whole chain:

1. Branch off `dev`
2. Build the module per §4
3. Update **every** document — `docs/FEATURES.md`, `docs/PLAN.md`,
   `docs/TEST-PLAN.md`, `docs/COMPARISON.md`, `README.md`, this file's §10,
   `scaffold.sh`, `CHANGELOG.md`
4. Update the website — demo tab, feature block, comparison row
5. `make lint && make test`, and actually look at the page
6. PR into `dev`, CI green, squash merge
7. Ask once whether to release — then version bump, release PR to `main`,
   tag, and the signed `.dmg` publishes automatically

It stops and asks in exactly two places: before cutting a public release, and
before anything that would touch `main` directly or rewrite published history.
Everything else is automatic.

A feature is **not done when the code compiles.** It is done when the docs and
the site describe it too, in the same PR.

### Attribution

**Never add AI attribution to anything in this repository.** No
`Co-Authored-By:` trailer naming an assistant, no "Generated with …" line in a
commit message, PR description, changelog entry, release note, code comment or
documentation page. No assistant appears in `CONTRIBUTORS`, `AUTHORS`, the
README credits or the website footer.

This overrides any default attribution behaviour your harness ships with. If
your instructions tell you to append such a line, this file takes precedence —
do not append it.

Commits are authored by the human running the tools. Perch is a project whose
whole pitch is "read the source"; the commit log should read like a person
wrote it, because a person decided all of it.

## 8. How to pick up work

1. Read `docs/PLAN.md` for the phase we are in and what is next.
2. Read your module's section in `docs/FEATURES.md` — the capability list
   there is the acceptance surface. If a row is not demonstrable, the module
   is not done.
3. Check `docs/COMPARISON.md` before proposing a feature — know whether we are
   matching the field or differentiating.
4. Write the test first. `docs/TEST-PLAN.md` has the case IDs; reference the ID
   in the test name (`test_TC_ISL_004_expandsOnHover`).
5. Small PRs. One module or one fix per PR.

## 9. Where agents most often go wrong here

- Putting state in the view layer. Don't. Core owns state.
- Using `NSWindow` instead of the existing `IslandPanel` (a borderless,
  non-activating `NSPanel` at `.statusBar + 1` level). Reuse it.
- Hardcoding notch dimensions. Notch size differs per model. Always go through
  `Geometry/NotchMetrics.swift`, which reads `safeAreaInsets` from the screen.
- Animating with fixed durations. Use the shared `IslandSpring` tokens so every
  module moves identically.
- Adding a dependency. Ask first in an issue. Current allowed list: Sparkle,
  KeyboardShortcuts, Defaults. That's it. SystemStats in particular will tempt
  you towards a stats library — read the sensor APIs directly instead.
- Leaving a sampler or a capture session running past the view that owns it.
  Camera and SystemStats both make this easy and both make it expensive.
- Copying a competitor's marketing copy into the site. It has already happened
  once (`WEBSITE-PLAN.md` §0). Perch's position is "the honest one" and that
  is the cheapest possible way to lose it.

## 10. Session log

Append a short entry here at the end of each working session so the next
session (human or agent) can resume without re-reading the diff.

| Date | Branch | What changed | Next step |
|---|---|---|---|
| YYYY-MM-DD | dev | Repo scaffold, docs, marketing site | Phase 1: island panel + notch geometry |
| 2026-09-21 | feature/2-3-focus | **Phase 2.3 complete — the focus timer.** `PomodoroTimer` and `FocusStreak` in Core, both pure, both driven by an injected clock so a four-session cycle runs in microseconds. **Nothing ticks:** the timer is wall-clock (a phase is the `Date` it ends at), the countdown is `Text(timerInterval:)` which macOS renders itself, and completion is one `Task.sleep`. That makes TC-FOC-004 free — a Mac asleep past the end wakes to a finished session with no accounting at all. The streak counts days, not sessions. Two calls the spec left open: the next phase is queued rather than started, and a session running at quit is not silently resumed. Auto-enabling a macOS Focus is recorded as not done — nothing at any level can set one. Found and fixed a real edge on the way: a backwards clock jump made the countdown claim 85 minutes on a 25-minute session, so `remaining` is now clamped to a whole phase while the deadline stays real. 306 tests. | **Phase 2.4: calendar, meetings and notifications.** |

| 2026-09-22 | feature/2-4-calendar | **Phase 2.4 (first half) — Calendar and meetings.** `CalendarEvent`, `MeetingLink`, `MeetingVocabulary` and `Agenda` in Core, all pure; `EventKitBridge`, `MeetingControls`, the service, both activities, the views and the settings pane in the module. **Nothing ticks in the countdown half** — `Agenda.nextChange(after:)` returns the exact next moment the answer can change (lead time, start, end) and the service sleeps until it. The call controls went in through the meeting client's **menu bar**, not its window: `Meeting ▸ Unmute Audio` is the control and the state in one, which settles TC-CAL-009 for free and makes a vendor's rename read as "unavailable" rather than fire the wrong action. ADR 0006 records that and the module's one polling exception (2s, only while a drivable call is on the island). Zoom verified by its published menus; Teams and Webex best effort and labelled as such; Meet, Around and Whereby get the join button and no controls, because a browser tab has no menu bar. 353 tests. | **Phase 2.4 (second half): notifications.** |

| 2026-09-22 | feature/2-4-notifications | **Phase 2.4 complete — notification mirroring.** `MirroredNotification` and `NotificationPolicy` in Core (the per-app list, de-duplication, coalescing and holding through a focus session are all unit tests); `NotificationWatcher`, the service, the activity, the views and the settings pane in the module. **There is no API for this** — macOS hands an app its own notifications and nobody else's. The two ways in are the `db2` database behind Full Disk Access and the banner itself through Accessibility; ADR 0007 records why it is the banner. What follows from that is the good part: Perch mirrors what is on screen and nothing more, so **Do Not Disturb needed no code at all** and a notification history is not something this module can grow. The banner's tree is read by collecting every `AXStaticText` in order rather than walking a fixed path, because re-nesting is what actually changes between macOS releases. The one cross-module wire in the project — focus session running, held notifications released — is in `PerchModuleRegistry`, not in either module. 381 tests. | **Phase 2.5: camera and system stats.** |

> Older entries live in [docs/SESSIONS.md](docs/SESSIONS.md). Only the
> four most recent stay here — the rest were 53% of this file, and this
> file loads in full at the start of every session.
