# Bee Busy — Design Spec

**Date:** 2026-05-06  
**Status:** Approved

---

## Overview

Bee Busy is a lightweight macOS menu bar app that keeps a "Busy" status in sync across multiple local calendars. It runs silently in the background, requires no account, no login, and no remote server. All data stays on-device via EventKit.

When an event exists in one configured calendar, Bee Busy creates a corresponding "Busy" event in every other configured calendar. If the source event is moved, resized, or deleted, the Busy events are updated or removed accordingly. No details from the source event are ever written to the Busy events — only the time block is mirrored.

---

## Tech Stack

- **Language:** Swift (open-source, Apache 2.0)
- **UI:** SwiftUI (`MenuBarExtra` for tray, standard window for Settings)
- **Calendar access:** EventKit
- **Persistence:** `UserDefaults` for settings only; no local database
- **Minimum OS:** macOS 26 Tahoe
- **Dependencies:** None beyond Apple system frameworks

---

## Architecture

Three layers with clear boundaries:

### App Shell
SwiftUI entry point. Owns the `MenuBarExtra` tray item and the Settings window. Responsible for app lifecycle, first-launch flow, and wiring the sync engine to the UI.

### Sync Engine
A pure Swift class with no UI dependencies. Subscribes to `EKEventStoreChangedNotification` and runs reconciliation. Has no knowledge of the tray or settings window — it receives configuration and emits state (last sync time, error log entries).

### EventKit Layer
Thin wrapper around `EKEventStore`. Contains the only code that reads from or writes to calendars. The `deleteEvent(_:)` function lives here and is the single deletion path in the entire app.

---

## Tray Menu

Shown when the user clicks the menu bar icon:

```
BEE BUSY
● Active
Last sync: 2 min ago
──────────────────
SYNCED CALENDARS
📅 Work
📅 Personal
📅 Side Project
──────────────────
Settings...
──────────────────
Quit
```

The `●` indicator is green when active, amber when a recoverable error has occurred, red when calendar access is denied.

---

## Settings Window

Single-pane window, no tabs. Sections:

**Calendars**  
A list of all calendars from EventKit, each with a checkbox and the calendar's colour dot. Checking a calendar adds it to the sync mesh; unchecking it triggers a cleanup sweep of that calendar's Busy events before it stops being watched.

**Look-forward window**  
Slider, range 1–90 days, default 30. Label shows the current value in days. The sync engine always operates on `[today, today + N days]` as a rolling window.

**General**  
- Launch at login toggle (default off)
- "View Logs" button — opens `~/Library/Logs/BeeBusy/bee-busy.log` via `NSWorkspace.shared.open(_:)`

---

## First-Launch Flow

1. App launches → requests EventKit access. If denied, show a one-time alert directing to System Settings → Privacy → Calendars. Sit idle until access is granted.
2. Settings window opens automatically. User selects calendars.
3. On clicking "Done" (or closing settings), the app runs a **dry run**: reconciliation logic executes in read-only mode, collecting what would be created without writing anything.
4. A **Preview sheet** is shown:
   - Summary: "X Busy events would be created across Y calendars. Nothing has been written yet."
   - Events grouped by source calendar. Up to 10 events shown per group; if more exist, a footer reads "+ N more not shown".
   - A notice: "This preview is shown once. After activating, Bee Busy runs silently in the background — no further prompts."
   - Two buttons: **Activate** and **Go Back**.
5. On Activate, the sync engine starts, writes the initial Busy events, and the app transitions to normal tray-only operation. The dry-run flow is never shown again.

---

## Sync Engine

### Change Detection

The engine subscribes to `EKEventStoreChangedNotification`. On every notification, and once on startup, it runs a full reconciliation pass over the look-forward window. There is no polling timer.

### Reconciliation Pass

1. **Fetch** all events in `[today, today + N days]` across all configured calendars from EventKit — one date-range query.
2. **Partition** into two disjoint sets:
   - **Source events** — events whose `notes` do not contain `bee-busy:source=`
   - **Our Busy events** — events whose `notes` contain `bee-busy:source=`

   This partition is the loop guard. Busy events never enter the source set and therefore never trigger further Busy event creation.

3. **Build a map** from the Busy set: `sourceCalendarItemIdentifier → [EKEvent]`

