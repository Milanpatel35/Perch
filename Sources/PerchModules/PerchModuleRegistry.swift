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
        switch module {
        case .clipboard:
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
        case .shelf:
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
        case .focus:
            focusPane(in: host)
        case .hud:
            hudPane(in: host)
        case .battery:
            batteryPane(in: host)
        case .calendar:
            calendarPane(in: host)
        case .nowPlaying:
            AnyView(
                NowPlayingSettingsView(
                    knownSources: host.service(NowPlayingService.self)?.knownSources ?? []
                )
            )
        default:
            nil
        }
    }

    // One function per module rather than one growing switch: the switch is a
    // dispatch table, and eighteen inline view constructions in it would be
    // unreadable long before the eighteenth.

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
