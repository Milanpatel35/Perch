# 8. Apple Music and Spotify for Now Playing

Date: 2026-09-29

## Status

Accepted. Supersedes [ADR 0002](0002-mediaremote-for-now-playing.md).

## Context

ADR 0002 chose the private `MediaRemote` framework because it reports
whatever is playing in any app, browser tabs included. From macOS 15.4 it
refuses third-party apps. On a MacBook Pro running macOS 27 the request is
answered with `kMRMediaRemoteFrameworkErrorDomain Code=3 "Operation not
permitted"`, and the Now Playing module showed nothing, whatever was
playing. None of the tests could see that: they use an injected fake source,
which is correct for the module's rules and blind to the platform refusing
the real one.

The options were:

1. **Keep MediaRemote through a helper.** Other notch apps have `/usr/bin/perl`
   load the framework, because Apple-signed binaries are still allowed. It
   works today. It is also a workaround for a restriction Apple added on
   purpose, one update away from breaking again, and it needs a second process
   running for as long as the module is on.
2. **Ask each player directly.** Apple Music and Spotify both post a
   distributed notification on every change with the track in it, and both
   answer AppleScript. That is public, documented behaviour. It covers those two
   players and no browser tab.
3. **Switch the module off** and say it does not work on current macOS.

## Decision

Option 2. `PlayerScriptingSource` listens to `com.apple.Music.playerInfo` and
`com.spotify.client.PlaybackStateChanged`, which costs nothing between changes
and needs no permission, and parses them with `PlayerNotification` in Core.
AppleScript is used only for what the notifications leave out:
- Music's elapsed position and artwork,
- the transport buttons,
- the one read at start-up if a player is already running.

Every script runs off the main thread inside `with timeout of 2 seconds`, so a
busy player cannot hang the island.

## Consequences

- **Browser audio is no longer shown.** YouTube, SoundCloud and web players are
  not covered. The Now Playing pane, `FEATURES.md` §1 and the website say so.
- **One permission prompt per player**, from macOS's Automation dialog, the
  first time Perch reads its position or sends it a command. That only
  happens while the module is on and something is playing, never at launch
  (`CLAUDE.md` §5.3). If refused, the island still shows the track and loses
  the position and the buttons.
- **Spotify artwork is not shown.** Spotify gives a URL rather than image
  data, and fetching it would be a network request, which `CLAUDE.md` §5.2
  does not allow.
- `MediaRemoteBridge.swift` is deleted rather than kept as a dead fallback.
