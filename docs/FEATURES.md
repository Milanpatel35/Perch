# Perch — the complete feature specification

Last updated: 20 September 2026.

This is the master list. Every feature that Seam, Boring Notch, Alcove,
DynamicLake Pro, TopNotch, NotchBay and NotchNook charge for — plus the two
things none of them do properly — collapsed into one free, open-source app.

**The rule:** if any of the seven ships it, Perch ships it, and Perch ships it
free. No Pro tier, no licence key, no trial timer, no feature that exists in
the codebase but is gated. See `CLAUDE.md` §1.

Legend for the "Comes from" column:
`SE` Seam · `BN` Boring Notch · `AL` Alcove · `DL` DynamicLake Pro ·
`TN` TopNotch · `NB` NotchBay · `NN` NotchNook · `★` nobody has this properly.

Status: **P0** ship for 1.0 · **P1** ship by 1.1 · **P2** post-1.0 backlog.

---

## 0. How to read this

Each numbered section is one module directory under
`Sources/PerchModules/<Name>/`, built exactly as `CLAUDE.md` §4 describes. The
sub-bullets are the acceptance surface: if a bullet is not demonstrable, the
module is not done.

Every module obeys the same three laws:

1. It is individually switchable in Preferences.
2. When switched off it costs literally 0% CPU — observers removed, timers
   invalidated, no allocations.
3. It asks for its permission the moment it is switched on, never at launch,
   and it says why in plain English.

---

## 1. Now Playing — P0

The benchmark feature. Every competitor has it, so ours is judged on motion
quality, not novelty.

| Capability | Comes from | Notes |
|---|---|---|
| Artwork, title, artist in the collapsed island | BN AL NN DL SE NB | Artwork left of the notch, visualiser right |
| Live audio visualiser | BN AL NN | Must stop dead on pause — no perpetual animation |
| Expanded transport: play/pause, skip, seek scrubber | all | Scrub is a drag, with haptic-style snap at 0/100% |
| AirPlay / output device picker | NN AL | Route without opening Control Centre |
| Up Next queue | DL NN | Reorder by drag, clear queue |
| Synced lyrics | NN | Line-by-line, follows the scrubber |
| Per-app source switching | DL | When two apps play, pick which one owns the island |
| Fullscreen-app detection | BN | Island still presents over a fullscreen video |
| Sneak peek on track change | BN AL | A 2-second peek, not a full expand |
| Swipe to skip on the notch | AL NN | Trackpad swipe over the island area |

**Differentiator:** nobody does lyrics *and* queue *and* device picker in one
free app.

**Status — shipped in 0.2.0.** Artwork, title and artist in the collapsed
island; the visualiser; expanded transport and a working seek scrubber;
the output-device picker; per-app source switching; fullscreen presentation;
the two-second sneak peek on track change; and swipe to skip. Built on
`MediaRemote` — see [ADR 0002](adr/0002-mediaremote-for-now-playing.md).

Two rows are **not done**, and are recorded here rather than quietly dropped:

- **Up Next queue** and **synced lyrics.** `MediaRemote` exposes neither, and
  no other local interface exposes them for an arbitrary source — a browser
  tab has no queue to read. Reachable only for Music.app, via
  `ScriptingBridge`, and only as static lyrics with no timings. Tracked for a
  later release; it is not a 1.0 blocker.

And one row means something narrower than it sounds, which the module says out
loud in its own source:

- **The visualiser reflects playback, not amplitude.** Reading the actual
  signal means capturing system audio, which on macOS means Screen Recording
  permission and a capture session running for as long as music plays. That is
  a permission prompt and a constant cost, for decoration. Perch does not do
  it, and does not imply a spectrum analyser it has not built.

## 2. Shelf — P0

