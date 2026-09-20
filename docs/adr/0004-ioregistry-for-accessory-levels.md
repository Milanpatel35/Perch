# 4. Reading accessory battery levels from the IO registry

Date: 2026-09-20

## Status

Accepted. Module 7, `docs/FEATURES.md` §7.

## Context

The Mac's own battery is public API and has been for twenty years:
`IOPSCopyPowerSourcesInfo` returns the level, the power source and the time
estimate, and `IOPSNotificationCreateRunLoopSource` calls you back whenever
any of it changes. Nothing about the Mac's own battery needs a decision.

**Accessories are a different story.** There is no public API — no framework,
no notification, no documented key — for "what is my mouse's battery level"
or "how much is left in the left AirPod". The levels exist: macOS shows them
in the Bluetooth menu, in Control Centre and in the Batteries widget. They
are simply not vended to third-party apps.

What is there instead is the IO registry. Every connected accessory that
reports a level publishes an `AppleDeviceManagementHIDEventService` entry
carrying `BatteryPercent`, and, for the devices that have more than one cell,
`BatteryPercentLeft`, `BatteryPercentRight` and `BatteryPercentCase`. This is
where every Mac battery utility gets its numbers, free and paid alike.

The alternatives were considered and are worse:

1. **`IOBluetooth`.** Deprecated in its entirety, gives connection events but
   no battery levels, and would add a framework for half an answer.
2. **Parse `system_profiler SPBluetoothDataType`.** Spawns a subprocess that
   takes two seconds and returns a localised, reformattable text blob. Worse
   in every dimension, including fragility.
3. **Don't list accessories.** Module 7's entire second half. Three of the
   seven competitors ship it, and "AirPods: left, right, case" is one of the
   rows people actually compare on.

## Decision

Read the levels from the IO registry with public IOKit calls —
`IOServiceMatching`, `IOServiceGetMatchingServices`,
`IORegistryEntryCreateCFProperties` — and constrain it:

- **The framework is public and needs no entitlement, no permission and no
  `dlopen`.** Unlike [ADR 0002](0002-mediaremote-for-now-playing.md) there is
  no private framework here and nothing is loaded by hand. What is
  undocumented is the *class name* and the *key spellings*, not the API used
  to read them.
- **A failed lookup is an empty list, never a crash and never a guess.** If a
  macOS release renames the class or the keys, `AccessoryScanner.scan()`
  returns nothing, the accessory rows disappear, and the Mac's own battery —
  which is public API — carries on working. That is the correct failure for a
  read-only convenience.
- **Zero means "not reporting", not "flat".** A bud sitting in its case
  publishes its key with a zero in it. Showing that as an empty battery would
  have people charging something that is already full, so a level outside
  1–100 is treated as absent and a device reporting no level at all is not
  listed. The Mac's internal keyboard publishes this service with no battery
  keys, and it is correctly skipped rather than drawn at 0%.
- **Nothing polls.** Connect and disconnect come from
  `IOServiceAddMatchingNotification`, which is a genuine push notification.
  A level changing while a device stays connected is *not* published by
  anything, and the honest answer to that is to re-read when somebody is
  about to look — `refreshAccessories()` runs when the tile appears and when
  the list is opened — rather than to sample on a timer. This is the
  difference between this module and [ADR 0003](0003-polling-the-pasteboard.md):
  the clipboard had no choice, and this one does.

## Consequences

A level shown on the island is correct as of the last connect, disconnect, or
time the island was opened. In practice that means it is correct whenever
anybody is looking at it, which is the only time it matters, and it costs
nothing the rest of the time.

If Apple renames the registry class, accessory rows vanish until someone
updates the string. The test suite cannot catch that — CI runners have no
Bluetooth accessories — so it will be caught by a person, on hardware, which
is recorded in `docs/TEST-PLAN.md` as TC-BAT-003 at experience level.

If Apple ever ships a public API for this, replace `AccessoryScanner` with it
and delete this ADR's decision. The rest of the module — `AccessoryRoster`,
`AccessoryBattery`, every rule about ordering and staleness — is pure and
does not care where the numbers came from.
