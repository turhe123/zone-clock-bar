import AppKit
import Foundation

/// Owns the ticking clock, the saved city clocks and the month shown in the calendar grid.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var now = Date()
    @Published var displayedMonth = Date()
    @Published var clocks: [CityClock] { didSet { saveClocks() } }

    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        clocks = Self.loadClocks()
        let refresh: (Notification) -> Void = { [weak self] note in
            if note.name == .NSSystemTimeZoneDidChange { NSTimeZone.resetSystemTimeZone() }
            Task { @MainActor in self?.tick() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refresh)))
        let center = NotificationCenter.default
        for name in [Notification.Name.NSSystemTimeZoneDidChange, .NSSystemClockDidChange, .NSCalendarDayChanged, UserDefaults.didChangeNotification] {
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main, using: refresh)))
        }
        tick()
    }

    deinit {
        timer?.invalidate()
        for (center, token) in observers { center.removeObserver(token) }
    }

    /// Refreshes `now` and schedules the next tick on the next minute (or second) boundary.
    func tick() {
        now = Date()
        timer?.invalidate()
        let defaults = UserDefaults.standard
        let pattern = MenuFormat.effectivePattern(
            useCustom: defaults.bool(forKey: Keys.useCustom),
            custom: defaults.string(forKey: Keys.customPattern) ?? "",
            preset: defaults.string(forKey: Keys.preset) ?? MenuFormat.defaultPattern)
        let step: TimeInterval = MenuFormat.showsSeconds(pattern) ? 1 : 60
        let t = now.timeIntervalSinceReferenceDate
        let fireDate = Date(timeIntervalSinceReferenceDate: (floor(t / step) + 1) * step + 0.01)
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = step == 1 ? 0.05 : 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Calendar navigation

    func shiftMonth(_ delta: Int) {
        displayedMonth = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth
    }

    func goToToday() { displayedMonth = Date() }

    // MARK: Clocks

    func addClock(_ identifier: String) {
        guard TimeZone(identifier: identifier) != nil else { return }
        clocks.append(CityClock(identifier: identifier, label: ZoneMath.cityName(identifier)))
    }

    func removeClock(_ id: UUID) { clocks.removeAll { $0.id == id } }

    func moveClock(_ id: UUID, by delta: Int) {
        guard let index = clocks.firstIndex(where: { $0.id == id }) else { return }
        let target = index + delta
        guard clocks.indices.contains(target) else { return }
        clocks.swapAt(index, target)
    }

    private static func loadClocks() -> [CityClock] {
        guard let json = UserDefaults.standard.string(forKey: Keys.clocks),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([CityClock].self, from: data) else { return [] }
        return decoded
    }

    private func saveClocks() {
        guard let data = try? JSONEncoder().encode(clocks) else { return }
        UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: Keys.clocks)
    }
}
