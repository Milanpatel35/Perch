# The Mac notch app market, September 2026

Last updated: 20 September 2026 — NotchBay's price and feature list corrected
from its own site (it is $9 one-time, not an unspecified "paid"), and Camera
and System stats added to the matrix as the two categories nobody competes in.

Written so contributors know where Perch is matching the field and where it is
trying to be different. Prices were checked in September 2026 against
third-party roundups and vendor pages; they move, so confirm before quoting
them anywhere public.

The per-feature breakdown of everything below — what Perch absorbs from each
app, module by module — lives in [FEATURES.md](FEATURES.md).

---

## The seven apps you asked about

### Seam — $19.90 one-time, closed source, macOS 14+
Positions itself as the "complete but simple" option. The standout is offline
voice-to-text running on-device with Whisper, which no free competitor has.
Also ships a Pomodoro timer, calendar, drag-and-drop dropzones and HUDs.
Explicitly event-driven rather than polling, which is a performance claim worth
taking seriously. 48-hour trial, no credit card, then it stops working.

**Threat to us:** voice typing is genuinely expensive to build and they have it.
**Weakness:** no clipboard history, macOS 14 floor, closed source.

### Boring Notch — free, open source, macOS 13+
The incumbent free option and our closest comparison. Media controls, a basic
shelf, camera mirror. Actively maintained, code is readable. Consistently named
"best free" in every roundup, which means the slot we are competing for is
already occupied by something well-regarded.

**Threat to us:** it is already free and already open source. We cannot win on
price, only on breadth and polish.
**Weakness:** thin beyond media — no clipboard, no calendar, no timer — and
roundups repeatedly flag rough edges on multi-display setups. That is the
specific gap Perch should target.

### Alcove — roughly $15–17 one-time, closed source, macOS 14+
The animation benchmark. Closest of anything on the Mac to Apple's own Dynamic
Island feel: live activities, fluid state transitions, swipe gestures,
customisable HUDs, Lock Screen widgets. Deliberately narrow — presentation over
utility.

**Threat to us:** sets the bar for motion quality. If our island feels cheap
next to Alcove, reviewers will say so.
**Weakness:** no file tray, no clipboard, no notes. Aesthetics-first.

### DynamicLake Pro — $13.99 one-time, closed source
The broadest of the mid-priced apps: file shelf, AirDrop, share links, an Up
Next queue, notch notifications, file conversion, app switcher, weather,
Bluetooth device alerts. Also supports older macOS releases than most paid
rivals.

**Threat to us:** best features-per-dollar in the paid field.
**Weakness:** wide but shallow — battery is alerts rather than a full HUD,
meeting support is activity display only, and the "clipboard" is really just
file-shelf clips, not a text history.

### TopNotch — free, closed source
Solves the opposite problem. It blacks out the menu bar so the notch disappears
into it, which works remarkably well on mini-LED displays. No island, no
features, no maintenance burden.

**Threat to us:** none directly, but it reveals a real audience segment —
people who want the notch gone, not used. Worth a settings option that makes
Perch's island near-invisible when idle.

### NotchBay — $9 one-time, closed source, macOS 14+
Meeting-centric, and the cheapest paid entry in the field. Calendar join,
in-call mute and controls, on-device transcription, and drop-to-share are its
named differentiators. It also ships a 60-clip tray with **OCR on copied
images**, which is the closest anything in the field gets to real clipboard
history, and per-app skins that re-tint the island to the frontmost app. It
markets itself on a checkable feature matrix rather than adjectives, and its
site is the design reference for our own marketing page.

**Threat to us:** in-call controls are a strong, sticky feature, $9 is a low
bar to clear, and the OCR tray narrows our biggest differentiator.
**Weakness:** narrow audience — built for people whose day is meetings — and
the tray is capped at 60 clips with no pinning or search depth.

A warning for whoever writes marketing copy: NotchBay's hero headline is
"Your MacBook notch, finally a Dynamic Island", which is currently sitting
verbatim in our own `index.html`. See `WEBSITE-PLAN.md` §0.

### NotchNook — $25 one-time or $3/month, closed source, macOS 14+
The app that defined the category and still the most-recommended paid pick.
Most visually refined, good file tray, sensible widget system (media, calendar,
shortcuts, mirror), Shortcuts integration, five Macs per licence, and it is
bundled in Setapp.

**Threat to us:** brand recognition. "Dynamic Island for Mac" means NotchNook to
most people.
**Weakness:** most expensive way into the category, feature pace has reportedly
slowed, and for $25 it still has no clipboard history and no focus timer.

---

## Where the gaps are

Reading across all seven, six things are consistently missing or weak:

1. **Clipboard history.** Almost nobody has a real one — NotchBay's 60-clip
   OCR tray is the only serious attempt, and it has no search depth or
   pinning. Still the single biggest differentiator available.
2. **System stats.** Not one of the seven has a CPU / GPU / memory / disk /
   network / thermal monitor. DynamicLake's weather widget is the closest
   anything gets to an ambient-data module. An entire category is unoccupied.
