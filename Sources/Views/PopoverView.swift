import AppKit
import SwiftUI

/// The menu bar dropdown: month grid, upcoming events, world clocks and footer actions.
struct PopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var events: EventService
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonthGridView(model: model)
            Divider()
            EventListView(events: events, now: model.now)
            Divider()
            ClocksView(model: model)
            Divider()
            HStack {
                SettingsLink { Label("Settings…", systemImage: "gearshape") }
                    .simultaneousGesture(TapGesture().onEnded { Links.activate() })
                Spacer()
                Button("Support / Donate ❤️") { Links.donate() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(12)
        .frame(width: 330)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.leftArrow) { model.shiftMonth(-1); return .handled }
        .onKeyPress(.upArrow) { model.shiftMonth(-1); return .handled }
        .onKeyPress(.rightArrow) { model.shiftMonth(1); return .handled }
        .onKeyPress(.downArrow) { model.shiftMonth(1); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "tT")) { _ in model.goToToday(); return .handled }
        .onAppear {
            focused = true
            model.tick()
            events.reload()
        }
    }
}

/// A month calendar grid with today highlighted and optional ISO-style week numbers.
struct MonthGridView: View {
    @ObservedObject var model: AppModel
    @AppStorage(Keys.firstWeekday) private var firstWeekday = 0
    @AppStorage(Keys.weekNumbers) private var showWeeks = false

    private var calendar: Calendar {
        var cal = Calendar.current
        if (1...7).contains(firstWeekday) { cal.firstWeekday = firstWeekday }
        return cal
    }

