# 7. Reading the banner, not the database, for notifications

Date: 2026-09-22

## Status

Accepted.

## Context

`docs/FEATURES.md` §8 promises notifications mirrored into the island, with
inline reply for Messages and Mail. DynamicLake and NotchBay both do the
first part; nobody does the second.

**macOS has no API for this.** `UNUserNotificationCenter` hands an app its
own notifications and nobody else's, and there is no delegate, no
distributed notification and no entitlement that changes that. Two ways in
exist, and only two:

1. **The notification database.** `~/Library/Group Containers/
   group.com.apple.usernoted/db2/db` is a SQLite file holding every
   notification delivered, including ones already dismissed. It is complete,
   it is easy to read, and it is behind **Full Disk Access** — the broadest
   permission macOS grants, which a notification mirror has no business
   asking for. It also means reading notifications that were never shown,
   which is not mirroring, it is history.

2. **The banner.** The process that draws banners publishes them through the
   Accessibility API like any other window. With Accessibility granted, an
   `AXObserver` on that process reports every banner as it appears, and the
   text can be read out of the window that appeared.

## Decision

Read the banner.

The permission is the argument. Accessibility is what `docs/FEATURES.md`'s
permission table already lists for this module, it is what the window
snapping module (12) needs anyway, and it is narrower than Full Disk Access
by a wide margin. It also constrains the feature to exactly what it claims
to be: **Perch mirrors what is on screen and nothing more.** No history, no
dismissed notifications, nothing read from disk. A banner macOS chose not to
draw — because Do Not Disturb is on, because the app is not allowed to
notify — is one Perch never sees, and that is the correct behaviour rather
than a limitation to work around.

### What this costs

The banner's element tree is not documented and has changed shape across
releases. The reader does not walk a fixed path: it collects every
`AXStaticText` descendant in order, depth-limited, and assigns them by
position. Re-nesting the tree — the thing that actually changes between
macOS versions — does not break it. A banner it cannot read produces no
notification rather than an empty one.

The app that posted a notification is named in the banner in the user's own
language, and no attribute carries its bundle identifier. Perch matches the
name against running applications, which is right almost always and `nil`
otherwise. A notification with no identifier still mirrors; it just cannot
be filtered by app, and allow-list mode drops it, because "only these apps"
has to mean what it says.

Inline reply types into the banner's own reply field and presses its send
button. Everything about that is conditional — the banner may have gone, the
field may have moved, the app may never have offered one — and each case
returns false, which the island turns into "open the app" (TC-NTF-011).

### No polling

The observer is genuine push. Between two notifications the module runs no
code at all, and switched off it holds nothing: the observer is removed and
its run loop source with it (TC-NTF-009). The one thing it re-reads is the
Focus state, once per banner, through the reader the HUD module already
owns — so there is still exactly one kqueue on that database in the whole
app.

## Consequences

- Full Disk Access is never requested, and the README can say so.
- Notification history is not a feature and cannot become one without
  revisiting this decision. That is deliberate: a notification mirror that
  keeps a log is a different product with a different privacy story.
- The banner process is restarted by macOS after a crash, a log-out or a
  Focus change, and an observer attached to the old pid then watches nothing
  at all, silently. `NotificationWatcher` re-attaches on
  `didLaunchApplicationNotification`, because "notifications stopped
  working" is otherwise undiagnosable from the outside.
- Every rule about which notifications reach the island — the per-app list,
  de-duplication, coalescing, holding through a focus session — lives in
  `NotificationPolicy` in Core, where it is a unit test rather than a
  judgement call inside a C callback.