| Capability | Comes from | Notes |
|---|---|---|
| Drag a file to the top edge, island becomes a drop target | DL NN SE NB BN | Drop zone appears on drag-hover, not on drag-start |
| Hold files across app switches, Spaces, fullscreen | DL NN | Persisted to disk, survives relaunch if configured |
| Drag back out to any app | all shelf apps | Promise-based file provider, original untouched |
| Folders and multi-file drops | DL NN | A folder is one item |
| Text and image clippings | NN | Dragged selections become clippings |
| **AirDrop straight from the shelf** | DL | Sharing sheet anchored to the island |
| **Share sheet / copy link** | DL NB | Drop-to-share, NotchBay's headline feature |
| **Quick file conversion** | DL | HEIC→JPG, PNG→JPG, WebP, MOV→MP4, resize. On-device, ffmpeg-free where AVFoundation and ImageIO can do it |
| Clear-on-quit toggle | DL | Off by default |
| Stack badge with count when collapsed | DL NN | |

**Status — shipped in 0.3.0.** Drag-to-the-notch drop target, holding across
app switches and relaunches, drag back out to any app, folders as single
items, text and image clippings, the share sheet (which is where AirDrop
lives — there is no separate AirDrop API and there does not need to be),
HEIC/PNG/TIFF/WebP → JPEG/PNG/HEIC and MOV → MP4 conversion, clear-on-quit
(off by default), and the stack badge.

Conversion uses ImageIO and AVFoundation only. No ffmpeg, no bundled binary,
nothing extra to notarise — which is why the conversion list stops where it
does, and why the feature costs the download nothing. There is a test that
asserts no ffmpeg-shaped library is linked into the process.

Files are **copied** into Perch's own folder, never moved. The original stays
where you dragged it from. That is `TC-SHF-002`, and it is checked at the one
place that could break it.

## 3. Clipboard history — P0 ★

The single biggest gap in the paid field. NotchNook is $25 and does not have
this. DynamicLake's "clipboard" is file clips, not text history.

| Capability | Comes from | Notes |
|---|---|---|
| Text, rich text, image, file-path and colour history | ★ | Colour swatches render as swatches |
| Searchable, keyboard-driven picker | ★ | Global shortcut, type to filter, Enter pastes |
| Pinning | ★ | Pinned entries never evicted |
| Configurable retention (count and age) | ★ | Default 200 items / 7 days |
| Exclusion list | ★ | 1Password, Bitwarden, Keychain excluded out of the box |
| `NSPasteboardTypeAutoGenerated` / concealed type respected | ★ | Never captured, no setting needed |
| Paste as plain text modifier | ★ | ⌥ on select |
| **OCR on copied images** | NB | NotchBay's tray reads text out of a copied screenshot. On-device Vision framework, no network |
| Storage inside the app container only | ★ | See `TEST-PLAN.md` TC-PRV-003 |

**Where "the container" is.** Perch is not sandboxed — it reads pasteboard
changes, drives the Accessibility API and reads IOKit sensors, none of which
is possible inside the App Sandbox. So the container is
`~/Library/Application Support/app.perch.Perch/`, and everything the shelf and
the clipboard keep stays inside it. The trade is stated plainly in the
entitlements file: no sandbox, no network, and the source is right there.

NotchBay caps its tray at 60 clips. Ours is configurable and defaults to 200.

**Status — shipped in 0.3.0.** Text, rich text, images, file paths and
colours; a searchable picker on a global shortcut; pinning; configurable
retention by count and age; the exclusion list, shipped populated; concealed
pasteboard types honoured unconditionally; paste as plain text; and on-device
OCR of copied images through Vision.

**This module contains Perch's only polling loop.** `NSPasteboard` has no
notification of any kind — no delegate, no `NSNotification`, no observable
property — so the only way to know something was copied is to read
`changeCount` and compare. Every clipboard manager on macOS does this.
[ADR 0003](adr/0003-polling-the-pasteboard.md) records the decision and the
constraints: 600ms, only while the module is on, suspended on screen lock and
on sleep, and the pasteboard's *contents* read only when the count actually
changed. Claiming to be purely event-driven while shipping a timer is the
kind of small dishonesty this project cannot afford.