    var body: some View {
        let cal = calendar
        let days = Self.gridDays(for: model.displayedMonth, calendar: cal)
        let month = cal.component(.month, from: model.displayedMonth)
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        VStack(spacing: 6) {
            HStack {
                Text(MenuFormat.string(model.displayedMonth, pattern: "LLLL yyyy")).font(.headline)
                Spacer()
                Button { model.shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Button("Today") { model.goToToday() }
                Button { model.shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.borderless)
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    if showWeeks { Text("Wk").foregroundStyle(.tertiary) }
                    ForEach(0..<7, id: \.self) { Text(ordered[$0]).foregroundStyle(.secondary) }
                }
                .font(.caption)
                ForEach(0..<6, id: \.self) { row in
                    GridRow {
                        if showWeeks {
                            Text("\(cal.component(.weekOfYear, from: days[row * 7]))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        ForEach(0..<7, id: \.self) { col in
                            dayCell(days[row * 7 + col], inMonth: cal.component(.month, from: days[row * 7 + col]) == month, cal: cal)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date, inMonth: Bool, cal: Calendar) -> some View {
        let isToday = cal.isDate(day, inSameDayAs: model.now)
        return Text("\(cal.component(.day, from: day))")
            .font(.callout.weight(isToday ? .bold : .regular))
            .monospacedDigit()
            .frame(width: 34, height: 24)
            .foregroundStyle(isToday ? Color.white : (inMonth ? Color.primary : Color.secondary.opacity(0.6)))
            .background(isToday ? Circle().fill(Color.accentColor) : Circle().fill(Color.clear))
    }

    /// 42 consecutive days (6 weeks) starting on the first weekday on or before the 1st of the month.
    static func gridDays(for month: Date, calendar cal: Calendar) -> [Date] {
        let start = cal.dateInterval(of: .month, for: month)?.start ?? cal.startOfDay(for: month)
        let lead = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        let first = cal.date(byAdding: .day, value: -lead, to: start) ?? start
        return (0..<42).map { cal.date(byAdding: .day, value: $0, to: first) ?? first }
    }
}

/// Upcoming events grouped by day, or a calendar-access prompt when not authorised.
struct EventListView: View {
    @ObservedObject var events: EventService
    let now: Date

    var body: some View {
        if !events.hasAccess {
            HStack {
                Label("Calendar access is off, so events aren't shown.", systemImage: "calendar.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Grant Access") { events.requestAccess() }.controlSize(.small)
            }
        } else if events.rows.isEmpty {
            Text("No upcoming events").font(.callout).foregroundStyle(.secondary)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(groups, id: \.0) { day, rows in
                        Text(dayTitle(day)).font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 2)
                        ForEach(rows) { row in
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2).fill(row.color).frame(width: 4, height: 16)
                                Text(row.title).lineLimit(1).truncationMode(.tail)
                                Spacer()
                                Text(timeText(row)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 170)
        }
    }

    private var groups: [(Date, [EventRow])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let grouped = Dictionary(grouping: events.rows) { cal.startOfDay(for: max($0.start, today)) }
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInTomorrow(day) { return "Tomorrow" }
        return MenuFormat.string(day, pattern: "EEEE d MMM")
    }

    /// Handles timed, all-day and multi-day events (including ones that started earlier).
    private func timeText(_ row: EventRow) -> String {
        let cal = Calendar.current
        let lastDay = cal.startOfDay(for: row.end.addingTimeInterval(row.isAllDay ? -1 : 0))
        let multiDay = lastDay > cal.startOfDay(for: row.start)
        let time = { (d: Date) in ZoneMath.time(d, in: .current) }
        if row.isAllDay {
            return multiDay ? "All day · until \(MenuFormat.string(lastDay, pattern: "EEE d MMM"))" : "All day"
        }
        if multiDay {
            let endText = "\(MenuFormat.string(row.end, pattern: "EEE")) \(time(row.end))"
            return row.start < cal.startOfDay(for: now) ? "until \(endText)" : "\(time(row.start)) → \(endText)"
        }
        return "\(time(row.start)) – \(time(row.end))"
    }
}

/// Saved city clocks with a 24-hour time travel slider and business-hours shading.
struct ClocksView: View {
    @ObservedObject var model: AppModel
    @State private var offsetMinutes = 0.0
    @State private var copiedID: UUID?

    private var date: Date { model.now.addingTimeInterval(offsetMinutes * 60) }

    var body: some View {
        if model.clocks.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "globe").font(.title2).foregroundStyle(.secondary)
                Text("Add a city to see world clocks and plan calls.").font(.callout).foregroundStyle(.secondary)
                SettingsLink { Text("Add a City…") }
                    .simultaneousGesture(TapGesture().onEnded { Links.activate() })
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 4) {
                ForEach(model.clocks) { clock in clockRow(clock) }
                HStack {
                    Image(systemName: "clock.arrow.2.circlepath").foregroundStyle(.secondary)
                    Slider(value: $offsetMinutes, in: -720...720, step: 15)
                    Button(offsetLabel) { offsetMinutes = 0 }
                        .buttonStyle(.borderless).font(.caption.monospacedDigit()).frame(width: 64)
                        .help("Reset to now")
                }
                let allWorking = model.clocks.allSatisfy { (9..<17).contains(ZoneMath.hour(date, in: $0.timeZone)) }
                Text(allWorking ? "✓ Within 9–17 business hours everywhere" : "Shaded cities are within 9–17 business hours")
                    .font(.caption2).foregroundStyle(allWorking ? .green : .secondary)
            }
        }
    }

    private var offsetLabel: String {
        guard offsetMinutes != 0 else { return "Now" }
        let m = Int(abs(offsetMinutes))
        return "\(offsetMinutes > 0 ? "+" : "−")\(m / 60):\(String(format: "%02d", m % 60))"
    }

    private func clockRow(_ clock: CityClock) -> some View {
        let zone = clock.timeZone
        let hour = ZoneMath.hour(date, in: zone)
        let dayOffset = ZoneMath.dayOffset(date, in: zone)
        let dayText = dayOffset == 0 ? "" : (dayOffset > 0 ? " · +\(dayOffset)d" : " · \(dayOffset)d")
        let business = (9..<17).contains(hour)
        let dst = ZoneMath.upcomingDSTChange(zone, from: model.now)
        return Button { copy(clock) } label: {
            HStack(spacing: 8) {
                Image(systemName: (6..<18).contains(hour) ? "sun.max.fill" : "moon.fill")
                    .foregroundStyle((6..<18).contains(hour) ? Color.orange : Color.indigo)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text(clock.label).lineLimit(1)
                    Text(copiedID == clock.id ? "Copied!" : ZoneMath.offsetText(zone, at: date) + dayText)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let dst {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.orange)
                        .help("Daylight saving change on \(MenuFormat.string(dst, pattern: "EEE d MMM", zone: zone))")
                }
                Text(ZoneMath.time(date, in: zone)).font(.title3.monospacedDigit())
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(business ? Color.green.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to copy this time")
    }

    private func copy(_ clock: CityClock) {
        let zone = clock.timeZone
        let text = "\(clock.label): \(ZoneMath.time(date, in: zone)), \(MenuFormat.string(date, pattern: "EEE d MMM", zone: zone)) (\(zone.abbreviation(for: date) ?? zone.identifier))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedID = clock.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedID == clock.id { copiedID = nil }
        }
    }
}