4. **For each source event** (after eligibility filtering — see below):
   - Not in map → **create** Busy events in all other configured calendars
   - In map, start/end unchanged → **no-op**
   - In map, start/end changed → **delete** old Busy events, **create** new ones

5. **For each entry in the map** whose source ID has no matching source event in the fetch results → **delete** (orphan cleanup)

### Source Event Eligibility

A source event is eligible for syncing only if **both** conditions are met:

- **No attendees** (self-created event): always eligible  
- **Has attendees**: find the attendee where `isCurrentUser == true`. Eligible only if `participantStatus == .accepted`. All other statuses (`.tentative`, `.pending`, `.declined`, `.unknown`) are excluded.

This is a whitelist check. Any status not explicitly `.accepted` results in the event being skipped — including future statuses that EventKit may introduce.

### Busy Event Format

| Field | Value |
|---|---|
| `title` | `"Busy"` |
| `notes` | `"bee-busy:source=<calendarItemIdentifier>"` |
| `startDate` | Copied from source |
| `endDate` | Copied from source |
| `isAllDay` | Copied from source |
| All other fields | Left blank / default |

No title, description, location, URL, or any other detail from the source event is written.

---

## Delete Guard

`deleteEvent(_:)` in the EventKit layer is the **only** function in the app that calls `EKEventStore.remove(...)`. Before every deletion it asserts:

```swift
guard let notes = event.notes, notes.contains("bee-busy:source=") else {
    log("SAFETY: attempted to delete non-bee-busy event \(event.calendarItemIdentifier) — aborted")
    return
}
```

If the assertion fails, the deletion is aborted and logged. The rest of the reconciliation pass continues. This guard makes it structurally impossible for the app to delete a user's own events even if there is a logic bug upstream.

---

## Calendar Removal Cleanup

When the user unchecks a calendar in Settings, before the engine stops watching it the app runs a targeted sweep: fetch all events in that calendar within the look-forward window, find any with our marker, delete them via the guarded `deleteEvent(_:)`. Only then is the calendar removed from the active set.

---

## Logging

- Log file: `~/Library/Logs/BeeBusy/bee-busy.log`
- Format: `[YYYY-MM-DD HH:MM:SS] [LEVEL] message`
- Rotation: capped at ~5 MB; one previous file kept (`bee-busy.log.1`)
- Levels: `INFO`, `WARN`, `ERROR`
- No `os_log` — single logging path, single file
- Opened via the "View Logs" button in Settings; not shown inline

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| EventKit access denied | Amber/red tray indicator, one-time alert with link to System Settings. Idle until access granted. |
| Write fails for a single event | Log at ERROR, skip that event, continue the pass. Retry on next notification. |
| Delete guard fires | Log at ERROR, abort that deletion, continue. No user-facing alert. |
| Log file write fails | Silent — do not crash or alert over a logging failure. |

No pop-up alerts for transient failures. Errors surface only in the log file and the tray indicator colour.

---

## GitHub Release Pipeline

**File:** `.github/workflows/release.yml`  
**Trigger:** Push of a `v*.*.*` tag

### Structure (mirrors `nodepoint-solutions/local-code-review` reference)

**Build job** (runs on `macos-latest`):
1. Checkout code
2. Select correct Xcode version
3. `xcodebuild archive` → `xcodebuild -exportArchive` → `.app`
4. Ad-hoc codesign: `codesign --sign - --deep --force BeeBusy.app`
5. For each architecture (`arm64`, `x86_64`): build, codesign, package as DMG via `hdiutil create`
6. Upload `BeeBusy-<version>-arm64.dmg` and `BeeBusy-<version>-x86_64.dmg` as artifacts

**Release job** (runs after build job):
1. Download all artifacts
2. Publish GitHub Release via `softprops/action-gh-release` with auto-generated release notes and both DMGs attached

**Secrets required:** None for ad-hoc signing. Developer ID signing and notarization can be added later by wiring in `APPLE_CERTIFICATE` and `APPLE_NOTARIZATION_*` secrets without restructuring the workflow.

---

## Out of Scope (v1)

- Notarization / Developer ID signing
- Support for macOS older than 26 Tahoe
- Manual "Sync Now" trigger
- Per-calendar-pair configuration (always full mesh)
- Any network functionality
