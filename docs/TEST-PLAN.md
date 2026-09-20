# Perch — test plan

Last updated: 20 September 2026 — added CAM (camera), SYS (system stats), WIN
(window management), SHC (Shortcuts), VOI (voice) and HID (hide-the-notch)
blocks, plus new cases in SHF and CLP for the absorbed AirDrop, file
conversion and OCR features.

Every test in the codebase references an ID from this file in its name, e.g.
`test_TC_GEO_003_externalDisplayHasNoNotchInset`. If you add a case here, add
the ID before you write the test.

Levels:

- **U** unit — `Tests/PerchCoreTests`, fast, no UI, no sleeping, no real system
  services. Must run in under 10 seconds as a suite.
- **S** snapshot — `Tests/PerchUITests`, renders a view at fixed size and
  compares to a reference image.
- **E** end-to-end — XCUITest against the running app.
- **M** manual — needs hardware or a display arrangement CI cannot provide.
  Lives in the release checklist at the bottom.

---

## GEO — notch geometry and displays

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-GEO-001 | U | Notched built-in display | `NotchMetrics` returns non-zero width and height from `safeAreaInsets` |
| TC-GEO-002 | U | Non-notched built-in display | Returns `.virtual` mode with a synthesised pill size |
| TC-GEO-003 | U | External display attached | No notch inset reported; virtual pill used |
| TC-GEO-004 | U | Two notch sizes (14" vs 16") | Metrics differ; no hardcoded constants used |
| TC-GEO-005 | E | Display hot-plugged while island expanded | Island collapses, re-anchors to the active screen, no crash |
| TC-GEO-006 | E | Display arrangement changed at runtime | Island moves to the new primary within one runloop |
| TC-GEO-007 | E | Resolution / scale factor changed | Island re-lays out at correct pixel size, no blur |
| TC-GEO-008 | E | Screen rotated (external portrait) | Island anchors to the top edge, does not clip |
| TC-GEO-009 | U | Screen with zero-height safe area | Falls back to virtual mode rather than dividing by zero |
| TC-GEO-010 | E | Sidecar / iPad as second display | No island drawn on the Sidecar screen unless enabled |
| TC-GEO-011 | U | Panel on a display narrower than the island's maximum | Panel frame never exceeds the screen; nothing hangs off either edge |
| TC-GEO-012 | U | Island inside the panel | Centred on the notch and flush with the top edge at every presentation size |

## ISL — island state machine

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-ISL-001 | U | Idle with no activities | State is `.idle`, panel ignores mouse events |
| TC-ISL-002 | U | Single activity submitted | Transitions `idle → peek`, auto-collapses after its TTL |
| TC-ISL-003 | U | Higher-priority activity during a peek | Pre-empts immediately; lower one is re-queued, not dropped |
| TC-ISL-004 | E | Hover over the notch | Expands within the spring duration |
| TC-ISL-005 | E | Mouse leaves while expanded | Collapses after the grace period, not instantly |
| TC-ISL-006 | U | Two equal-priority activities | Most recent wins; the other stays queued |
| TC-ISL-007 | U | Activity cancelled while presented | Collapses cleanly; queue advances |
| TC-ISL-008 | E | Click while expanded | Stays expanded and becomes interactive; does not steal key focus from the frontmost app |
| TC-ISL-009 | U | Queue overflow (100 activities) | Bounded; oldest low-priority entries dropped, no unbounded growth |
| TC-ISL-010 | E | Full-screen app active | Island still presents above the full-screen window |
| TC-ISL-011 | E | Mission Control / Spaces switch | Island follows to the active Space |
| TC-ISL-012 | U | Reduce Motion enabled | Transition uses cross-fade, spring tokens unused |
| TC-ISL-013 | U | Type-erased activity | Identity, priority and TTL survive erasure; re-wrapping does not nest the box |
| TC-ISL-014 | U | Home surface present when a module activity arrives | Anything above `ambient` pre-empts it; the home surface returns when that activity is withdrawn |
| TC-ISL-015 | U | Runtime applies the reducer's effects | Exactly one collapse is ever pending; a new activity replaces it rather than adding a second |

