# 9. Checking the front tab during a focus session

Date: 2026-10-04

## Status

Accepted. The third documented exception to `CLAUDE.md` §5.1, after the
pasteboard ([ADR 0003](0003-polling-the-pasteboard.md)) and the meeting
menu ([ADR 0006](0006-menu-bar-accessibility-for-meeting-controls.md)).

## Context

Distraction blocking (`docs/FEATURES.md` §4) closes listed sites during a
focus session. Apps are easy: `NSWorkspace` says which app came to the
front, and a listed one is hidden. Sites are not.

**No browser says that its front tab changed.** Safari and the Chromium
browsers publish the front tab's address to AppleScript, and that is all —
there is no notification, no distributed notification and no callback.
Typing `reddit.com` into a tab that is already in front changes nothing the
workspace can see.

The alternatives were considered and are worse:

1. **Block at the network.** Editing `/etc/hosts` needs root; a content
   filter needs a Network Extension, a system extension approval and a
   paid developer programme. A free notch app asking for either to stop
   somebody opening reddit is out of all proportion, and it would block the
   site for every app, all day, rather than in the front tab for 25 minutes.
2. **A browser extension.** One per browser, each in its own store, and it
   would need to talk to Perch — which is a network-shaped hole in an app
   that promises not to have one.
3. **Check only when a browser comes to the front.** Event-driven, but it
   misses the whole point: the detour is a new tab in a browser that is
   already in front.
4. **Read the window title through Accessibility.** Titles are page titles,
   not hosts, and it needs a second permission for a worse answer.

## Decision

Read the front tab of the frontmost browser every two seconds, and constrain
it hard:

- **Only during a running work phase**, and only with sites listed and site
  blocking on. Idle, paused, on a break, nothing listed or the module off:
  no task exists. `DistractionBlocklist.isEnforced(during:)` is the rule,
  and TC-FOC-013 and TC-FOC-014 test it.
- **Only while a scriptable browser is frontmost.** The check starts when
  one comes to the front and stops the moment anything else does — which
  the workspace *does* announce. With Xcode in front for 25 minutes, the
  session makes no Apple Events at all (TC-FOC-016).
- **One read, no write, almost every time.** The script returns one
  string. The blanking script runs only for a listed page.
- **A refusal stops it.** If Automation is refused for a browser, its
  checks end for that session and the settings pane names it — it is not
  asked every two seconds (TC-FOC-018).
- **Nothing outside a fixed table goes into a script.** The application
  name and the destination are constants in `Browser`; the address read
  back is only ever compared, never interpolated (TC-FOC-017).

Firefox and Arc publish no tab to AppleScript. They are named as not
supported rather than handled badly.

## Consequences

`TC-PRF-001` and `TC-PRF-002` are unchanged: neither runs a focus session.
A session with a browser in front costs one short Apple Event every two
seconds, which is the price of the feature and is paid only by somebody who
asked for it.

The Automation prompt now covers browsers as well as music players and
meeting apps, and `NSAppleEventsUsageDescription` says so.

If a browser ever posts a front-tab-changed event, this check should be the
first thing rewritten to use it.
