# 6. The menu bar, not the window, for meeting controls

Date: 2026-09-22

## Status

Accepted. Records the second documented exception to `CLAUDE.md` §5.1,
alongside [ADR 0003](0003-polling-the-pasteboard.md).

## Context

`docs/FEATURES.md` §5 promises mute, camera and leave controls for a running
call, and `docs/COMPARISON.md` records them as NotchBay's stickiest feature —
the one capability people name when they explain why they pay for it.
`docs/PLAN.md` §2.4 calls it "the most technically awkward thing in the phase"
and budgets for it breaking when a vendor ships an update.

There is no API for this. Zoom, Teams and Webex publish no scripting
dictionary worth the name, no URL scheme for mute, and no notification when
their state changes. Three ways in were considered:

1. **Drive the meeting window through the Accessibility API.** A meeting
   window is a canvas of custom-drawn controls. Zoom's mute button is not an
   `AXButton` with a title; it is a rendered region whose position, label and
   element path change between releases. Anything written against it works on
   the version it was written against and fails silently on the next.

2. **Synthesise the keyboard shortcut** — post ⇧⌘A to Zoom. It is one line,
   and it is wrong twice over: the shortcut is user-configurable, and posting
   a key event tells you nothing about the resulting state. Press it when the
   call is already muted and you have unmuted somebody who thought they were
   muted. That is the worst possible failure for this feature.

3. **Drive the menu bar.** Every one of these clients puts its in-call
   commands in a menu: Zoom's `Meeting ▸ Mute Audio`, `Meeting ▸ Stop Video`,
   `Meeting ▸ End Meeting`. Menu items are `AXMenuItem` elements with titles,
   an enabled flag, and a press action.

## Decision

Drive the menu bar, through `AXUIElement`. Three consequences follow, and
they are the reason this is worth an ADR rather than a comment.

**The title is the state.** A client offering `Unmute Audio` is muted; one
offering `Mute Audio` is not. Perch reads the answer out of the app on every
refresh and never remembers it, so muting inside the Zoom window and muting
from the island cannot disagree (TC-CAL-009). Where neither title is present
the answer is `nil` — *unknown*, which the island draws as unknown rather
than as unmuted.

**It degrades honestly.** A vendor that renames a menu produces no match,
which resolves to `unsupported` and a line of text saying so (TC-CAL-011).
Accessibility not granted resolves to `needsAccessibility` with a button that
asks for it (TC-CAL-012). Client not running resolves to `notRunning`. None
of those is an error, a crash, or a dead button.

**It only covers clients with a menu bar.** Meet, Around and Whereby run in a
browser. A browser tab has no menu bar of its own and its mute button is a
`<div>`; driving it would mean reaching into whichever browser you use and
guessing at a web page's element tree. Perch does not offer controls for
those and says why — `docs/FEATURES.md` §5.

### The exception to §5.1

While a call is running **and** its controls are drivable **and** the event
is on the island, the module re-reads the menu every two seconds. This is a
polling loop and §5.1 forbids those, so:

- It exists only in that state. No running call, no timer — not a slower
  timer, none.
- It stops itself the moment the state stops being actionable, which
  includes the call ending (TC-CAL-010).
- The work is one AX query against one already-running app, with the
  messaging timeout set to 0.5s so a busy client cannot block the main
  thread (TC-CAL-011).

The countdown half of the module — the part almost everybody will use — has
no timer at all. `Agenda.nextChange(after:)` computes the exact next moment
the answer can change and the service sleeps until it.

## Consequences

- Zoom is the client this is verified against. Teams and Webex ship title
  tables that match their published menus, but they are **best effort** and
  are recorded as such in `docs/FEATURES.md` §5 and in the Preferences pane.
  A title miss is `unsupported`, not a wrong action.
- `MeetingVocabulary` is pure data in `PerchCore`, so the matching rules —
  decoration stripping, longest-match-wins, state inference — are unit
  tested without Accessibility, a client, or a call.
- Accessibility is requested when somebody presses a control for the first
  time, never on enabling the module and never at launch. The countdown, the
  agenda and the join button all work without it (`CLAUDE.md` §5.3).
- When a vendor does break this, the fix is one line in a title table rather
  than a rewrite. That was the point.