## MED — Now Playing

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-MED-001 | U | Playback starts | Activity submitted with correct title, artist, artwork |
| TC-MED-002 | U | Playback pauses | Visualiser stops; no timer left running |
| TC-MED-003 | U | Track changes mid-peek | Content updates in place; island does not re-expand |
| TC-MED-004 | U | Source with no artwork | Placeholder shown; no crash, no blank frame |
| TC-MED-005 | E | Scrubber dragged | Seek applied to the source; position echoes back correctly |
| TC-MED-006 | U | Long title and artist | Truncated with a marquee, no layout overflow |
| TC-MED-007 | U | Module disabled | All observers removed; zero notifications received |
| TC-MED-008 | E | Two media apps playing at once | Only the system's active source is shown |
| TC-MED-009 | U | Source reports itself unavailable | Module says so in its pane; no empty island, no crash |
| TC-MED-010 | U | Module switched on and off four times | Source started and stopped the same number of times; nothing left watching |
| TC-MED-011 | M | The real MediaRemote path, on a Mac that is playing something | Live playback appears, survives repeated enable/disable and repeated play/pause, and the app quits with no orphan process |

**On TC-MED-011 being manual.** The module takes its source as a parameter
(`NowPlayingSourcing`), and every case above it runs against a fake. That is
not a convenience — a level **U** test is defined at the top of this file as
having "no real system services", and a unit test that opens a private system
framework is an integration test wearing a unit test's name. It behaves like
one, too: the first version of these tests passed on the machine they were
written on and crashed on a headless CI runner with no media session. The
framework path is verified where it can honestly be verified, on a Mac that
is playing something.

## SHF — file shelf

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-SHF-001 | E | Drag a single file to the top edge | Island expands into a drop target |
| TC-SHF-002 | E | Drop, then drag back out to Finder | File copied correctly, original untouched |
| TC-SHF-003 | E | Drop 50 files at once | All accepted; UI stays responsive |
| TC-SHF-004 | U | Shelf contents across an app switch | Persisted |
| TC-SHF-005 | U | Source file deleted while shelved | Entry marked unavailable, not a dangling crash |
| TC-SHF-006 | E | Drag a folder | Accepted as a single item |
| TC-SHF-007 | E | Multi-file drop from mixed sources | Order preserved |
| TC-SHF-008 | U | Clear-on-quit enabled | Shelf empty on next launch |
| TC-SHF-009 | E | Drag text selection instead of a file | Stored as a text clipping |
| TC-SHF-010 | E | AirDrop a shelved file | Share sheet anchors to the island, transfer completes |
| TC-SHF-011 | U | Convert HEIC to JPG | Output is valid JPG, EXIF orientation preserved, original untouched |
| TC-SHF-012 | U | Convert MOV to MP4 | Output plays, audio track intact, no ffmpeg dependency linked |
| TC-SHF-013 | U | Convert an unsupported type | Refused with a readable message, not a silent no-op |
| TC-SHF-014 | E | Conversion of a 2GB video | Runs off the main thread, island stays responsive, progress shown |

## CLP — clipboard history

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-CLP-001 | U | Copy text | New entry at the top of history |
| TC-CLP-002 | U | Copy identical text twice | Deduplicated, timestamp updated |
| TC-CLP-003 | U | Copy an image | Stored with a thumbnail |
| TC-CLP-004 | U | Retention limit reached | Oldest unpinned entry evicted |
| TC-CLP-005 | U | Pinned entry at the limit | Never evicted |
| TC-CLP-006 | U | Excluded app (password manager) | Nothing captured |
| TC-CLP-007 | U | Concealed pasteboard type | Nothing captured |
| TC-CLP-008 | E | Search history | Filters as you type; Enter pastes the selection |
| TC-CLP-009 | U | Module disabled | Change-count observer stopped; history untouched on disk |
| TC-CLP-010 | U | 10,000-entry history | Search stays under 50ms |
| TC-CLP-011 | U | Copy a colour value | Stored with a rendered swatch, hex and RGB both searchable |
| TC-CLP-012 | U | OCR a copied screenshot | Extracted text attached to the entry and searchable |
| TC-CLP-013 | U | OCR an image with no text | No text attached, no error surfaced, no retry loop |
| TC-CLP-014 | U | OCR runs entirely on-device | No network request made during recognition |
| TC-CLP-015 | E | Paste as plain text (⌥ modifier) | Formatting stripped, original entry unchanged |

