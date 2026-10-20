import ServiceManagement
import SwiftUI

/// The Settings window: menu bar format, clocks, calendar and general options.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var events: EventService

    var body: some View {
        TabView {
            FormatSettings(model: model).tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            ClockSettings(model: model).tabItem { Label("Clocks", systemImage: "globe") }
            CalendarSettings(events: events).tabItem { Label("Calendar", systemImage: "calendar") }
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 460)
    }
}

/// Preset or custom date pattern for the menu bar, with a live preview.
struct FormatSettings: View {
    @ObservedObject var model: AppModel
    @AppStorage(Keys.preset) private var preset = MenuFormat.defaultPattern
    @AppStorage(Keys.customPattern) private var custom = "EEE d MMM HH:mm"
    @AppStorage(Keys.useCustom) private var useCustom = false

    var body: some View {
        Form {
            Section("Menu bar format") {
                Picker("Preset", selection: $preset) {
                    ForEach(MenuFormat.presets, id: \.self) { Text(MenuFormat.string(Date(), pattern: $0)).tag($0) }
                }
                .disabled(useCustom)
                Toggle("Use custom pattern", isOn: $useCustom)
                TextField("Pattern", text: $custom).disabled(!useCustom).font(.body.monospaced())
                if useCustom && !MenuFormat.isValid(custom) {
                    Text("Invalid pattern — the default format is used instead.").font(.caption).foregroundStyle(.red)
                }
                Text("Tokens: EEE weekday · d day · MMM month · yyyy year · HH:mm 24h · h:mm a 12h · ss seconds · 'text' literal")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Preview") {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let pattern = MenuFormat.effectivePattern(useCustom: useCustom, custom: custom, preset: preset)
                    Text(MenuFormat.title(now: context.date, pattern: pattern, clocks: model.clocks))
                        .font(.system(size: 13, weight: .medium)).monospacedDigit()
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }
}

/// Add clocks by city search, rename, reorder, remove and pin them to the menu bar.
struct ClockSettings: View {
    @ObservedObject var model: AppModel
    @State private var query = ""

    var body: some View {
        Form {
            Section("Add a clock") {
                TextField("Search by city, e.g. Tokyo", text: $query)
                ForEach(ZoneMath.search(query).prefix(8), id: \.self) { identifier in
                    Button {
                        model.addClock(identifier)
                        query = ""
                    } label: {
                        HStack {
                            Text(ZoneMath.cityName(identifier))
                            Spacer()
                            Text(identifier).foregroundStyle(.secondary)
                            Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Section("Your clocks") {
                if model.clocks.isEmpty {
                    Text("No clocks yet — search for a city above.").foregroundStyle(.secondary)
                }
                ForEach($model.clocks) { $clock in
                    HStack {
                        TextField("Label", text: $clock.label).labelsHidden()
                        Text(clock.identifier).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Toggle("Menu bar", isOn: $clock.showInMenuBar).toggleStyle(.checkbox)
                        Button { model.moveClock(clock.id, by: -1) } label: { Image(systemName: "chevron.up") }
                        Button { model.moveClock(clock.id, by: 1) } label: { Image(systemName: "chevron.down") }
                        Button { model.removeClock(clock.id) } label: { Image(systemName: "trash") }
                    }
                    .buttonStyle(.borderless)
                }
                .onMove { model.clocks.move(fromOffsets: $0, toOffset: $1) }
            }
        }
    }
}

/// First weekday, week numbers, event range and which calendars are included.
struct CalendarSettings: View {
    @ObservedObject var events: EventService
    @AppStorage(Keys.firstWeekday) private var firstWeekday = 0
    @AppStorage(Keys.weekNumbers) private var showWeeks = false
    @AppStorage(Keys.eventDays) private var eventDays = 3
    @AppStorage(Keys.excludedCalendars) private var excludedRaw = ""

    private var excluded: Set<String> { Set(excludedRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        Form {
            Section("Calendar") {
                Picker("First weekday", selection: $firstWeekday) {
                    Text("System default").tag(0)
                    ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
                }
                Toggle("Show week numbers", isOn: $showWeeks)
                Stepper("Show events for the next \(eventDays) day\(eventDays == 1 ? "" : "s")", value: $eventDays, in: 1...14)
            }
            Section("Calendars to include") {
                if events.hasAccess {
                    ForEach(events.calendars, id: \.calendarIdentifier) { calendar in
                        Toggle(isOn: binding(for: calendar.calendarIdentifier)) {
                            HStack {
                                Circle().fill(Color(cgColor: calendar.cgColor)).frame(width: 10, height: 10)
                                Text(calendar.title)
                            }
                        }
                    }
                } else {
                    Text("ZoneClockBar needs calendar access to list your events. Clocks and the calendar grid work without it.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Grant Calendar Access") { events.requestAccess() }
                }
            }
        }
        .onChange(of: eventDays) { events.reload() }
        .onChange(of: excludedRaw) { events.reload() }
        .onAppear { events.reload() }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !excluded.contains(id) },
            set: { include in
                var set = excluded
                if include { set.remove(id) } else { set.insert(id) }
                excludedRaw = set.sorted().joined(separator: ",")
            })
    }
}

/// Launch at login, support link and app info.
struct GeneralSettings: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var errorText: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Support") {
                Text("ZoneClockBar is free and open source. If it helps you plan your calls, consider supporting it.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Support / Donate ❤️") { Links.donate() }
            }
            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            errorText = nil
        } catch {
            errorText = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
