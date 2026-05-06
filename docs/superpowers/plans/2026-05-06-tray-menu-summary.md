# Tray Menu Summary & Timestamp Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the "SYNCED CALENDARS" list in the tray menu with a "Watching N calendars" summary line, and fix the "Last sync: in 0 seconds" bug by using `TimelineView` for live-updating relative timestamps.

**Architecture:** Both changes are isolated to `TrayMenuView.swift`. The calendar count comes from the existing `state.activeCalendarNames.count`. The timestamp fix wraps the last-sync label in a `TimelineView(.everyMinute)` so SwiftUI refreshes it each minute without any state changes.

**Tech Stack:** SwiftUI, `@Observable` AppState, `TimelineView`, `RelativeDateTimeFormatter`

---

### Task 1: Remove calendar section and add "Watching N calendars" summary

**Files:**
- Modify: `BeeBusy/UI/TrayMenuView.swift`

- [ ] **Step 1: Open the file and confirm current structure**

Read `BeeBusy/UI/TrayMenuView.swift`. Confirm:
- `calendarSection` is a separate computed property rendering "SYNCED CALENDARS" + a `ForEach` of calendar names
- It's included in `body` between two `Divider()` calls
- `statusSection` shows dot + status label + last sync caption

- [ ] **Step 2: Write the failing test**

Open `BeeBusyTests/` — check if there are snapshot or UI tests for `TrayMenuView`. If none exist, this is a visual-only change with no unit test surface. Skip to Step 3.

Run:
```bash
find BeeBusyTests -name "*.swift" | xargs grep -l "TrayMenuView" 2>/dev/null
```
Expected: no output (no existing TrayMenuView tests — confirm before proceeding).

- [ ] **Step 3: Replace `TrayMenuView.swift` with the updated implementation**

Replace the entire file content with:

```swift
import SwiftUI

struct TrayMenuView: View {
    @Environment(\.openSettings) private var openSettings
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusSection
            Divider()
            Button("Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusLabel)
                    .font(.callout)
            }
            if !state.activeCalendarNames.isEmpty {
                Text("Watching \(state.activeCalendarNames.count) calendar\(state.activeCalendarNames.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TimelineView(.everyMinute) { _ in
                Text(lastSyncLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        if state.isAccessDenied { return .red }
        if state.errorMessage != nil { return .orange }
        return .green
    }

    private var statusLabel: String {
        state.isAccessDenied ? "Calendar access denied" : "Active"
    }

    private var lastSyncLabel: String {
        guard let date = state.lastSyncDate else { return "Last sync: Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last sync: \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}
```

- [ ] **Step 4: Build and verify no compile errors**

```bash
xcodebuild -scheme BeeBusy -destination 'platform=macOS' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manually verify in the app**

Run the app. Open the tray menu. Confirm:
- No "SYNCED CALENDARS" section
- "Watching N calendars" appears below the status dot (or is absent when no calendars are configured)
- "Last sync: X minutes ago" updates each minute instead of staying frozen at "in 0 seconds"

- [ ] **Step 6: Commit**

```bash
git add BeeBusy/UI/TrayMenuView.swift
git commit -m "feat: replace synced calendars list with summary and fix live timestamp"
```
