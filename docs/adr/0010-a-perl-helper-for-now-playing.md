# 10. A perl helper for Now Playing

Date: 2026-10-05

## Status

Accepted. Supersedes [ADR 0008](0008-music-and-spotify-for-now-playing.md),
which stays in place as the fallback.

## Context

ADR 0008 took Now Playing down to Apple Music and Spotify, because from
macOS 15.4 MediaRemote answers only Apple-signed processes. It rejected the
workaround — having `/usr/bin/perl` load the framework — as one update away
from breaking, and as a second process running for as long as the module
is on.

Users disagreed with the result. Most listening on a Mac is in a browser —
YouTube, Prime Video, SoundCloud, web players — and the island showed none
of it. Every comparable notch app uses the workaround, and the user who
owns this project asked for it explicitly.

Checked on macOS 27.0.1 before deciding: the same MediaRemote call returned
nothing from a normal binary, and returned the Prime Video title playing in
Chrome, with its position and Chrome as the source, when made from a
library loaded into `/usr/bin/perl`.

## Decision

Option 1 of ADR 0008, written by us rather than taken from another project:

- `Helpers/MediaRemote/PerchMediaRemote.m` builds into
  `Perch.app/Contents/Frameworks/PerchMediaRemote.dylib`. It is never linked
  into Perch. `perch-mediaremote.pl`, in the app's Resources, loads it into
  Apple's perl and calls one of two entry points: `perch_stream`, which
  prints one JSON line per change, or `perch_command`, which sends play,
  pause, skip or seek and returns.
- **No polling.** The helper registers for MediaRemote's change
  notifications and coalesces each burst into one read. Between changes it
  sleeps.
- **Nothing is left behind.** Perch holds the helper's stdin; the helper
  exits when it closes, so quitting or crashing Perch ends it. Switching the
  module off ends it too.
- **No network, no files.** It reads MediaRemote and writes to stdout.
  `MediaRemoteLine`, in Core, reads its output, and every rule about a
  partial or malformed line is a unit test.
- **The fallback is automatic.** If the helper cannot start, exits on its
  own, or reports that MediaRemote refused it, `AnyAppNowPlayingSource`
  switches to ADR 0008's Music and Spotify source without being asked. A
  switch in the Now Playing pane turns the helper off entirely.
- **No new dependency.** The helper uses only the system's Foundation and
  MediaRemote.

## Consequences

- Browser audio and every other app that reports itself to macOS appear on
  the island again, with the browser named as the source.
- One extra process, `perl`, runs while Now Playing is on. It is idle
  between changes.
- It relies on a private framework and on Apple's perl staying a platform
  binary. When a macOS release closes either, the island falls back to
  Music and Spotify rather than going blank, and this ADR is revisited.
- The website and the Now Playing pane say plainly how it works, that it
  may stop working, and how to switch it off.
- Perch's own code signature does not change. The helper library is signed
  with the app, ad hoc included.