**Two things are not settings and never will be.** A concealed pasteboard
type is never recorded — no checkbox, no override, because the app that
marked it knows better than a checkbox. And the shortcut has no default: a
clipboard manager that claims a global hotkey without being asked will
collide with something, and the collision will be silent.

## 4. Focus timer — P0

| Capability | Comes from | Notes |
|---|---|---|
| Pomodoro with configurable work/break lengths | SE NB | 25/5 default |
| Countdown lives in the collapsed island | SE | Not a window, not a menu-bar string |
| Session and streak counts | SE | Streak increments once per day |
| Pre-empts Now Playing when a session ends | ★ | Priority rule, `CLAUDE.md` §3 |
| Survives sleep | ★ | Wall-clock accounting on wake |
| Auto-enable macOS Focus mode during a session | ★ | Optional |

**Status — shipped in 0.5.0, five of the six rows.** Configurable work and
break lengths (25/5/15 and four sessions to the long break by default), the
countdown in the collapsed island, session and streak counts, the finished
alert pre-empting Now Playing, and survival of sleep.

**There is no ticking anywhere in this module**, which is worth saying because
a Pomodoro timer is the most obvious place in the whole app to put a
one-second repeating timer. Three things make it unnecessary:

- `PomodoroTimer` is wall-clock: a running phase is the `Date` it ends at, and
  the time left is computed on demand. That *is* TC-FOC-004 — a Mac asleep for
  forty minutes wakes to a session that is simply over, with no accounting,
  because nothing was ever counting.
- The countdown is drawn with `Text(timerInterval:)`, which macOS renders
  itself. It does not exist while the island is not showing it.
- Completion is one `Task.sleep` to the moment the phase ends, cancelled the
  instant anything changes.

One row is **not** done:

- **Auto-enabling a macOS Focus during a session.** There is no interface for
  *setting* a Focus at any level — the entitlement belongs to Apple's own apps
  — so Perch can read which Focus is on and show it (module 6 does), but not
  turn one on. The route that does exist is a user-written Shortcut, which
  belongs to module 13 rather than here. Preferences says so in the pane
  rather than leaving somebody hunting for the switch.

Two decisions the table left open:

- **The next phase is queued, not started.** A break that begins by itself
  while you are still typing is a break you do not take, and a work session
  that begins by itself is worse. The finished alert offers to start it.
- **A session running when Perch quits is not resumed.** The timer is a thing
  you start on purpose, and silently resuming one from yesterday is worse than
  forgetting it.

## 5. Calendar and meetings — P0

| Capability | Comes from | Notes |
|---|---|---|
| Next event, countdown, lead-time alert | SE NB DL NN | EventKit, lazily permissioned |
| One-click join | NB SE | Meet, Zoom, Teams, Webex, Around, Whereby |
| **In-call mute, camera and leave controls** | NB | NotchBay's stickiest feature. Per-app scripting/Accessibility |
| Agenda peek in the expanded state | NN | Today and tomorrow |
| All-day events excluded from countdown | ★ | |
| Reminders integration | NN | Complete from the island |

## 6. HUD replacement — P0

Alcove's whole personality. Replace every stock overlay.

| Capability | Comes from | Notes |
|---|---|---|
| Volume, brightness, keyboard backlight | AL SE NN DL NB | Stock HUD suppressed while the module is on |
| Charging / power-source change | AL | Plug-in animation at the notch |
| Bluetooth device connect and disconnect | AL DL | AirPods connect animation |
| Focus mode changed | AL | |
| AirDrop received | AL | |
| Screen recording / camera in use indicator | AL | Privacy dot, but useful |
| Do Not Disturb state | AL | |
| Per-HUD on/off switches | AL | Every one individually |

**Status — shipped in 0.5.0, six of the eight rows.** Volume and mute
(CoreAudio, entirely public), display brightness, charging, Bluetooth connect
and disconnect, Focus — Do Not Disturb is a Focus, so the two rows above are
one HUD — and a camera-and-microphone-in-use indicator. Every one is
individually switchable, and the stock overlay is suspended while the module
is on and restored the instant it is switched off or Perch quits.

