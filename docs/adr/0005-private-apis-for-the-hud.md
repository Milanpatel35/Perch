# 5. Private interfaces for the HUD module

Date: 2026-09-20

## Status

Accepted. Module 6, `docs/FEATURES.md` §6. Extends the reasoning in
[ADR 0002](0002-mediaremote-for-now-playing.md) to a second case, and adds one
thing ADR 0002 did not have to consider: an effect on another process.

## Context

`docs/FEATURES.md` §6 asks for the stock overlays to be *replaced*. Not
duplicated — replaced. A notch app that draws its own volume HUD while macOS
draws one in the middle of the screen has made the machine worse, and that is
TC-HUD-001.

Two of the six HUDs cannot be built on public API.

**Display brightness.** There is no public way to read it and no public way at
all to be told it changed. `IODisplayGetFloatParameter` is the old public
answer and returns nothing useful on Apple Silicon. `DisplayServices` has
both: `DisplayServicesGetBrightness` and
`DisplayServicesRegisterForBrightnessChangeNotifications`.

**Suppressing the stock overlay.** `OSDUIHelper` is the agent that draws it.
There is no setting, no entitlement and no API to ask it to stand down.

The alternatives were considered and are worse:

1. **Ship without suppression.** Two HUDs per key press. Every reviewer would
   call it broken, and they would be right.
2. **Ship without brightness.** The single most-used HUD after volume.
3. **Drive brightness from key presses instead.** Reading the media keys needs
   an event tap, which needs Accessibility — a far larger permission than the
   one being avoided, requested for a HUD, which `CLAUDE.md` §5.3 rules out.
4. **Don't build module 6.** It is Alcove's whole personality and one of the
   most-cited reasons people buy these apps.

## Decision

Use `DisplayServices` for brightness, and suspend `OSDUIHelper` while the
module is on. Both are constrained, and the constraints are the decision.

### Brightness

- `dlopen` at activation, every symbol resolved with `dlsym`, nothing linked —
  the same shape as `MediaRemoteBridge`, and for the same reason.
- If any symbol is missing, `isAvailable` goes false, Preferences disables the
  brightness switch and says why, and the other five HUDs are unaffected.
  Nothing here runs at launch, so nothing here can fail at launch.
- **The change callback's arguments are ignored.** Its signature is
  undocumented, and a probe on this machine returned a garbage string and a
  denormal double where the name and value should be. What the callback
  reliably means is "something changed", so the level is read back through the
  getter, which *is* verified.
- Registration follows the displays, and re-registers on
  `didChangeScreenParametersNotification` — `CLAUDE.md` §5.4, because a HUD
  that stops working when you plug a monitor in is exactly the bug this
  project keeps pointing at in other people's apps.

### The stock overlay

- **`SIGSTOP`, not `SIGKILL`.** A suspended process is completely reversible:
  `SIGCONT` restores the stock HUD immediately and exactly, which is
  TC-HUD-003. Killing it would work for a moment and then have launchd respawn
  it, over and over, for as long as Perch ran.
- **Only while the module is on**, and restored on deactivate *and* on quit.
  `ModuleHost.deactivateAll()` runs on termination, so nothing is left
  suspended behind us.
- **It is a switch, not a fact.** `hud.suppressesStockHUD` is on by default,
  because without it the module looks broken — but it is the one thing Perch
  does to the rest of the system, so anybody who would rather it did not can
  say so, and Preferences shows the current state rather than hiding it.

### The launch problem, and what it costs

`OSDUIHelper` is started on demand, so it is usually not running when the
module is switched on. There is no notification for its launch:
`NSWorkspace.didLaunchApplicationNotification` does **not** fire for it —
verified on hardware, with the agent started both directly and through
LaunchServices. It is not an application `NSWorkspace` reports at all.

So the trigger is Perch's own HUD events, which is the one moment we know
something asked macOS for an overlay. The stop is *delayed* rather than
immediate, because suspending a process while its window is on screen leaves
that window frozen there — a worse bug than the one being fixed.

The cost is exact and is stated in the source and on the website: after the
agent starts, **one** stock overlay is drawn before it is caught. It then
stays suspended for the rest of the session. One overlay per launch of the
agent, not one per key press.

## Consequences

A macOS release can break either half, and they break differently.

**Brightness** degrades cleanly: a missing symbol means the switch is disabled
with an explanation and the other HUDs carry on.

**Suppression** degrades to the stock overlay simply appearing, which is
macOS's own behaviour — the failure mode is "Perch did not help", not "Perch
broke something". If `OSDUIHelper` is renamed, `signalAll` finds nothing and
does nothing.

Neither can wedge the machine. The worst case for suppression is a suspended
agent outliving Perch, and that requires Perch to be killed with `SIGKILL`
rather than quit — in which case `SIGCONT` from any source, or a log-out,
restores it.

Two rows of §6 are **not** covered by this decision because no interface
exists at any level:

- **Keyboard backlight.** `CoreBrightness` exposes
  `KeyboardBrightnessClient.brightnessForKeyboard:`, which reads the level —
  confirmed working on this machine — but nothing anywhere publishes a
  *change* to it. `BrightnessSystemClient.registerNotificationBlock:` exists
  but is not a documented path to keyboard events. A getter with no
  notification can only be used by polling, and `CLAUDE.md` §5.1 says no.
- **AirDrop received.** No property, no notification, no framework. Watching
  `~/Downloads` would fire for every download, which is not the same feature.

Both are recorded in `docs/FEATURES.md` §6 as not done, the same way Up Next
and synced lyrics are for module 1. A switch for a HUD that can never fire is
worse than an honest gap.
