# Cleanup Feature Design

**Date:** 2026-05-06  
**Status:** Approved

## Overview

Add a "Delete All Busy Events" button to the Settings screen that removes every bee-busy-managed event across all calendars. The operation is protected by the existing safety guard in `EventKitStore.delete(_:)`, which aborts on any event that does not carry a `bee-busy:source=` notes marker.

## Architecture

Changes are confined to two existing files:

- `BeeBusy/Sync/SyncEngine.swift` — new `deleteAllBusyEvents()` method
- `BeeBusy/UI/SettingsView.swift` — new button + confirmation dialog

## SyncEngine — `deleteAllBusyEvents()`

Fetches all calendars from `store.fetchCalendars()` (all writable calendars, not just the currently selected ones), fetches events across the look-forward window using those calendar IDs, filters by `BusyEventMarker.isBusyEvent(_:)`, then calls `store.delete(_:)` on each matching event. Logs count before and after.

The `store.delete(_:)` safety guard (line 83–86 of `EventKitStore.swift`) independently verifies each event carries a `bee-busy:source=` marker before removing it, so source events can never be deleted even in the presence of a bug.

## SettingsView — Button and Confirmation

A `"Delete All Busy Events"` button is added to the existing "General" `Section`, styled with `.foregroundStyle(.red)` to signal destructiveness. A `@State var showingCleanupConfirmation: Bool = false` drives a `.confirmationDialog` with:

- Title: `"Delete All Busy Events?"`
- Message: `"This will remove all Busy events from all calendars. This cannot be undone."`
- Destructive action: `"Delete"` → calls `engine.deleteAllBusyEvents()`
- Cancel action: `"Cancel"`

## What This Does NOT Do

- Does not stop or restart the sync engine (a reconciliation will recreate events on the next sync cycle if the engine is still running and calendars are still configured — that is expected behaviour).
- Does not touch source events under any circumstances.
- Does not modify `settings.selectedCalendarIDs`.