Brightness and the suppression both need private interfaces, and
[ADR 0005](adr/0005-private-apis-for-the-hud.md) is the decision: what is
used, how it is contained, and how each half degrades.

**One thing it costs, stated plainly because the website says it too.**
`OSDUIHelper` — the agent that draws the stock overlay — is started on demand,
and macOS publishes no notification when it launches. (`NSWorkspace` does not
report it at all; that was checked on hardware, both ways of launching it.)
Perch catches it on its own next HUD event instead, and waits for the stock
overlay to fade before suspending it, because suspending a process while its
window is up freezes that window on screen. So **one** stock overlay appears
after the agent starts, and none after that for the rest of the session.

Two rows are **not** done, and are recorded here rather than quietly dropped:

- **Keyboard backlight.** The level can be read —
  `KeyboardBrightnessClient.brightnessForKeyboard:` works, and returned
  0.237 on the machine this was written on — but nothing on macOS publishes a
  *change* to it, at any level, public or private. A getter with no
  notification can only be used by polling, and `CLAUDE.md` §5.1 says no. It
  is not a switch in Preferences, because a switch for a HUD that can never
  fire is worse than an honest gap.
- **AirDrop received.** No property, no notification, no framework. Watching
  `~/Downloads` would fire for every download, which is a different feature
  wearing this one's name.

And one row means something narrower than it sounds:

- **"Screen recording / camera in use" is the camera and the microphone.**
  Both are property listeners on `…DeviceIsRunningSomewhere`, need no Camera
  or Microphone permission, and name the device in use. Screen recording has
  no such interface, and the only route to detecting it is Screen Recording
  permission — which Perch is not going to request in order to tell you that
  something else has it.

## 7. Battery and accessories — P0

| Capability | Comes from | Notes |
|---|---|---|
| Mac battery, charge state, time remaining | BN AL SE NB | Hidden on desktop Macs |
| AirPods: left, right, case | SE NB AL | |
| Mouse, keyboard, trackpad, and any BLE device that reports level | SE | |
| Low-battery alert once per discharge cycle | DL SE | Not repeating |
| Charging-complete alert | AL | |

**Status — shipped in 0.5.0.** All five rows. The Mac's battery, charge state
and time remaining come from `IOPSNotificationCreateRunLoopSource`, which is
a genuine push notification — there is no timer anywhere in this module. The
accessory levels come from the IO registry, which is where every Mac battery
utility gets them because there is no public API; that decision, and what
happens when Apple renames the keys, is
[ADR 0004](adr/0004-ioregistry-for-accessory-levels.md).

Two things the implementation settled that the table above left open:

- **The alerts are keyed on the power *source*, never on `isCharging`.** A
  charger that is attached but not currently taking charge — a full battery,
  or macOS holding at 80% for battery health — flips `isCharging` on and off
  by itself. Keying the announcement on that would repeat it all day. This is
  the same rule TC-HUD-005 asks of the charging HUD, and the reason the
  machine that built this module, sitting at 80% on the wall with
  `isCharging` false, was a useful thing to have.
- **The low warning rearms on plugging in, not on the level recovering.** A
  battery under load crosses the threshold, recovers a point when a core
  parks, and crosses it again. Rearming on the level would warn every time.

**This module needs no permission.** The permission table below said
Bluetooth, and that was wrong: `CoreBluetooth` and `IOBluetooth` are what
require it, and this module uses neither. Reading the IO registry needs no
entitlement and shows no prompt.

The readable state — every level, all the time — is a tile on the island's
home surface rather than an alert, because the alerts are rare by design and
a battery read-out is a thing you glance at. The tile re-reads the
accessories when it appears and at no other time: the levels are only stale
when nobody is looking at them.

## 8. Notifications — P1

| Capability | Comes from | Notes |
|---|---|---|
| Mirror notifications into the island | DL NB | |
| Inline reply for Messages and Mail | ★ | Needs Accessibility, asked lazily |
| Per-app allow/deny list | ★ | |
| Silent mode while a Focus session runs | ★ | |