## FOC — focus timer

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-FOC-001 | U | Start a 25-minute session | Countdown visible in the collapsed island |
| TC-FOC-002 | U | Session completes | High-priority activity fires; pre-empts Now Playing |
| TC-FOC-003 | U | Pause and resume | Remaining time preserved exactly |
| TC-FOC-004 | E | Mac sleeps mid-session | Elapsed wall-clock time accounted for on wake |
| TC-FOC-005 | U | Session count across days | Streak increments once per day, not per session |

## BAT — battery and accessories

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-BAT-001 | U | Charger connected | Charging activity fires once, not repeatedly |
| TC-BAT-002 | U | Level drops below threshold | Low-battery alert fires once per discharge cycle |
| TC-BAT-003 | U | AirPods connected | Both buds plus case levels shown |
| TC-BAT-004 | U | Accessory disconnected | Entry removed; no stale level displayed |
| TC-BAT-005 | E | Desktop Mac with no battery | Mac battery row hidden, accessories still shown |

## CAL — calendar and meetings

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-CAL-001 | E | Calendar permission denied | Module shows an actionable explanation, app keeps working |
| TC-CAL-002 | U | Next event within the window | Countdown activity fires at the configured lead time |
| TC-CAL-003 | U | All-day event | Excluded from countdown |
| TC-CAL-004 | U | Meet / Zoom / Teams / Webex links in notes | Join button parses each correctly |
| TC-CAL-005 | U | Event with no link | No join button, no empty control |
| TC-CAL-006 | U | Overlapping events | Earliest shown; the other queued |
| TC-CAL-007 | U | Event cancelled after the alert | Activity withdrawn |
| TC-CAL-008 | E | Mute from the island during a Zoom call | Zoom's own mute state changes and stays in sync |
| TC-CAL-009 | E | Mute toggled inside the meeting app instead | Island reflects the change; the two never disagree |
| TC-CAL-010 | E | Leave from the island | Call ends, island collapses, controls withdrawn |
| TC-CAL-011 | E | Meeting app updated / element tree changed | Controls degrade to "unavailable", app does not crash or hang |
| TC-CAL-012 | E | Accessibility permission revoked mid-call | Controls disabled with an explanation, rest of the app unaffected |

## HUD — system HUD replacement

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-HUD-001 | E | Volume key pressed | Perch HUD shown, stock macOS HUD suppressed |
| TC-HUD-002 | E | Brightness key held | Continuous updates, no flicker, coalesced |
| TC-HUD-003 | E | Module disabled | Stock HUD returns immediately |
| TC-HUD-004 | E | Volume changed while island expanded | HUD composes with the expanded state, does not fight it |
| TC-HUD-005 | E | Charger connected | Charging HUD plays once, does not repeat on power fluctuation |
| TC-HUD-006 | E | AirPods connected | Connect animation with the device name and battery levels |
| TC-HUD-007 | E | Focus mode changed | HUD reflects the new mode; no HUD when the change came from Perch itself |
| TC-HUD-008 | U | Individual HUD disabled, module still on | Only that HUD stops; the others are unaffected |

## CAM — camera

The privacy cases here are promises made publicly on the website. They are not
optional and they do not get skipped when the suite is slow.

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-CAM-001 | E | Enable the module | Camera permission requested with a reason shown, never before |
| TC-CAM-002 | E | Expand the camera activity | Preview appears under the notch within 400ms |
| TC-CAM-003 | U | Mirror toggle | Horizontal flip applied; preference persists across relaunch |
| TC-CAM-004 | S | Each shape preset | Strip, circle, rounded rect and 16:9 all mask without distortion |
| TC-CAM-005 | E | Pin as a floating pill | Detaches, stays on top, draggable, survives a Space switch |
| TC-CAM-006 | E | **Collapse the island** | Capture session stops and the green light goes out within 500ms |
| TC-CAM-007 | U | **No frame reaches disk** | Filesystem watcher sees no writes during a full preview session |
| TC-CAM-008 | U | **No buffer retained after collapse** | Sample-buffer references released; leak check clean |
| TC-CAM-009 | U | **Module never opens the device to warm up** | Device opened only on explicit expand, never on enable or launch |
| TC-CAM-010 | E | Snapshot pressed | Exactly one image written, and it lands in the shelf |
| TC-CAM-011 | E | Camera in use by another app | Clear message, no hang, no fight over the device |
| TC-CAM-012 | E | Camera unplugged mid-preview | Falls back to the next device or collapses cleanly |
| TC-CAM-013 | E | Continuity Camera selected | Appears in the picker, connects, survives the iPhone sleeping |
| TC-CAM-014 | E | Pre-call check fires | Preview opens automatically under a minute before a calendar event |
| TC-CAM-015 | U | Pre-call check with Calendar module off | Does not fire; no dependency crash |
| TC-CAM-016 | E | Permission denied | Actionable explanation with a link to System Settings; app keeps working |

