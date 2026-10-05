import AppKit
import Combine
import Defaults
import PerchCore
import SwiftUI

extension CalendarGrid.Mode: Defaults.Serializable {}

extension Defaults.Keys {
    /// Week or Month on Home's calendar. Week by default: seven days and
    /// what is in them is what a glance at the notch is for.
    static let homeCalendarMode = Key<CalendarGrid.Mode>("home_calendarMode", default: .week)

    /// Week or Month on the Calendar tab, which has the room for a month.
    static let calendarTabMode = Key<CalendarGrid.Mode>("home_calendarTabMode", default: .month)
}

/// The island's calendar: a week strip or a month grid, and the chosen
/// day's events under it (or beside it, on the Calendar tab).
///
/// Events are read when the view appears, when it pages, and when
/// `changes` fires — `CalendarService` republishes its agenda when EventKit
/// reports a change. Nothing here runs on a timer. Inputs rather than the
/// service, so the picture on the website can be drawn with a demo week.
struct HomeCalendar: View {

    /// Home's corner of the surface, or the whole Calendar tab.
    enum Layout {
        case card
        case full
    }

    let access: EventKitBridge.Access
    let events: (DateInterval) -> [CalendarEvent]
    let changes: AnyPublisher<Void, Never>
    let layout: Layout

    @State private var mode: CalendarGrid.Mode = .week
    @State private var anchor = Date()
    @State private var selected = Calendar.current.startOfDay(for: Date())
    @State private var shown: [CalendarEvent] = []

    private var calendar: Calendar { .current }

    /// Home and the Calendar tab each remember their own choice.
    private var modeKey: Defaults.Key<CalendarGrid.Mode> {
        layout == .card ? .homeCalendarMode : .calendarTabMode
    }

    private var grid: CalendarGrid {
        CalendarGrid(mode: mode, containing: anchor, calendar: calendar)
    }

