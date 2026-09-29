import Foundation
import PerchCore

/// The next event, counting down beside the notch.
///
/// One activity covers both halves of the module's life — the countdown
/// before a meeting and the controls during it — because they are the same
/// event and the island must not blink between them at the moment it starts
/// (TC-CAL-002, TC-CAL-006). `isRunning` is what the view switches on.
struct CalendarActivity: IslandActivity {

    /// Identity includes the start date, because a recurring event shares one
    /// `eventIdentifier` across every occurrence. Without the date, tomorrow's
    /// standup would update today's in place rather than replacing it.
    var id: ActivityID {
        ActivityID("calendar.event.\(event.id).\(event.startDate.timeIntervalSince1970)")
    }

    let source: ModuleID = .calendar

    /// Ambient, not `systemAlert`. A meeting in five minutes is worth
    /// looking at; it is not worth taking the island from a timer that has
    /// just finished or from an incoming call. The one thing in this module
    /// that does interrupt is `MeetingStartingActivity` below.
    let priority: ActivityPriority = .ambient

    /// Held until withdrawn. The module decides when the event is over —
    /// which it knows exactly, from the event's own end date — and a
    /// countdown that collapsed after three seconds would be a notification
    /// rather than a countdown.
    let timeToLive: Duration? = nil

    let event: CalendarEvent

    /// Everything else eligible and still to come. Drawn as the stack badge.
    let queuedCount: Int

    /// Whether the event has started. The view draws a countdown before and
    /// the meeting controls after.
    let isRunning: Bool

    /// Whether the meeting controls can act on this call right now.
    ///
    /// False when the meeting has no link, when the client is not running,
    /// or when Accessibility has not been granted — all three of which the
    /// view has to say out loud rather than drawing a button that does
    /// nothing (TC-CAL-011, TC-CAL-012).
    let controls: MeetingControlState
}

/// A meeting that is starting right now.
///
/// **The one thing in the module that interrupts.** It sits at
/// `timerFinishing` in `CLAUDE.md` §3's ladder, one below an incoming call,
/// so it takes the island from whatever is playing — which is the point: you
/// are about to be late, and the music is not the priority.
///
/// It is a separate activity rather than a flag on `CalendarActivity`
/// because priority is a property of the activity, and a countdown that
/// promoted itself would also demote itself again three seconds later.
struct MeetingStartingActivity: IslandActivity {

    var id: ActivityID { ActivityID("calendar.starting.\(event.id)") }

    let source: ModuleID = .calendar
    let priority: ActivityPriority = .timerFinishing

    /// Long enough to read across a desk and to press Join. The focus
    /// timer's finished alert made the same call for the same reason.
    let timeToLive: Duration? = .seconds(12)

    let event: CalendarEvent
}

/// What the mute, camera and leave controls can do at this moment.
///
/// A value rather than three booleans on the service, so the view renders
/// one state and the tests assert one state. `unavailable` is a first-class
/// answer here: TC-CAL-011 and TC-CAL-012 both say the controls degrade to
/// "unavailable" with an explanation rather than disappearing or hanging.
struct MeetingControlState: Equatable, Sendable {

    enum Availability: Equatable, Sendable {
        /// Nothing to control — the event has no join link at all.
        case noMeeting

        /// There is a link, but its client is not running. Perch does not
        /// launch it to find out; that would open Zoom to read a checkbox.
        case notRunning

        /// Accessibility has not been granted, or was revoked mid-call
        /// (TC-CAL-012).
        case needsAccessibility

        /// The client is running but Perch cannot find the controls in it —
        /// the usual cause is the vendor shipping an update that moved them
        /// (TC-CAL-011). Deliberately distinguished from `needsAccessibility`,
        /// because the fix is completely different.
        case unsupported

        case available
    }

    var availability: Availability = .noMeeting

    /// `nil` when unknown — which is not the same as "not muted", and is why
    /// this is an optional rather than a bool. Drawing "unmuted" for a call
    /// Perch cannot read is how TC-CAL-009 fails.
    var isMuted: Bool?
    var isCameraOn: Bool?

    var service: MeetingLink.Service?

    var isActionable: Bool { availability == .available }
}