## SYS — system stats

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-SYS-001 | U | CPU load reported | Total and per-core values within 5% of `host_processor_info` |
| TC-SYS-002 | U | Memory reported | Used, cached and swap match `vm_stat`; pressure colour matches Activity Monitor's thresholds |
| TC-SYS-003 | U | Disk free space per volume | Matches `statfs`; external volumes appear and disappear on mount |
| TC-SYS-004 | U | Network throughput | Up/down bytes match the interface counters; no negative deltas on counter wrap |
| TC-SYS-005 | U | Temperature and fans unreadable | Rows hidden rather than showing zeroes or a crash |
| TC-SYS-006 | U | GPU stats on Intel | Degrades to "unavailable"; no Apple-Silicon-only API called |
| TC-SYS-007 | U | Alert threshold crossed | Fires once as a normal island activity, not once per sample |
| TC-SYS-008 | U | Threshold crossed then recovered then crossed again | Fires twice, with hysteresis — no flapping |
| TC-SYS-009 | U | **Island collapsed with no gauge shown** | No sampling timer exists at all. Not a slower timer — none |
| TC-SYS-010 | U | Collapsed micro-gauge shown | Sample interval is 5s; expanded is 2s |
| TC-SYS-011 | U | Module disabled | Every sampler torn down; no IOReport subscription remains |
| TC-SYS-012 | U | Public IP readout default state | Off. No network request made unless explicitly enabled |
| TC-SYS-013 | E | Public IP enabled | The one request is made, disclosed, and fails silently offline |
| TC-SYS-014 | S | Sparkline with 60 points | Renders without clipping; flat line when idle, not a blank box |
| TC-SYS-015 | M | Sustained heavy load for 10 minutes | Perch's own CPU stays under 1%; the monitor does not become the problem |

## WIN — window management

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-WIN-001 | E | Drag a window to the notch | Snap targets appear; drop snaps to the chosen region |
| TC-WIN-002 | E | Snap on a second display | Uses that display's frame, not the primary's |
| TC-WIN-003 | E | App that refuses resizing | Declines gracefully with a message, no retry loop |
| TC-WIN-004 | E | Accessibility permission absent | Module shows how to grant it; nothing else breaks |
| TC-WIN-005 | U | Module disabled | No window observers registered |

## SHC — Shortcuts and automation

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-SHC-001 | E | Run a favourite Shortcut from the island | Executes; result reported in the island |
| TC-SHC-002 | U | Perch action invoked from Shortcuts | "Show message in island" presents with the right priority |
| TC-SHC-003 | U | `perch://` URL with a malformed payload | Rejected safely; no arbitrary execution path |
| TC-SHC-004 | E | CLI `perch notify "build ok"` | Appears in the island; exits zero |

## VOI — voice to text (P2)

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-VOI-001 | E | First enable | Microphone permission requested with a reason; model download is explicit and cancellable |
| TC-VOI-002 | E | Push-to-talk dictation | Text inserted into the focused field |
| TC-VOI-003 | U | Transcription is offline | No network request after the model is present |
| TC-VOI-004 | U | Module disabled | Audio engine stopped; no microphone indicator |

## HID — hide-the-notch mode

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-HID-001 | E | Enable menu-bar blackout | Notch visually disappears into the bar |
| TC-HID-002 | E | Wallpaper changed | Top strip re-matches within one runloop |
| TC-HID-003 | E | Per-display setting | Applies only to the chosen display |
| TC-HID-004 | E | Blackout plus an island activity | Activity still presents, then the strip returns to black |
| TC-HID-005 | E | Disable | Menu bar returns to normal immediately, no artefacts |