3. **The camera, done properly.** Boring Notch and NotchNook have a mirror and
   stop there. Nobody fires it automatically before a meeting, pins it for
   presenting, or makes a privacy promise about the frames.
4. **macOS 13 Ventura support.** Nearly every paid app requires macOS 14+,
   stranding Macs that stopped at Ventura. Our floor is 13.
5. **Multi-display reliability.** The most common complaint across every app,
   free and paid. Correctness here is a feature.
6. **Breadth without a price tag.** The choice today is "free but thin" or
   "broad but $9–25". Perch is the attempt to be broad and free — eighteen
   modules against a field that averages six.

Gaps 2 and 3 are the two modules that were added to the plan most recently and
they are the ones the marketing site leads with, because they are the only
claims on the page that no competitor can answer. See `WEBSITE-PLAN.md` §5.

## Where we will not win

- **Animation polish out of the gate.** Alcove has had years. Budget real time
  for the motion layer and accept we start behind.
- **Brand recall.** NotchNook owns the search term.
- **Voice transcription.** Seam's on-device Whisper is a serious piece of work.
  Post-1.0 at the earliest, if ever.

## Positioning, in one line

> Everything the $25 apps do, plus a system monitor and a real camera module
> that none of them have, free and open source, and it runs on Ventura.

## Feature matrix

Rows marked ★ are where nothing in the field competes.

| | Perch (target) | Boring Notch | Seam | Alcove | NotchNook | DynamicLake Pro | NotchBay | TopNotch |
|---|---|---|---|---|---|---|---|---|
| Price | Free | Free | $19.90 | ~$15–17 | $25 / $3 mo | $13.99 | $9 | Free |
| Open source | Yes | Yes | No | No | No | No | No | No |
| Min macOS | 13 | 13 | 14 | 14 | 14 | 13/14 | 14 | 12 |
| Modules | 18 | 4 | 6 | 6 | 8 | 10 | 6 | 1 |
| Media controls | Yes | Yes | Yes | Yes | Yes | Yes | Yes | — |
| Lyrics / up-next queue | Yes | — | — | — | Lyrics | Queue | — | — |
| File shelf | Yes | Basic | Yes | — | Yes | Yes | Yes | — |
| AirDrop / share from shelf | Yes | — | — | — | — | Yes | Yes | — |
| File conversion | Yes | — | — | — | — | Yes | — | — |
| Clipboard history | Yes | — | — | — | — | Files only | 60 clips | — |
| Clipboard OCR | Yes | — | — | — | — | — | Yes | — |
| Focus timer | Yes | — | Yes | — | — | — | Yes | — |
| Calendar | Yes | — | Yes | — | Peek | Activities | Yes | — |
| Meeting join / call controls | Yes | — | — | — | — | — | Yes | — |
| HUD replacement | Yes | — | Yes | Yes | Yes | Yes | Yes | — |
| Battery + accessories | Yes | — | Yes | Yes | — | Alerts | Yes | — |
| Notification mirroring | Yes | — | — | — | — | Yes | Yes | — |
| **Camera mirror** | Yes | Yes | — | — | Yes | Yes | — | — |
| **Camera: pre-call check, pin, shapes** ★ | Yes | — | — | — | — | — | — | — |
| **System stats (CPU/GPU/RAM/net/temp)** ★ | Yes | — | — | — | — | — | — | — |
| Weather | Yes | — | — | — | — | Yes | — | — |
| Window snapping / app switcher | Yes | — | — | — | — | Yes | — | — |
| Shortcuts integration | Yes | — | — | — | Yes | — | — | — |
| Notes / scratchpad | Backlog | — | — | — | Yes | — | — | — |
| Screenshot capture ★ | Backlog | — | — | — | — | — | — | — |
| Voice to text | Backlog | — | Yes | — | — | — | Yes | — |
| Lock Screen presence | Backlog | — | — | Yes | — | — | — | — |
| Works without a notch | Yes | Yes | Yes | — | — | Partial | — | n/a |
| Hides the notch instead | Option | — | — | — | — | — | — | Yes |
| Telemetry | None | None | None | ? | ? | ? | ? | None |

Module counts are our reading of each vendor's own feature list, not a
published figure — they are a rough shape, not a spec. Perch's 18 is the count
in `FEATURES.md`, including P2 backlog items that are not in 1.0.

## Sources

Roundups consulted, all September 2026 or earlier. Each is published by a
competitor, so cross-read rather than trusted individually:

- notchy.dev/best-mac-notch-apps
- macnotch.io/compare/best-mac-notch-apps
- getdroppy.app/blog/best-mac-notch-apps-2026
- notchbay.com/blog/best-mac-notch-apps
- getseam.app/blog/free-dynamic-island-for-mac
- brow-app.com/blog/best-macbook-notch-apps-2026
- favtray.com/blog/dynamic-island-for-mac-notch-apps

Vendor pages read directly (more reliable than the roundups, but obviously
partisan):

- notchbay.com — read 20 Sep 2026. Source for the $9 price, the 60-clip OCR
  tray, transcription, meeting controls and per-app skins.

When you update this file, update the date at the top and say what changed.
