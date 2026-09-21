<div align="center">

# Perch

**Your MacBook notch, put to work. Free, forever, open source.**

Media controls, a file shelf, clipboard history, a system monitor, your camera,
timers, battery and meeting alerts — all living in the black cutout you already
paid for.

### [**perch — see it running →**](https://milanpatel35.github.io/Perch/)

The site has a live island you can actually use: hover it, click it, switch it
between states. No video, no install.

[![CI](https://github.com/Milanpatel35/Perch/actions/workflows/ci.yml/badge.svg)](https://github.com/Milanpatel35/Perch/actions/workflows/ci.yml)
[![Licence: MIT](https://img.shields.io/badge/licence-MIT-black.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black.svg)]()
[![Universal](https://img.shields.io/badge/arch-Apple%20Silicon%20%2B%20Intel-black.svg)]()

[**Website**](https://milanpatel35.github.io/Perch/) · [**Download**](https://github.com/Milanpatel35/Perch/releases/download/build-0.5.0/Perch-0.5.0-unsigned.zip) · [Features](#what-it-does) · [Why Perch](#how-it-compares) · [Contributing](CONTRIBUTING.md) · [Roadmap](docs/PLAN.md) · [Full feature list](docs/FEATURES.md)

</div>

---

## Why this exists

Apple ships the Dynamic Island free on every iPhone. On the Mac, the same idea
costs between $9 and $25 depending on whose app you buy, and the one genuinely
free open-source option covers media playback and not much else.

Perch is the attempt at the missing option: the full feature set of the paid
apps, open source, with nothing held back behind a licence key. No Pro tier,
no subscription, no account, no telemetry, no network calls beyond checking for
updates.

## What it does

| | |
|---|---|
| **Now Playing** | Artwork, scrubbing, AirPlay target, Up Next queue, synced lyrics |
| **Shelf** | Drag files to the notch, hold, drop them anywhere else. AirDrop and quick format conversion built in |
| **Clipboard** | Searchable history with pinning, text, images, colours — and OCR on anything you screenshot |
| **Focus** | Pomodoro that counts down in the notch instead of stealing a window — and survives the lid being closed, because nothing is counting |
| **Calendar** | Next meeting, countdown, one-click join — then mute, camera and leave without finding the window |
| **HUDs** | Volume, brightness, charging, Bluetooth, Focus and the camera-in-use dot — in the notch, with the macOS overlay suspended while the module is on |
| **Battery** | Mac, AirPods, mouse, keyboard, trackpad — charge state, time remaining, and one low warning per discharge cycle rather than one per wobble |
| **Notifications** | Mirrored into the island, with inline reply |
| **Camera** | Live preview under the notch. Fires automatically before a meeting so you see yourself before they do. Pin it while presenting |
| **System stats** | CPU, GPU, memory, disk, network, temperature and fans — with alert thresholds |
| **Weather** | Conditions and hourly forecast, off by default |
| **Windows** | Snap and tile by dragging a window to the notch |
| **Shortcuts** | Run Shortcuts from the island, and drive Perch from Shortcuts |
| **Hide it instead** | Prefer the notch gone? Black out the menu bar and it disappears |
| **No-notch mode** | A floating pill for Mac mini, Studio, iMac and external displays |

Eighteen modules. The paid apps average six. Every one is individually
switchable and costs nothing when off — see [docs/FEATURES.md](docs/FEATURES.md)
for the feature-by-feature breakdown, including what each one is answering in
which competitor.

Two of them exist nowhere else: **nobody in the field has a system monitor**,
and nobody has built the camera out past a plain mirror.

## Install

> **Pre-1.0.** Six of the eighteen modules are built — Now Playing, the
> Shelf, the Clipboard, the Battery, the HUDs and the Focus timer — plus the
> island itself. The rest of
> `docs/PLAN.md` is not done, and the Homebrew cask goes live with the first
> signed release. The feature table below is what 1.0 is aiming at.

**Download the app** — [Perch 0.5.0, universal](https://github.com/Milanpatel35/Perch/releases/download/build-0.5.0/Perch-0.5.0-unsigned.zip)

Apple Silicon and Intel, macOS 13+. **Not yet signed**: macOS will refuse it
on a double-click, so right-click the app → Open and confirm once. You only
do that the first time, and it stops once there is a Developer ID certificate
to sign with — at which point this becomes a notarised `.dmg` that Gatekeeper
opens without a word.

[All builds](https://github.com/Milanpatel35/Perch/releases).

**Latest build, right now** — every commit on `dev` produces a universal
(Apple Silicon + Intel) build you can download from the
[CI run's artifacts](https://github.com/Milanpatel35/Perch/actions/workflows/ci.yml?query=branch%3Adev).
It is **unsigned**, so macOS will want a right-click → Open the first time.
It is a build, not a release: artifacts expire after 30 days, and the signed,
notarised `.dmg` arrives with the certificate.

**Homebrew** (recommended once released)

```bash
brew install --cask perch
```

**Build from source**

```bash
git clone https://github.com/Milanpatel35/Perch.git
cd perch
make bootstrap
make run
```

Requires macOS 13.0 or later and Xcode 16+.

**The website** lives in [`Website/`](Website/) and deploys to
<https://milanpatel35.github.io/Perch/>. Run it locally with `make site`,
which serves it on <http://localhost:8000>. It is a hand-written static site
— no framework, no bundler — so anyone who can write HTML can fix a typo in
it. The plan for it is [docs/WEBSITE-PLAN.md](docs/WEBSITE-PLAN.md).

## How it compares

Prices checked September 2026 — confirm on each vendor's own site before
buying, since they change faster than READMEs do.

| | Perch | Boring Notch | Seam | Alcove | NotchNook | DynamicLake Pro | NotchBay | TopNotch |
|---|---|---|---|---|---|---|---|---|
| Price | **Free** | Free | $19.90 | ~$15–17 | $25 / $3 mo | $13.99 | $9 | Free |
| Open source | **Yes** | Yes | No | No | No | No | No | No |
| Minimum macOS | **13** | 13 | 14 | 14 | 14 | 13/14 | 14 | 12 |
| Media controls | Yes | Yes | Yes | Yes | Yes | Yes | Yes | — |
| File shelf | Yes | Basic | Yes | — | Yes | Yes | Yes | — |
| Clipboard history | Yes | — | — | — | — | Partial | 60 clips | — |
| Focus timer | Yes | — | Yes | — | — | — | Yes | — |
| Calendar / meeting join | Yes | — | Yes | — | Peek | Activities | Yes | — |
| In-call mute / camera / leave | Yes | — | — | — | — | — | Yes | — |
| System HUD replacement | Yes | — | Yes | Yes | Yes | Yes | Yes | — |
| **System stats** | **Yes** | — | — | — | — | — | — | — |
| **Camera beyond a mirror** | **Yes** | — | — | — | — | — | — | — |
| Window snapping | Yes | — | — | — | — | Yes | — | — |
| Works without a notch | Yes | Yes | Yes | — | — | Partial | — | n/a |
| Hides the notch instead | Option | — | — | — | — | — | — | Yes |

Full write-up with sources: [docs/COMPARISON.md](docs/COMPARISON.md).

TopNotch is in the table for completeness but solves the opposite problem — it
hides the notch by blacking out the menu bar, rather than using it.

## Privacy

Perch makes no network requests except to the Sparkle appcast when checking for
updates. Clipboard history, file shelf contents, camera frames and calendar
data never leave your Mac and are stored in the app's own container. There is
no analytics SDK, no crash reporter phoning home, and no account.

Two optional features can make a request, both **off by default** and both
disclosed where you turn them on: the weather forecast, and the public-IP
readout inside System stats. Nothing else is ever allowed to, and adding a
third requires a documented decision record, not just a pull request.

The camera specifically: no frame is written to disk unless you press the
snapshot button, no buffer is kept after the island closes, and the device is
released — green light off — within half a second of collapsing. Those are
tests in the suite, not intentions.

Permissions are requested lazily — Calendar access is only asked for when you
switch the Calendar module on, camera access only when you switch the Camera
module on, and never at launch.

## Contributing

Contributions are very welcome, especially bug reports from unusual display
setups. Start with [CONTRIBUTING.md](CONTRIBUTING.md), then look for issues
tagged `good first issue`.

If you are using an AI coding agent, point it at [CLAUDE.md](CLAUDE.md) first.

## Licence

MIT — see [LICENSE](LICENSE).

Perch is not affiliated with or endorsed by Apple Inc. "Dynamic Island" is a
trademark of Apple Inc., used here only to describe what the app resembles.
