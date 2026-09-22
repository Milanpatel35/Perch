import Foundation
import PerchCore
import SwiftUI

/// Where every module is wired in.
///
/// One line per module, and the only line the app target needs to know about.
/// Adding a module means adding it here and nowhere else — the switchboard,
/// the preferences list and the teardown path all come from `ModuleHost`
/// (`CLAUDE.md` §4).
///
/// Modules are registered whether or not they are switched on. `ModuleHost`
/// activates only the ones whose switch is on, which is what keeps a module
/// that nobody uses at literally zero cost (`CLAUDE.md` §5.1).
public enum PerchModuleRegistry {

    @MainActor
    public static func registerAll(in host: ModuleHost, island: IslandController) {
        host.register(NowPlayingService(island: island))
        host.register(ShelfService(island: island))
        host.register(ClipboardService(island: island))
        host.register(BatteryService(island: island))
        host.register(HUDService(island: island))
        host.register(FocusService(island: island))
        host.register(CalendarService(island: island))
        host.register(NotificationService(island: island))
        host.register(CameraService(island: island))
        host.register(SystemStatsService(island: island))

        wireFocusToNotifications(in: host)
        wireCalendarToCamera(in: host)
        wireCameraToShelf(in: host)
    }

    /// Lets the notification module know when a focus session is running.
    ///
    /// The one place two modules are connected, and it is here rather than
    /// inside either of them: a module that reached into another would have
    /// to know whether it was switched on, and `CLAUDE.md` §4 puts that
    /// question in exactly one place. Both closures survive either module
    /// being switched off, because `ModuleHost.service` returns `nil` for a
    /// module that is not running.
    @MainActor
    private static func wireFocusToNotifications(in host: ModuleHost) {
        guard let notifications = host.service(NotificationService.self) else { return }

        notifications.isFocusSessionRunning = { [weak host] in
            host?.service(FocusService.self)?.timer.isRunning ?? false
        }

        host.service(FocusService.self)?.onSessionEnded = { [weak host] in
            host?.service(NotificationService.self)?.releaseHeldNotifications()
        }
    }

    /// Lets the camera open itself just before a meeting.
    ///
    /// `docs/FEATURES.md` §9's "you're on mute / your hair" moment, and the
    /// module's one original idea. With the calendar switched off nothing
    /// calls the camera and nothing breaks — TC-CAM-015 is this closure not
    /// firing rather than a check inside either module.
    @MainActor
    private static func wireCalendarToCamera(in host: ModuleHost) {
        host.service(CalendarService.self)?.onMeetingApproaching = { [weak host] event in
            host?.service(CameraService.self)?
                .meetingApproaching(
                    eventID: event.id,
                    title: event.title,
                    startsAt: event.startDate,
                    hasLink: event.meeting != nil
                )
        }
    }

    /// Lands a snapshot in the shelf when the shelf is on
    /// (`docs/FEATURES.md` §9). Returning false is how the camera learns the
    /// shelf is not there, and puts the image in Pictures instead.
    @MainActor
    private static func wireCameraToShelf(in host: ModuleHost) {
        host.service(CameraService.self)?.onSnapshot = { [weak host] url in
            host?.service(ShelfService.self)?.add(fileAt: url) != nil
        }
    }

    /// The Preferences pane for a module, if it has one yet.
    ///
    /// `nil` means the module has not been built — Preferences shows the
    /// switch and says so, which is a more honest answer than a blank panel.
    @MainActor
    public static func settingsPane(
        for module: ModuleID,
        in host: ModuleHost
    ) -> AnyView? {
        earlyPane(for: module, in: host) ?? laterPane(for: module, in: host)
    }

    /// Phases 1 and 2.1–2.3. Split from `laterPane` only because one switch
    /// holding eighteen cases is unreadable long before the eighteenth.
    @MainActor
    private static func earlyPane(for module: ModuleID, in host: ModuleHost) -> AnyView? {
        switch module {
        case .nowPlaying:
            AnyView(
                NowPlayingSettingsView(
                    knownSources: host.service(NowPlayingService.self)?.knownSources ?? []
                )
            )
        case .shelf:
            shelfPane(in: host)
        case .clipboard:
            clipboardPane(in: host)
        case .focus:
            focusPane(in: host)
        case .hud:
            hudPane(in: host)
        case .battery:
            batteryPane(in: host)
        default:
            nil
        }
    }

    /// Phases 2.4 onwards.
    @MainActor
    private static func laterPane(for module: ModuleID, in host: ModuleHost) -> AnyView? {
        switch module {
        case .calendar:
            calendarPane(in: host)
        case .notifications:
            notificationsPane(in: host)
        case .camera:
            cameraPane(in: host)
        case .systemStats:
            systemStatsPane(in: host)
        default:
            nil
        }
    }

