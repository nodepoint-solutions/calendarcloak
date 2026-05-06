# Auto-Updater Design

**Date:** 2026-05-06
**Scope:** CalendarCloak macOS app — launch-time update check with automated DMG install

---

## Overview

On each launch, CalendarCloak checks the GitHub Releases API for a newer semver version. If one exists, the tray menu shows an inline "Update to vX.Y.Z" button. Clicking it downloads the DMG, mounts it, copies the `.app` to a staging path, strips quarantine, and spawns a detached relaunch script before quitting. No separate window; no background polling.

---

## Architecture

Two new source files, three modified files.

### New: `CalendarCloak/Update/UpdateChecker.swift`

Single async function:

```swift
func checkForUpdate() async -> UpdateInfo?
```

- In `#if DEBUG` builds: returns `nil` immediately — local dev is never affected.
- Fetches `https://api.github.com/repos/nodepoint-solutions/calendarcloak/releases/latest` via `URLSession`.
- Parses `tag_name` as `vMAJOR.MINOR.PATCH` (with optional `v` prefix).
- Reads current version from `Bundle.main.infoDictionary["CFBundleShortVersionString"]` (stamped from `MARKETING_VERSION` in `project.pbxproj` at build time).
- Returns `UpdateInfo(version: String, dmgUrl: URL)` if the release is strictly newer, `nil` otherwise.
- All errors (network failure, unexpected JSON, unparseable semver) are swallowed — the function returns `nil`.

```swift
struct UpdateInfo {
    let version: String
    let dmgUrl: URL
}
```

DMG asset selection: prefer an asset whose name contains the current `process` arch suffix (e.g. `arm64`), fall back to any `.dmg` asset.

### New: `CalendarCloak/Update/UpdateInstaller.swift`

Single async throwing function:

```swift
func installUpdate(dmgUrl: URL, onProgress: @MainActor (UpdateState) -> Void) async throws
```

Stages (mirrors local-code-review's installer):

1. **Download** — stream DMG to a temp directory via `URLSession` with a delegate tracking `didReceive data` bytes vs `countOfBytesExpectedToReceive`. Reports `.downloading(pct:)` progress.
2. **Mount** — `hdiutil attach -nobrowse -quiet -noverify <dmgPath>`. Parse `/Volumes/...` mount point from stdout.
3. **Find `.app`** — `FileManager` scan of mount point for a `.app` entry.
4. **Copy to staging** — `cp -R <src> "/Applications/CalendarCloak (update).app"`, removing any prior staging copy first.
5. **Strip quarantine** — `xattr -cr "/Applications/CalendarCloak (update).app"`.
6. **Detach DMG** — `hdiutil detach <mountPoint> -quiet` (in `defer`, always runs).
7. **Relaunch script** — write a `bash` script to a temp path that: sleeps 2s, `mv` current `.app` to `.bak`, `mv` staging into place, `xattr -cr` final path, `open` it, removes `.bak`, removes itself. `chmod +x` and spawn detached.
8. **Quit** — `NSApplication.shared.terminate(nil)`.

Shell-out uses `Process` (Swift's `Foundation` wrapper for `posix_spawn`), not `shell()`. Each stage reports progress via `onProgress` before starting.

On any thrown error, the caller resets `updateState` to `.available(...)` so the user can retry.

### Modified: `AppState.swift`

Adds one property:

```swift
var updateState: UpdateState = .idle
```

```swift
enum UpdateState: Equatable {
    case idle
    case available(version: String, dmgUrl: URL)
    case downloading(pct: Double)
    case installing
    case restarting
}
```

`AppState` is `@Observable`, so `TrayMenuView` reacts automatically.

### Modified: `AppCoordinator.swift`

After `engine.start()` succeeds, fires a detached task:

```swift
Task.detached(priority: .background) {
    if let info = await checkForUpdate() {
        await MainActor.run { state.updateState = .available(version: info.version, dmgUrl: info.dmgUrl) }
    }
}
```

No retry, no periodic re-check. A new launch re-checks.

### Modified: `TrayMenuView.swift`

New section rendered above the Settings divider when `state.updateState != .idle`:

- `.available(version, dmgUrl)` → `Button("Update to \(version)")` that fires `installUpdate` in a `Task`.
- `.downloading(pct)` → `Text("Downloading… \(Int(pct * 100))%")` (non-interactive).
- `.installing` → `Text("Installing…")`.
- `.restarting` → `Text("Restarting…")`.

On install error, the `Task` catches and resets `state.updateState = .available(...)`.

---

## Version Stamping

`MARKETING_VERSION` in `CalendarCloak.xcodeproj/project.pbxproj` is the source of truth. Xcode injects it into `Info.plist` as `CFBundleShortVersionString` at build time.

Release workflow:
1. Bump `MARKETING_VERSION` in Xcode.
2. Archive and export a DMG.
3. Tag `vX.Y.Z` on GitHub and attach the DMG as a release asset.

Running apps on an older version will see the update on next launch.

---

## Error Handling

| Stage | Failure behaviour |
|---|---|
| `checkForUpdate` (any error) | Returns `nil` silently — tray unchanged |
| Download failure | Throws → caller resets to `.available`, user can retry |
| Mount failure | Throws → same |
| No `.app` in DMG | Throws → same |
| Copy/quarantine failure | Throws → same |
| Relaunch script write failure | Throws → same |

---

## Testing

No new test targets. `UpdateChecker` is a pure async function over a URL — validated manually against the live API. `UpdateInstaller` shells out to system tools (`hdiutil`, `cp`, `xattr`, `bash`) making unit testing impractical; it follows the same untested-boundary pattern as `EventKitStore`.

---

## Out of Scope

- Periodic background checking (launch-time only)
- Progress window (tray inline only)
- Rollback on failed relaunch
- Signature/checksum verification of downloaded DMG
