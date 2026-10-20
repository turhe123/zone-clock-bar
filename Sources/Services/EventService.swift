import EventKit
import SwiftUI

/// A display-ready snapshot of one calendar event occurrence.
struct EventRow: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
}

/// Wraps EventKit: requests access, loads upcoming events and follows store changes.
@MainActor
final class EventService: ObservableObject {
    @Published private(set) var status = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var rows: [EventRow] = []
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    var hasAccess: Bool { status == .fullAccess }
    var calendars: [EKCalendar] {
        hasAccess ? store.calendars(for: .event).sorted { $0.title < $1.title } : []
    }

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        reload()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Asks for access the first time; afterwards sends the user to System Settings.
    func requestAccess() {
        guard status == .notDetermined else {
            Links.openCalendarPrivacy()
            return
        }
        Task {
            _ = try? await store.requestFullAccessToEvents()
            reload()
        }
    }

    func reload() {
        status = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else { rows = []; return }
        let defaults = UserDefaults.standard
        let days = max(1, defaults.integer(forKey: Keys.eventDays) == 0 ? 3 : defaults.integer(forKey: Keys.eventDays))
        let excluded = Set((defaults.string(forKey: Keys.excludedCalendars) ?? "").split(separator: ",").map(String.init))
        let selected = store.calendars(for: .event).filter { !excluded.contains($0.calendarIdentifier) }
        let start = Calendar.current.startOfDay(for: Date())
        guard !selected.isEmpty, let end = Calendar.current.date(byAdding: .day, value: days, to: start) else {
            rows = []
            return
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
        rows = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                EventRow(
                    id: "\(event.calendarItemIdentifier)-\(event.startDate.timeIntervalSince1970)",
                    title: event.title ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    color: event.calendar.map { Color(cgColor: $0.cgColor) } ?? .accentColor)
            }
    }
}
