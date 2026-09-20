# 3. Polling the pasteboard

Date: 2026-09-20

## Status

Accepted. This is the documented exception to `CLAUDE.md` §5.1.

## Context

`CLAUDE.md` §5.1 is unambiguous: "No polling loops, no perpetual animation,
no timers that fire when nothing is on screen. Everything is event-driven."
Every other module in Perch obeys it — MediaRemote posts notifications,
NSWorkspace posts notifications, IOKit has callbacks.

**`NSPasteboard` has no notification.** There is no delegate, no
`NSNotification`, no KVO-observable property and no callback. The only way to
learn that the pasteboard changed is to read `changeCount` and compare it to
the last value you saw. This is not an oversight we can route around; it is
how the API has always worked, and it is why every clipboard manager on macOS
— free or paid — polls.

The alternatives were considered and are worse:

1. **Capture on demand only**, when the user opens the picker. This gives a
   history of one item, which is not a history.
2. **A global event monitor for ⌘C.** Needs Accessibility permission, misses
   every copy made from a menu, a context menu, a drag, or an app with its
   own shortcut, and catches ⌘C in apps where it means something else.
3. **Don't build the module.** It is the single biggest gap in the paid
   field, and the reason a lot of people would install Perch at all.

## Decision

Poll `NSPasteboard.general.changeCount` on a timer, and constrain it hard:

- **Only while the module is on.** Switched off, there is no timer, no
  observer and no state. That is the same contract every other module has.
- **600ms.** Fast enough that the picker always has what you just copied;
  slow enough to be an integer comparison roughly a hundred times a minute.
  Reading `changeCount` does not touch the pasteboard's contents and does not
  allocate.
- **Suspended when nothing can be copying.** The timer stops on screen lock
  and on sleep, and resumes on unlock and wake. A locked Mac cannot copy
  anything, so a timer running against it is pure waste.
- **Contents are read only when the count actually changed.** The expensive
  part — reading types, decoding an image, running OCR — happens on a real
  change, not on every tick.

## Consequences

**`TC-PRF-002` needs a note.** "One hour idle, all modules off: CPU
effectively 0%; no timers scheduled" still holds exactly, because the module
being off means the timer does not exist. `TC-PRF-001` and `TC-PRF-007`
("all modules on") now include this timer, and the budget is unchanged: the
tick is an integer read.

**This is the only polling loop in Perch, and it stays that way.** A second
one needs its own ADR. If a future macOS ever posts a pasteboard
notification, this module should be the first thing rewritten.

**We say so publicly.** The website's "What it doesn't do yet" section is the
right register for this: Perch polls the pasteboard, at 600ms, only while the
clipboard module is on, because macOS offers nothing else. Claiming to be
purely event-driven while shipping a timer would be the kind of small
dishonesty this project cannot afford.