## 9. Camera — P0 ★ *(you asked for this)*

Boring Notch has a mirror. Nobody has built it out. This is a cheap feature to
make genuinely better than the field.

| Capability | Comes from | Notes |
|---|---|---|
| Live webcam preview under the notch | BN NN | Expands from the island, not a separate window |
| **Pre-call check** — fires automatically when a meeting is about to start | ★ | Ties to module 5; "you're on mute / your hair" moment |
| Mirror / flip horizontally | BN | Toggle, remembered |
| Shape presets: notch-width strip, circle, rounded rect, full 16:9 | NN | |
| Pin as a floating always-on-top pill | ★ | Detaches from the island, draggable, for presenting |
| Size and opacity control | ★ | Scroll to resize while hovering |
| Device picker | ★ | Built-in, Continuity Camera, external USB |
| Snapshot to the shelf | ★ | One click, lands in module 2 |
| **Hard privacy guarantees** | ★ | No frame ever written to disk unless you press snapshot. No buffer retained after collapse. Camera released — green light off — within 500ms of closing |
| Green-light honesty | ★ | The module never opens the device to "warm up" |

Permission: Camera. Requested only on first enable, with a sheet that says
exactly what the paragraph above says.

## 10. System stats — P0 ★ *(you asked for this)*

Nobody in the seven has a real system monitor. DynamicLake shows weather;
that's the closest anyone gets to an ambient data module.

| Capability | Notes |
|---|---|
| CPU: total and per-core load, plus top process by CPU | Sampled at 2s while visible, **stopped entirely when collapsed and idle** |
| GPU: utilisation and VRAM where the API allows | Apple Silicon via IOReport, Intel best-effort |
| Memory: used, cached, swap, memory pressure colour | Green / amber / red matches Activity Monitor's own thresholds |
| Disk: free space per volume, read/write throughput | |
| Network: up/down throughput, current SSID, VPN and public-IP state | Public IP is **opt-in only** — it is the one feature that would make a network call, and it is off by default with a warning (see `CLAUDE.md` §5.2) |
| Temperature and fan RPM | Apple Silicon sensors via IOHID; degrade gracefully where unreadable |
| Uptime and load average | |
| Battery cycle count and health | Complements module 7 |
| Collapsed presentation | A two-glyph micro-gauge in the notch corner: pick any two of CPU / RAM / net / temp |
| Expanded presentation | A compact grid with 60-second sparklines |
| Alert thresholds | "Tell me when CPU > 90% for 60s", "when disk < 10GB", "when temp > 95°C". Fires as a normal island activity |
| Click through to Activity Monitor | |

**The performance trap:** a system monitor is the easiest way to break
`CLAUDE.md` §5.1. The sampler must be owned by the *view's* lifetime, not the
module's — when the island is collapsed and no gauge is shown, no timer exists.
When the collapsed micro-gauge is shown, the sample interval drops to 5s. This
is enforced by TC-SYS-009 and TC-PRF-002.

## 11. Weather — P1

| Capability | Comes from | Notes |
|---|---|---|
| Current conditions and temperature in the island | DL | WeatherKit, or a user-supplied provider key |
| Hourly strip and today's high/low in the expanded state | DL | |
| Severe-weather alerts | ★ | |

This is the second module that touches the network. It is off by default and
the Preferences pane says so.

## 12. Window management — P1

| Capability | Comes from | Notes |
|---|---|---|
| Drag a window to the notch to snap it | DL | Halves, quarters, thirds, maximise |
| Layout presets from the expanded island | DL | |
| App switcher in the notch | DL | ⌘-Tab replacement, optional |

Needs Accessibility. Asked lazily.

## 13. Shortcuts and automation — P1

| Capability | Comes from | Notes |
|---|---|---|
| Run a Shortcut from the island | NN | Pick favourites, they appear as buttons |
| Perch actions exposed *to* the Shortcuts app | NN | "Show message in island", "Add to shelf", "Start focus session" |
| URL scheme `perch://` | ★ | Same actions, for scripters |
| CLI (`perch notify "…"`) | ★ | For developers piping build output into the notch |

