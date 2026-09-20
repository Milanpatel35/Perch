# 2. MediaRemote for Now Playing

Date: 2026-09-20

## Status

Accepted.

## Context

Module 1 of `docs/FEATURES.md` has to answer one question: what is playing on
this Mac, in any application, right now. Every competitor answers it, so the
module is judged on motion quality rather than novelty — but it cannot be
judged at all until the data is there.

There is no public API for this. The options are:

1. **`MPNowPlayingInfoCenter`.** Publishes *your own* application's playback
   state. It reads nobody else's. Wrong shape entirely.
2. **Script each player.** `ScriptingBridge` against Music.app and Spotify.
   Covers two applications and requires an Automation permission prompt per
   application. It does not cover a browser tab, which is where most
   listening now happens — the probe that informed this decision found Chrome
   holding the session on the developer's own Mac.
3. **Capture system audio and infer.** ScreenCaptureKit can do it. It needs
   Screen Recording permission and a capture session running the whole time
   music plays, and it still yields no title, artist or artwork.
4. **`MediaRemote`.** A private framework. It is what the system itself uses,
   it reports every source including browsers, and it carries title, artist,
   album, artwork, duration, elapsed time and playback rate, plus
   notifications when any of them change.

## Decision

Use `MediaRemote`, reached through `dlopen`/`dlsym` at module activation and
isolated in one file, `Sources/PerchModules/NowPlaying/MediaRemoteBridge.swift`.

Nothing is linked against it. Every entry point is optional. If a future macOS
removes, renames or restricts a symbol, `isAvailable` goes false, the module
reports itself unavailable in its own Preferences pane, and the rest of Perch
is unaffected. Nothing in the bridge runs at launch, so nothing in it can
delay or break one.

## Consequences

**We accept a dependency on an unsupported interface.** This is a real risk
and it is worth naming plainly: Apple has restricted this framework before and
may do so again. The containment above is what makes that a degraded module
rather than a broken app, and it is the reason the bridge is one file with no
callers outside its own module.

**Notarisation is unaffected.** `dlopen` of a system framework is not a
private-API *linkage*, and Perch is distributed directly and through Homebrew
rather than through the Mac App Store, where this would not be allowed.

**Two capabilities in `docs/FEATURES.md` §1 are not reachable this way.**
`MediaRemote` exposes no play queue and no lyrics, and neither does any other
local interface for arbitrary sources. They are recorded as outstanding in
`FEATURES.md` rather than quietly dropped.

**The fallback path stays open.** If the bridge ever goes dark, option 2
becomes the degraded mode: Music.app and Spotify via ScriptingBridge, asked
for lazily, with the module saying what it can and cannot see. That is a
smaller module, not a missing one.