## PRF — performance and resources

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-PRF-001 | M | One hour idle, all modules on | CPU under 1% average in Activity Monitor |
| TC-PRF-002 | M | One hour idle, all modules off | CPU effectively 0%; no timers scheduled |
| TC-PRF-003 | M | Memory after eight hours | Under 150MB, no upward drift |
| TC-PRF-004 | M | Energy impact during music playback | "Low" in Activity Monitor |
| TC-PRF-005 | U | No retain cycles | Leak check clean on module enable/disable cycles |
| TC-PRF-006 | M | Cold launch to island ready | Under 500ms |
| TC-PRF-007 | M | All 18 modules enabled, one hour idle | CPU under 1.5% average; the count of modules must not change the idle cost |
| TC-PRF-008 | M | Camera preview open for 30 minutes | Energy impact no worse than Photo Booth; thermals unchanged |
| TC-PRF-009 | M | System stats expanded for one hour | Perch under 1% CPU; sampling does not drift upwards |

## PRV — privacy

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-PRV-001 | E | Full session with a network monitor attached | No requests except the Sparkle appcast |
| TC-PRV-005 | E | Default install, every module enabled | Still no requests beyond Sparkle — Weather and public-IP are off by default |
| TC-PRV-006 | E | Weather enabled | Exactly one provider host contacted; no other host, no identifiers sent |
| TC-PRV-007 | U | Camera frames | Never written to disk, never sent anywhere. See TC-CAM-007 |
| TC-PRV-008 | U | OCR text from clipboard images | Stays in the app container; no recognition service contacted |
| TC-PRV-002 | E | Fresh launch | No permission prompts until a module needing one is enabled |
| TC-PRV-003 | U | Clipboard and shelf storage location | Inside the app container, not in shared storage |
| TC-PRV-004 | E | App uninstalled | Container removal instructions correct; nothing left in `~/Library` outside it |

## A11Y — accessibility

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-A11Y-001 | E | VoiceOver on the expanded island | Every control has a meaningful label |
| TC-A11Y-002 | E | Keyboard-only navigation | All controls reachable, focus ring visible |
| TC-A11Y-003 | S | Increase Contrast enabled | Contrast ratios meet WCAG AA |
| TC-A11Y-004 | E | Reduce Motion enabled | No spring animation anywhere |
| TC-A11Y-005 | S | Largest Dynamic Type equivalent | No clipping in the expanded layout |

## UPD — updates and lifecycle

| ID | Level | Case | Expected |
|---|---|---|---|
| TC-UPD-001 | E | Update available | Sparkle prompt appears, signature verified |
| TC-UPD-002 | E | Appcast unreachable | Fails silently, app keeps running |
| TC-UPD-003 | E | Launch at login enabled | App starts after reboot, island ready, no visible window |
| TC-UPD-004 | E | Quit from menu bar | Panel torn down, no orphan process |

---

## Manual release checklist

Run before tagging any release on `main`.

- [ ] 14" MacBook Pro, built-in only
- [ ] 16" MacBook Pro, built-in only
- [ ] MacBook Air (notched)
- [ ] Intel MacBook, non-notched
- [ ] Mac mini / Studio with one external display
- [ ] Laptop with two externals, laptop lid closed
- [ ] Mirrored displays
- [ ] macOS 13, 14, 15 and current
- [ ] Light and dark appearance
- [ ] Reduce Motion, Increase Contrast, Reduce Transparency
- [ ] Every module toggled off, then on, then off again
- [ ] Fresh install on a Mac that has never run Perch (permission flow)
- [ ] Upgrade install over the previous version (settings migrate)
- [ ] `.dmg` signed, notarised, stapled; Gatekeeper opens it without a warning

Added for the Camera and System stats modules — do not skip these, they are
the two features the launch rests on:

- [ ] Camera green light observed going **off** within 500ms of collapse, on
      hardware, by eye — not just by test
- [ ] Camera tested with built-in, Continuity Camera and an external USB webcam
- [ ] Camera tested while Zoom already holds the device
- [ ] Pre-call check fires before a real calendar event
- [ ] System stats read correctly on Apple Silicon **and** on Intel, including
      the graceful degradation of GPU and thermal rows
- [ ] System stats checked against Activity Monitor side by side for ten
      minutes — numbers must agree, not merely look plausible
- [ ] Network counters checked across a VPN connect/disconnect
- [ ] Weather and public-IP confirmed off in a fresh install (TC-PRV-005)