## 14. Notes and scratchpad — P2

| Capability | Comes from | Notes |
|---|---|---|
| Quick note without leaving the app you're in | NN | Markdown, autosaved |
| Pin a note to the collapsed island | ★ | |

## 15. Voice to text — P2

Seam's differentiator, and honestly the hardest thing on this list.

| Capability | Comes from | Notes |
|---|---|---|
| On-device dictation into the focused text field | SE NB | Whisper via whisper.cpp / Core ML, model downloaded on first use |
| Push-to-talk global shortcut | SE | |
| Fully offline | SE | The model download is the only fetch, and it is explicit |

Post-1.0. Do not let this block 1.0. See `COMPARISON.md` § "Where we will not
win".

## 16. Screenshots — P2

| Capability | Comes from | Notes |
|---|---|---|
| Capture region / window / screen from the island | ★ | |
| Thumbnail lands in the shelf, annotate before sharing | ★ | |

## 17. Hide-the-notch mode — P1

TopNotch solves the opposite problem, and some of your users want that instead.
Shipping it costs almost nothing and removes a reason to install a second app.

| Capability | Comes from | Notes |
|---|---|---|
| Black out the menu bar so the notch visually disappears | TN | |
| Match the menu-bar strip to the wallpaper's top edge | TN | Re-computed on wallpaper change |
| Per-display setting | TN | |
| "Invisible until something happens" island mode | TN + ★ | Island draws nothing when idle, appears only for activities |

## 18. Appearance and gestures — P0/P1

| Capability | Comes from | Notes |
|---|---|---|
| Motion tokens shared by every module | AL | `IslandSpring`, `CLAUDE.md` §9 |
| Reduce Motion cross-fade path | ★ | Required, not optional |
| Corner radius, height, width offsets | NN | For odd display scaling |
| Light / dark / auto island tint | NN | |
| Hover, click, drag-hover, swipe, two-finger scroll gestures | AL NN | Each individually disableable |
| Virtual pill on non-notched Macs | BN SE DL | Mac mini, Studio, iMac, externals |
| Per-display island placement | ★ | Which screen owns the island, or all of them |
| Lock Screen presence | AL | P2 |

---

## Module priority summary

| # | Module | Priority | Permission needed |
|---|---|---|---|
| 1 | Now Playing | P0 | — |
| 2 | Shelf | P0 | — |
| 3 | Clipboard | P0 | — |
| 4 | Focus timer | P0 | — |
| 5 | Calendar & meetings | P0 | Calendar, Accessibility (call controls) |
| 6 | HUD replacement | P0 | — |
| 7 | Battery | P0 | — |
| 8 | Notifications | P1 | Accessibility |
| 9 | **Camera** | P0 | Camera |
| 10 | **System stats** | P0 | — |
| 11 | Weather | P1 | Location (optional) |
| 12 | Window management | P1 | Accessibility |
| 13 | Shortcuts | P1 | — |
| 14 | Notes | P2 | — |
| 15 | Voice to text | P2 | Microphone |
| 16 | Screenshots | P2 | Screen Recording |
| 17 | Hide-the-notch | P1 | — |
| 18 | Appearance & gestures | P0/P1 | — |

Seventeen of these are directories under `Sources/PerchModules/`. Number 18 is
the exception: appearance and gestures are cross-cutting and live in
`PerchUI/Motion` and `PerchUI/Preferences`, because every other module depends
on them. That is why `scaffold.sh` creates seventeen folders, not eighteen.

Eighteen modules. The paid apps average six.

## What we are deliberately not building

- **Cloud sync of clipboard or shelf.** It would need an account and a server.
  Both are banned by `CLAUDE.md` §1 and §5.2.
- **iPhone companion app.** Out of scope, and it drags in an Apple Developer
  Program dependency for something free.
- **AI summarisation of anything.** It means a network call to somebody's API.
- **A paid tier of any shape.** Reject the PR.
