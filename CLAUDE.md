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

| 2026-09-29 | feature/2-6-hide-notch | **Phase 2.6 (1 of 4) — hide-the-notch.** `HideNotchConfiguration`, `MenuBarStrip`, `WallpaperEdge` and `IdleVisibility` in Core; the service, `MenuBarStripPanel`, `WallpaperWatcher` and the settings pane in the module. **The one module with no activity** — it changes how the bar and the idle island look and never presents anything, so there is no `HideNotchActivity.swift`. The strip is the second non-`IslandPanel` window (§9), at `mainMenu - 1`: *under* the bar, so the bar's translucency lands on it and macOS whitens the menu text by itself. **Only a real screen found the bug:** AppKit pushes windows out from under the menu bar, so the strip first landed one bar-height too low — `constrainFrameRect` is overridden and there is a manual checklist line for it. The invisible-idle flag is `IslandController.hidesIdleIsland`, raised by the module like `requiresKeyFocus`. No wallpaper-changed API exists: a kqueue on the wallpaper store directory plus Space switches, only while the wallpaper fill is on. 480 tests. | **Phase 2.6: weather, windows, Shortcuts.** |

| 2026-09-29 | feature/2-6-shortcuts | **Phase 2.6 (2 of 4) — Shortcuts and automation.** `PerchCommand`/`PerchURL`, `ShortcutFavourites` and `ShortcutOutcome` in Core; the service, `ShortcutsCommandLine` (wraps `/usr/bin/shortcuts`, behind a protocol so tests fake it), the activity, the views and the pane in the module; three App Intents in `App/PerchIntents.swift` (app target, because frameworks only get App Intents on macOS 14); the `perch` CLI as a shell script in `Resources/`. **One front door:** intents and CLI both build a `perch://` URL and open it, so `PerchURL.parse` is the only input check, and its allow-list has **no run-a-Shortcut action** — any web page can open a link (TC-SHC-003). Outside messages top out at `.incomingCall`, one activity id so bursts coalesce. The registry was at swiftlint's 250-line limit, so cross-module wiring now goes in `PerchModuleRegistry+<Name>.swift` beside the module. Hardware: CLI → island verified; a `perch://run` link for a real Shortcut ran nothing; module off, nothing appears. 518 tests. Published `build-0.7.0` earlier this session and repaired `main`/`dev` history (#53) after #48 was squashed. | **Phase 2.6: weather and windows.** |

| 2026-09-29 | fix/* → 0.9.0 | **A fixes release: the running app did not work though every test passed.** A hands-on pass on a notched MacBook Pro (macOS 27) found: Settings… sent `showSettingsWindow:`, which macOS 14+ refuses, so no module could be switched (#58, now `SettingsWindowController`, ordered front explicitly); a second click on the home surface *withdrew* it and the island went dead until relaunch (#59, reducer `dismiss` folds TTL-less activities back to peek, TC-ISL-016); three General switches read by nothing (#59, `IslandGestures` in `IslandState`, TC-ISL-017, and `IslandPreferences`); every `Defaults` key had a dot, which it cannot observe (#59, renamed `_`, launch migration reads the persistent domain only, TC-SET-002); the System stats gauge covered the menus (#60, opt-in, home-surface row by default, TC-SYS-016); unbuilt modules had live switches (#61); **MediaRemote refuses third-party apps since macOS 15.4**, so Now Playing showed nothing (#62, Music + Spotify via distributed notifications and AppleScript, ADR 0008, TC-MED-010, no browser audio). The macOS 14 runner's older compiler caught two concurrency/throwing issues the local one did not. `build-0.9.0` published; the older builds' zips are backed up in `~/Downloads/perch-old-builds/`, and deleting their release pages was left to the user. The NowPlaying test-process crash (#57) is still open, and CI now uploads the `.xcresult` for it. 545 tests. | **Confirm a real Music song with Automation allowed; fix #57; then Phase 2.6: weather and windows.** |

| 2026-10-03 | fix/opened-panels-close, feature/first-run → 0.10.0 | **The product pass: what a stranger and a real notch see.** Looking at the running app found the island stuck wide with "Battery" drawn *under the camera housing*. Cause: #59 folds TTL-less activities to peek on close, which is right for module-owned ones and wrong for panels somebody opened — the battery list never left, the clipboard picker kept the keyboard, and **the camera preview folded with its id still on the island, so the device stayed open, light on (TC-CAM-006)**. `IslandActivity.endsWhenClosed` (defaults to having a TTL) fixes all three in the reducer (#71, TC-ISL-018); `NotchFlanks` replaces four peeks that centred text under the notch. Then Phase 3.1 pulled forward (#72): a three-screen welcome with the four presets and open at login (`SMAppService`, refused with a reason for a translocated copy — the user's own copy was running from Downloads). `ModulePreset`/`ModulePermission`/`InstallLocation` in Core, TC-ONB-001…006. **Hardware found two more:** the window centred before it had a size, and the preset cards ignored clicks — macOS kept the accessory app in the background, the window never became key, and `NSHostingView` refuses first mouse; a subclass accepts it. The macOS 14 runner rejected `filter(set.contains)` as "call can throw"; use closures. The unpushed 0.9.1 bump was superseded by 0.10.0. 554 tests. | **Confirm open at login across a real restart (TC-UPD-003); then Phase 2.6: weather and windows.** |

> Older entries live in [docs/SESSIONS.md](docs/SESSIONS.md). Only the
> four most recent stay here — the rest were 53% of this file, and this
> file loads in full at the start of every session.
