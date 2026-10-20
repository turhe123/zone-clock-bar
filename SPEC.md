# ZoneClockBar — specification

**Tagline:** A menu bar calendar with world clocks, upcoming events and a time-zone slider for planning calls across cities.

**Category:** Timers & Reminders

**Inspired by (paid):** Dato ($18 one-time)

**Frameworks:** SwiftUI, AppKit, EventKit, Foundation, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does and evidence of demand. Dato replaces the menu bar clock with a customizable date display and a dropdown containing a calendar, upcoming events and world clocks. It is sold in the Mac App Store at about 18 dollars as a single payment with lifetime updates, is also on Setapp, has been reviewed by Mac news sites and is a regular pick in lists of favorite menu bar apps on r/macapps, which shows strong demand among remote workers who juggle time zones. Our version keeps the clocks, calendar grid and event list and adds a simple meeting planner slider.

Feature set for our clean-room version. A menu bar item whose title is a configurable date and time string, chosen from presets such as Tue 20 Oct 14:05 or built from a custom pattern. Clicking opens a popover with a month calendar grid, today highlighted, week numbers optional, and arrows to move months. Under the grid is a list of events and reminders for the next few days from the user's calendars. Below that are saved city clocks, each with a custom label, the current local time, the day offset and a small sun or moon symbol. A time travel slider lets the user drag across 24 hours and see all cities' times update together, with business hours between 9 and 17 shaded, to find a call time that works for everyone. Clicking a city copies its time as text.

UI spec. A MenuBarExtra using the window style. The settings window has three sections: Menu bar format with a live preview, Clocks with an add field offering time-zone identifiers searched by city name, a reorder list and a per-clock option to also show in the menu bar, and Calendar with a first weekday picker, a week number toggle, the days of upcoming events to show and which calendars to include. General has launch at login. Empty state: with no clocks, the popover shows a prompt to add a city. With calendar access denied, the event area shows a short note and a button to grant access, and everything else still works. Keyboard: arrow keys change month, T returns to today.

Technical approach. Format menu bar text with DateFormatter for presets and for custom patterns, refreshed by a timer aligned to the next minute boundary or second if seconds are shown. Build the calendar grid with Calendar and DateComponents. Look up cities by filtering TimeZone known identifiers, converting identifiers to readable city names. Compute the offsets and day differences with TimeZone seconds from GMT for the displayed date. Read events through EventKit EKEventStore after requesting full access with requestFullAccessToEvents on macOS 14, and listen for the store changed notification to refresh. Persist clocks and options with AppStorage using Codable JSON. Launch at login uses SMAppService.

Edge cases and error handling. Daylight saving changes are handled by using the time zone's own rules for each displayed date and showing a small indicator when a city shifts within the next seven days. Handle denied or restricted calendar access without errors. Invalid custom format patterns fall back to the default and show a red hint. Update immediately after wake from sleep and when the system time zone or clock settings change, observing the corresponding notifications. Limit the menu bar width by truncating long labels. All-day and multi-day events display correctly in the list. Keep the code near 600 lines.