    // One function per module rather than one growing switch: the switch is a
    // dispatch table, and eighteen inline view constructions in it would be
    // unreadable long before the eighteenth.

    @MainActor
    private static func clipboardPane(in host: ModuleHost) -> AnyView? {
        host.service(ClipboardService.self).map { clipboard in
            AnyView(
                ClipboardSettingsView(
                    entryCount: clipboard.history.count,
                    pinnedCount: clipboard.history.pinned.count,
                    excludedBundleIDs: clipboard.exclusions.bundleIDs.sorted(),
                    onRetentionChange: { clipboard.setRetention($0) },
                    onClear: { clipboard.clearUnpinned() }
                )
            )
        }
    }

    @MainActor
    private static func shelfPane(in host: ModuleHost) -> AnyView? {
        host.service(ShelfService.self).map { shelf in
            AnyView(
                ShelfSettingsView(
                    itemCount: shelf.store.count,
                    byteCount: shelf.store.byteCount,
                    directory: ShelfService.defaultDirectory,
                    onClear: { shelf.clearAll() }
                )
            )
        }
    }

    @MainActor
    private static func focusPane(in host: ModuleHost) -> AnyView? {
        host.service(FocusService.self).map { focus in
            AnyView(
                FocusSettingsView(
                    configuration: focus.timer.configuration,
                    sessionsToday: focus.streak.sessions(on: Date()),
                    totalSessions: focus.streak.totalSessions,
                    streakDays: focus.streak.streak(on: Date()),
                    onChange: { focus.setConfiguration($0) }
                )
            )
        }
    }

    @MainActor
    private static func hudPane(in host: ModuleHost) -> AnyView? {
        host.service(HUDService.self).map { hud in
            AnyView(
                HUDSettingsView(
                    enabled: hud.policy.enabled,
                    isBrightnessAvailable: hud.isBrightnessAvailable,
                    isSuppressing: hud.isSuppressingStockHUD,
                    onToggle: { hud.setEnabled($0, $1) },
                    onSuppressionChange: { hud.setSuppressesStockHUD($0) }
                )
            )
        }
    }

    @MainActor
    private static func systemStatsPane(in host: ModuleHost) -> AnyView? {
        host.service(SystemStatsService.self).map { stats in
            AnyView(
                SystemStatsSettingsView(
                    gauges: stats.gauges,
                    alerts: stats.alerts.configuration,
                    snapshot: stats.snapshot,
                    isPublicIPEnabled: stats.isPublicIPEnabled,
                    isSampling: stats.isSampling,
                    onGaugesChange: { stats.setGauges($0) },
                    onAlertsChange: { stats.setAlertConfiguration($0) },
                    onPublicIPChange: { stats.setPublicIPEnabled($0) }
                )
            )
        }
    }

    @MainActor
    private static func cameraPane(in host: ModuleHost) -> AnyView? {
        host.service(CameraService.self).map { camera in
            AnyView(
                CameraSettingsView(
                    presentation: camera.presentation,
                    devices: camera.devices,
                    selectedDeviceID: camera.selectedDeviceID,
                    preCall: camera.preCall.configuration,
                    isCalendarOn: host.service(CalendarService.self) != nil,
                    onPresentationChange: { camera.setPresentation($0) },
                    onPreCallChange: { camera.setPreCallConfiguration($0) },
                    onSelectDevice: { camera.selectDevice($0) },
                    onRefreshDevices: { camera.refreshDevices() }
                )
            )
        }
    }

    @MainActor
    private static func notificationsPane(in host: ModuleHost) -> AnyView? {
        host.service(NotificationService.self).map { notifications in
            AnyView(
                NotificationSettingsView(
                    isWatching: notifications.isWatching,
                    configuration: notifications.policy.configuration,
                    knownApps: notifications.knownApps,
                    onChange: { notifications.setConfiguration($0) },
                    onRequestAccessibility: { notifications.requestAccessibility() }
                )
            )
        }
    }

    @MainActor
    private static func calendarPane(in host: ModuleHost) -> AnyView? {
        host.service(CalendarService.self).map { calendar in
            AnyView(
                CalendarSettingsView(
                    access: calendar.access,
                    remindersAccess: calendar.remindersAccess,
                    configuration: calendar.agenda.configuration,
                    calendarTitles: calendar.calendarTitles,
                    reminderCount: calendar.reminders.count,
                    onChange: { calendar.setConfiguration($0) },
                    onEnableReminders: { calendar.enableReminders() }
                )
            )
        }
    }

    @MainActor
    private static func batteryPane(in host: ModuleHost) -> AnyView? {
        host.service(BatteryService.self).map { battery in
            AnyView(
                BatterySettingsView(
                    power: battery.power,
                    accessories: battery.roster.accessories,
                    onThresholdChange: { battery.setLowThreshold($0) },
                    onRefresh: { battery.refreshAccessories() }
                )
            )
        }
    }
}
