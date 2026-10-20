import Foundation

/// A saved world clock: a time zone plus the user's label and menu bar preference.
struct CityClock: Codable, Identifiable, Hashable {
    var id = UUID()
    var identifier: String
    var label: String
    var showInMenuBar = false

    var timeZone: TimeZone { TimeZone(identifier: identifier) ?? .current }
}

/// UserDefaults keys shared by `@AppStorage` properties across the app.
enum Keys {
    static let preset = "formatPreset"
    static let customPattern = "customPattern"
    static let useCustom = "useCustomFormat"
    static let firstWeekday = "firstWeekday"
    static let weekNumbers = "showWeekNumbers"
    static let eventDays = "eventDays"
    static let excludedCalendars = "excludedCalendars"
    static let clocks = "clocksJSON"
}

/// Builds, validates and previews the menu bar date string.
enum MenuFormat {
    static let presets = ["EEE d MMM HH:mm", "EEE d MMM h:mm a", "EEE HH:mm", "HH:mm", "HH:mm:ss", "d MMM yyyy", "EEEE, MMMM d"]
    static let defaultPattern = presets[0]
    static let maxLength = 48
    private static let fieldLetters = Set("GyYuUrQqMLlwWdDFgEecaAbBhHkKjJmsSzZOvVXx")

    /// Letters of the pattern that are outside single-quoted literals.
    private static func fields(_ pattern: String) -> [Character] {
        var quoted = false
        var result: [Character] = []
        for ch in pattern {
            if ch == "'" { quoted.toggle(); continue }
            if !quoted && ch.isLetter { result.append(ch) }
        }
        return result
    }

    static func isValid(_ pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.filter({ $0 == "'" }).count % 2 == 0 else { return false }
        let letters = fields(trimmed)
        return !letters.isEmpty && letters.allSatisfy { $0.isASCII && fieldLetters.contains($0) }
    }

    static func effectivePattern(useCustom: Bool, custom: String, preset: String) -> String {
        if useCustom { return isValid(custom) ? custom : defaultPattern }
        return presets.contains(preset) ? preset : defaultPattern
    }

    static func showsSeconds(_ pattern: String) -> Bool { fields(pattern).contains("s") }

    static func string(_ date: Date, pattern: String, zone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// Full menu bar title: the date string plus any clocks pinned to the menu bar, truncated.
    static func title(now: Date, pattern: String, clocks: [CityClock]) -> String {
        var parts = [string(now, pattern: pattern)]
        for clock in clocks where clock.showInMenuBar {
            parts.append("\(clock.label) \(ZoneMath.time(now, in: clock.timeZone))")
        }
        let full = parts.joined(separator: "  ·  ")
        return full.count > maxLength ? String(full.prefix(maxLength - 1)) + "…" : full
    }
}

/// Time zone math and display helpers used by the clocks and the time travel slider.
enum ZoneMath {
    static var allIdentifiers: [String] { TimeZone.knownTimeZoneIdentifiers }

    static func cityName(_ identifier: String) -> String {
        guard let last = identifier.split(separator: "/").last else { return identifier }
        return last.replacingOccurrences(of: "_", with: " ")
    }

    static func search(_ query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return allIdentifiers.filter {
            cityName($0).localizedCaseInsensitiveContains(q) || $0.localizedCaseInsensitiveContains(q)
        }
    }

    static func calendar(_ zone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal
    }

    static func hour(_ date: Date, in zone: TimeZone) -> Int { calendar(zone).component(.hour, from: date) }

    /// Locale-aware short time (respects the user's 12/24-hour preference).
    static func time(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date)
    }

    /// Difference in calendar days between the city's date and the local date at `date`.
    static func dayOffset(_ date: Date, in zone: TimeZone) -> Int {
        let fields: Set<Calendar.Component> = [.year, .month, .day]
        let remote = calendar(zone).dateComponents(fields, from: date)
        let local = Calendar.current.dateComponents(fields, from: date)
        let utc = calendar(TimeZone(identifier: "UTC") ?? .current)
        guard let a = utc.date(from: remote), let b = utc.date(from: local) else { return 0 }
        return utc.dateComponents([.day], from: b, to: a).day ?? 0
    }

    /// Offset from the local zone using each zone's own DST rules for `date`, e.g. "+5:30h".
    static func offsetText(_ zone: TimeZone, at date: Date) -> String {
        let diff = zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        if diff == 0 { return "Same time" }
        let sign = diff > 0 ? "+" : "−"
        let minutes = abs(diff) / 60
        return minutes % 60 == 0 ? "\(sign)\(minutes / 60)h" : "\(sign)\(minutes / 60):\(String(format: "%02d", minutes % 60))h"
    }

    /// The next daylight saving transition if it falls within the next seven days.
    static func upcomingDSTChange(_ zone: TimeZone, from date: Date) -> Date? {
        guard let next = zone.nextDaylightSavingTimeTransition(after: date),
              next.timeIntervalSince(date) <= 7 * 86_400 else { return nil }
        return next
    }
}