    var body: some View {
        Group {
            switch access {
            case .granted:
                content
            case .notDetermined:
                Notice(
                    symbol: "calendar",
                    text: "Waiting for Calendar access — check the prompt macOS showed."
                )
            default:
                Notice(
                    symbol: "calendar.badge.exclamationmark",
                    text: "Perch needs Calendar access to show your week.",
                    action: ("Open Privacy Settings", Self.openPrivacySettings)
                )
            }
        }
        .onAppear {
            mode = Defaults[modeKey]
            reload()
        }
        .onChange(of: anchor) { _ in reload() }
        .onChange(of: mode) { mode in
            Defaults[modeKey] = mode
            reload()
        }
        .onReceive(changes) { reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .card:
            // Home's corner: the week and today's first three events, or the
            // month alone in small cells — it is the grid that matters there.
            VStack(alignment: .leading, spacing: 4) {
                header
                days
                if mode == .week { dayEvents(limit: 3) }
            }
        case .full:
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    header
                    days
                }
                .frame(width: 300)

                VStack(alignment: .leading, spacing: 6) {
                    Text(selected, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    ScrollView { dayEvents(limit: nil) }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text(anchor, format: .dateTime.month(.wide).year())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            pageButton("chevron.left", by: -1, label: "Previous")
            pageButton("chevron.right", by: 1, label: "Next")

            if !calendar.isDate(selected, inSameDayAs: Date()) {
                Button("Today") {
                    anchor = Date()
                    selected = calendar.startOfDay(for: Date())
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            }

            Spacer(minLength: 4)

            ModeSwitch(mode: $mode)
        }
    }

    private func pageButton(
        _ symbol: String, by periods: Int, label: LocalizedStringKey
    ) -> some View {
        Button {
            anchor = CalendarGrid.shifting(anchor, by: periods, mode: mode, calendar: calendar)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    // MARK: - Days

    private var days: some View {
        let grid = grid
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        let size: DayCell.Size =
            mode == .week ? .large : layout == .card ? .small : .medium

        return LazyVGrid(columns: columns, spacing: size == .small ? 0 : 2) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            ForEach(grid.days) { day in
                DayCell(
                    day: day,
                    isToday: calendar.isDateInToday(day.date),
                    isSelected: calendar.isDate(day.date, inSameDayAs: selected),
                    hasEvents: !CalendarGrid.events(shown, on: day.date, calendar: calendar)
                        .isEmpty,
                    size: size
                ) {
                    selected = day.date
                }
            }
        }
    }

    /// Very short weekday names, starting from the user's first weekday.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    // MARK: - Events

    @ViewBuilder
    private func dayEvents(limit: Int?) -> some View {
        let onDay = CalendarGrid.events(shown, on: selected, calendar: calendar)
        let shown = limit.map { Array(onDay.prefix($0)) } ?? onDay

        VStack(alignment: .leading, spacing: 3) {
            if onDay.isEmpty {
                Text(
                    calendar.isDateInToday(selected) ? "Nothing else today" : "Nothing on this day"
                )
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            }
            ForEach(shown) { event in
                EventRow(event: event)
            }
            if shown.count < onDay.count {
                Text("+\(onDay.count - shown.count) more")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func reload() {
        shown = events(grid.interval)
    }

    private static func openPrivacySettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

extension HomeCalendar {

    /// The calendar module's events, re-read whenever its agenda changes.
    init(service: CalendarService, layout: Layout) {
        self.init(
            access: service.access,
            events: { [weak service] in service?.events(in: $0) ?? [] },
            changes: service.$agenda.map { _ in () }.eraseToAnyPublisher(),
            layout: layout
        )
    }
}

// MARK: - Pieces

private struct ModeSwitch: View {

    @Binding var mode: CalendarGrid.Mode

    var body: some View {
        HStack(spacing: 0) {
            option(.week, "Week")
            option(.month, "Month")
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.1)))
    }

    private func option(_ value: CalendarGrid.Mode, _ title: LocalizedStringKey) -> some View {
        Button {
            mode = value
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(.white.opacity(mode == value ? 0.22 : 0)))
                .foregroundStyle(.white.opacity(mode == value ? 1 : 0.6))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == value ? .isSelected : [])
    }
}

private struct DayCell: View {

    let day: CalendarGrid.Day
    let isToday: Bool
    let isSelected: Bool
    let hasEvents: Bool
    let size: Size
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(day.date, format: .dateTime.day())
                    .font(.system(size: size.font, weight: isToday ? .bold : .regular))
                    .foregroundStyle(foreground)
                    .frame(width: size.circle, height: size.circle)
                    .background(Circle().fill(isToday ? Color.accentColor : .clear))
                    .overlay(
                        Circle().strokeBorder(.white.opacity(isSelected && !isToday ? 0.7 : 0))
                    )
                    // The small grid has no room under a day for its dot, so
                    // the dot sits in the corner instead.
                    .overlay(alignment: .bottomTrailing) {
                        if size == .small, hasEvents {
                            Circle().fill(.white.opacity(0.7)).frame(width: 3, height: 3)
                        }
                    }
                if size != .small {
                    Circle()
                        .fill(.white.opacity(hasEvents ? 0.6 : 0))
                        .frame(width: 3, height: 3)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day.date, format: .dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Week, the Calendar tab's month, and Home's month.
    enum Size {
        case large, medium, small

        var font: CGFloat {
            switch self {
            case .large: 12
            case .medium: 10
            case .small: 9
            }
        }

        var circle: CGFloat {
            switch self {
            case .large: 22
            case .medium: 17
            case .small: 13
            }
        }
    }

    private var foreground: Color {
        if isToday { return .white }
        return .white.opacity(day.isInPeriod ? 0.9 : 0.3)
    }
}

private struct EventRow: View {

    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(event.tint)
                .frame(width: 3, height: 12)
            Text(time)
                .font(.system(size: 10, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 52, alignment: .leading)
            Text(event.title)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(event.isTentative ? 0.6 : 0.9))
                .lineLimit(1)
        }
    }

    private var time: String {
        event.isAllDay
            ? String(localized: "all-day")
            : event.startDate.formatted(date: .omitted, time: .shortened)
    }
}

/// A short explanation, and the one thing to do about it.
struct Notice: View {

    let symbol: String
    let text: LocalizedStringKey
    var action: (LocalizedStringKey, () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action: action.1) {
                    Text(action.0)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.16)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
