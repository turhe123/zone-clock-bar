import SwiftUI
import AppKit

/// App entry point: a window-style menu bar extra plus a Settings window.
@main
struct ZoneClockBarApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var events = EventService()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model, events: events)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model, events: events)
        }
    }
}

/// The text shown in the menu bar, rebuilt whenever the clock ticks or settings change.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @AppStorage(Keys.preset) private var preset = MenuFormat.defaultPattern
    @AppStorage(Keys.customPattern) private var custom = ""
    @AppStorage(Keys.useCustom) private var useCustom = false

    var body: some View {
        let pattern = MenuFormat.effectivePattern(useCustom: useCustom, custom: custom, preset: preset)
        Text(MenuFormat.title(now: model.now, pattern: pattern, clocks: model.clocks))
            .monospacedDigit()
    }
}

/// External links and small AppKit helpers shared by several views.
enum Links {
    static func donate() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }

    static func openCalendarPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    static func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
