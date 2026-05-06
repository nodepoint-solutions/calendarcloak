# Auto-Updater Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On each launch, CalendarCloak checks GitHub Releases for a newer semver version and, if found, lets the user install it directly from the tray menu via an automated DMG download/mount/copy/relaunch flow.

**Architecture:** Two new files (`UpdateChecker.swift`, `UpdateInstaller.swift`) handle check and install logic. `AppState` grows a `updateState` enum property that `TrayMenuView` renders inline. `AppCoordinator.bootstrap` fires the check as a detached background task after the engine starts. `#if DEBUG` guards skip the check in local dev builds.

**Tech Stack:** Swift, Foundation (`URLSession`, `Process`, `FileManager`), SwiftUI, XCTest

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `CalendarCloak/Update/UpdateChecker.swift` | Semver parsing/comparison, GitHub API fetch |
| Create | `CalendarCloak/Update/UpdateInstaller.swift` | DMG download, mount, copy, relaunch script |
| Modify | `CalendarCloak/State/AppState.swift` | Add `UpdateState` enum + `updateState` property |
| Modify | `CalendarCloak/AppCoordinator.swift` | Fire check after `engine.start()` |
| Modify | `CalendarCloak/UI/TrayMenuView.swift` | Render update section |
| Create | `CalendarCloakTests/UpdateStateTests.swift` | Enum equality tests |
| Create | `CalendarCloakTests/UpdateCheckerTests.swift` | Semver parse + compare tests |
| Create | `CalendarCloakTests/UpdateInstallerTests.swift` | `parseMountPoint` pure helper test |

---

## Task 1: UpdateState enum + AppState property

**Files:**
- Modify: `CalendarCloak/State/AppState.swift`
- Create: `CalendarCloakTests/UpdateStateTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `CalendarCloakTests/UpdateStateTests.swift`:

```swift
import XCTest
@testable import CalendarCloak

final class UpdateStateTests: XCTestCase {
    func test_idle_equatable() {
        XCTAssertEqual(UpdateState.idle, UpdateState.idle)
    }

    func test_available_equatable_same() {
        let url = URL(string: "https://example.com/update.dmg")!
        XCTAssertEqual(
            UpdateState.available(version: "1.2.3", dmgUrl: url),
            UpdateState.available(version: "1.2.3", dmgUrl: url)
        )
    }

    func test_available_equatable_different_version() {
        let url = URL(string: "https://example.com/update.dmg")!
        XCTAssertNotEqual(
            UpdateState.available(version: "1.2.3", dmgUrl: url),
            UpdateState.available(version: "1.2.4", dmgUrl: url)
        )
    }

    func test_downloading_equatable() {
        XCTAssertEqual(UpdateState.downloading(pct: 0.5), UpdateState.downloading(pct: 0.5))
        XCTAssertNotEqual(UpdateState.downloading(pct: 0.5), UpdateState.downloading(pct: 0.9))
    }

    func test_idle_not_equal_installing() {
        XCTAssertNotEqual(UpdateState.idle, UpdateState.installing)
    }

    func test_restarting_equatable() {
        XCTAssertEqual(UpdateState.restarting, UpdateState.restarting)
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

In Xcode: Product → Test (⌘U). `UpdateStateTests` should fail with "cannot find type 'UpdateState' in scope".

- [ ] **Step 3: Add UpdateState enum and property to AppState**

Open `CalendarCloak/State/AppState.swift`. Replace the entire file with:

```swift
import Foundation
import Observation

enum UpdateState: Equatable {
    case idle
    case available(version: String, dmgUrl: URL)
    case downloading(pct: Double)
    case installing
    case restarting
}

@Observable
final class AppState {
    var lastSyncDate: Date?
    var activeCalendarNames: [String] = []
    var isAccessDenied: Bool = false
    var errorMessage: String?
    var updateState: UpdateState = .idle
}
```

- [ ] **Step 4: Run tests to confirm they pass**

⌘U. `UpdateStateTests` — all 6 tests should pass. Existing tests should still pass.

- [ ] **Step 5: Commit**

```bash
git add CalendarCloak/State/AppState.swift CalendarCloakTests/UpdateStateTests.swift
git commit -m "feat: add UpdateState enum to AppState"
```

---

## Task 2: UpdateChecker — semver helpers + GitHub API fetch

**Files:**
- Create: `CalendarCloak/Update/UpdateChecker.swift`
- Create: `CalendarCloakTests/UpdateCheckerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `CalendarCloakTests/UpdateCheckerTests.swift`:

```swift
import XCTest
@testable import CalendarCloak

final class UpdateCheckerTests: XCTestCase {

    // MARK: parseSemver

    func test_parseSemver_withVPrefix() {
        let r = parseSemver("v1.2.3")
        XCTAssertEqual(r?.0, 1)
        XCTAssertEqual(r?.1, 2)
        XCTAssertEqual(r?.2, 3)
    }

    func test_parseSemver_withoutVPrefix() {
        let r = parseSemver("0.1.0")
        XCTAssertEqual(r?.0, 0)
        XCTAssertEqual(r?.1, 1)
        XCTAssertEqual(r?.2, 0)
    }

    func test_parseSemver_invalidString_returnsNil() {
        XCTAssertNil(parseSemver("not-a-version"))
    }

    func test_parseSemver_twoPartVersion_returnsNil() {
        XCTAssertNil(parseSemver("1.2"))
    }

    func test_parseSemver_emptyString_returnsNil() {
        XCTAssertNil(parseSemver(""))
    }

    // MARK: isNewer

    func test_isNewer_majorBump_returnsTrue() {
        XCTAssertTrue(isNewer((2, 0, 0), than: (1, 9, 9)))
    }

    func test_isNewer_minorBump_returnsTrue() {
        XCTAssertTrue(isNewer((1, 2, 0), than: (1, 1, 9)))
    }

    func test_isNewer_patchBump_returnsTrue() {
        XCTAssertTrue(isNewer((1, 0, 1), than: (1, 0, 0)))
    }

    func test_isNewer_sameVersion_returnsFalse() {
        XCTAssertFalse(isNewer((1, 0, 0), than: (1, 0, 0)))
    }

    func test_isNewer_olderMajor_returnsFalse() {
        XCTAssertFalse(isNewer((0, 9, 9), than: (1, 0, 0)))
    }

    func test_isNewer_olderMinor_returnsFalse() {
        XCTAssertFalse(isNewer((1, 1, 9), than: (1, 2, 0)))
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

⌘U. `UpdateCheckerTests` should fail with "cannot find 'parseSemver' in scope".

- [ ] **Step 3: Create UpdateChecker.swift**

Create `CalendarCloak/Update/UpdateChecker.swift` (add the `Update` group in Xcode first):

```swift
import Foundation

struct UpdateInfo {
    let version: String
    let dmgUrl: URL
}

func parseSemver(_ tag: String) -> (Int, Int, Int)? {
    let s = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    let parts = s.split(separator: ".").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return (parts[0], parts[1], parts[2])
}

func isNewer(_ candidate: (Int, Int, Int), than current: (Int, Int, Int)) -> Bool {
    if candidate.0 != current.0 { return candidate.0 > current.0 }
    if candidate.1 != current.1 { return candidate.1 > current.1 }
    return candidate.2 > current.2
}

func checkForUpdate() async -> UpdateInfo? {
    #if DEBUG
    return nil
    #else
    guard
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        let current = parseSemver(currentVersion)
    else { return nil }

    let url = URL(string: "https://api.github.com/repos/nodepoint-solutions/calendarcloak/releases/latest")!
    var request = URLRequest(url: url)
    request.setValue("CalendarCloak-app", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 10

    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        guard let latest = parseSemver(release.tag_name), isNewer(latest, than: current) else {
            return nil
        }

        #if arch(arm64)
        let archSuffix = "arm64"
        #else
        let archSuffix = "x86_64"
        #endif

        let dmgAsset = release.assets.first { $0.name.contains(archSuffix) && $0.name.hasSuffix(".dmg") }
                    ?? release.assets.first { $0.name.hasSuffix(".dmg") }

        guard let asset = dmgAsset, let dmgUrl = URL(string: asset.browser_download_url) else {
            return nil
        }
        return UpdateInfo(version: release.tag_name, dmgUrl: dmgUrl)
    } catch {
        return nil
    }
    #endif
}

// MARK: - Private

private struct GitHubRelease: Decodable {
    let tag_name: String
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

⌘U. All `UpdateCheckerTests` should pass (11 tests). All existing tests should still pass.

- [ ] **Step 5: Commit**

```bash
git add CalendarCloak/Update/UpdateChecker.swift CalendarCloakTests/UpdateCheckerTests.swift
git commit -m "feat: add UpdateChecker with semver parsing"
```

---

## Task 3: UpdateInstaller — DMG download, mount, copy, relaunch

**Files:**
- Create: `CalendarCloak/Update/UpdateInstaller.swift`
- Create: `CalendarCloakTests/UpdateInstallerTests.swift`

- [ ] **Step 1: Write the failing test for the one testable pure helper**

Create `CalendarCloakTests/UpdateInstallerTests.swift`:

```swift
import XCTest
@testable import CalendarCloak

final class UpdateInstallerTests: XCTestCase {
    func test_parseMountPoint_findsVolumeLine() {
        let output = "/dev/disk4s1\tApple_HFS\t/Volumes/CalendarCloak 1.2.3\n"
        XCTAssertEqual(parseMountPoint(from: output), "/Volumes/CalendarCloak 1.2.3")
    }

    func test_parseMountPoint_multipleLines_returnsFirst() {
        let output = "/dev/disk4s1\tApple_partition_scheme\t\n/dev/disk4s2\tApple_HFS\t/Volumes/MyApp\n"
        XCTAssertEqual(parseMountPoint(from: output), "/Volumes/MyApp")
    }

    func test_parseMountPoint_noVolumeLine_returnsNil() {
        XCTAssertNil(parseMountPoint(from: "/dev/disk4s1\tApple_HFS\t/tmp/notvolumes\n"))
    }

    func test_parseMountPoint_emptyOutput_returnsNil() {
        XCTAssertNil(parseMountPoint(from: ""))
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

⌘U. `UpdateInstallerTests` should fail with "cannot find 'parseMountPoint' in scope".

- [ ] **Step 3: Create UpdateInstaller.swift**

Create `CalendarCloak/Update/UpdateInstaller.swift`:

```swift
import Foundation
import AppKit

enum UpdateError: Error {
    case downloadFailed
    case mountFailed(String)
    case noAppBundle
    case processFailure(String, Int32, String)
}

func installUpdate(dmgUrl: URL, onProgress: @escaping (UpdateState) async -> Void) async throws {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cc-update-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let dmgPath = tmpDir.appendingPathComponent("update.dmg")

    // 1. Download
    await onProgress(.downloading(pct: 0))
    try await streamDownload(from: dmgUrl, to: dmgPath) { pct in
        await onProgress(.downloading(pct: pct))
    }

    await onProgress(.installing)

    // 2. Mount
    let attachOutput = try runProcess("/usr/bin/hdiutil",
        arguments: ["attach", "-nobrowse", "-quiet", "-noverify", dmgPath.path])
    guard let mountPoint = parseMountPoint(from: attachOutput) else {
        throw UpdateError.mountFailed(attachOutput)
    }

    defer {
        try? runProcess("/usr/bin/hdiutil", arguments: ["detach", mountPoint, "-quiet"])
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // 3. Find .app in DMG
    let contents = try FileManager.default.contentsOfDirectory(atPath: mountPoint)
    guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
        throw UpdateError.noAppBundle
    }
    let srcApp = mountPoint + "/" + appName

    // 4. Copy to staging
    let stagingApp = "/Applications/CalendarCloak (update).app"
    if FileManager.default.fileExists(atPath: stagingApp) {
        try runProcess("/bin/rm", arguments: ["-rf", stagingApp])
    }
    try runProcess("/bin/cp", arguments: ["-R", srcApp, stagingApp])

    // 5. Strip quarantine
    try runProcess("/usr/bin/xattr", arguments: ["-cr", stagingApp])

    // 6. Write relaunch script
    await onProgress(.restarting)
    let currentApp = Bundle.main.bundleURL.path
    let scriptPath = tmpDir.appendingPathComponent("relaunch.sh").path
    let script = """
    #!/bin/bash
    sleep 2
    mv "\(currentApp)" "\(currentApp).bak" 2>/dev/null
    mv "\(stagingApp)" "\(currentApp)"
    xattr -cr "\(currentApp)" 2>/dev/null
    open "\(currentApp)"
    rm -rf "\(currentApp).bak" 2>/dev/null
    rm -f "$0"
    """
    try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

    // 7. Spawn detached script, quit
    let launcher = Process()
    launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
    launcher.arguments = [scriptPath]
    launcher.standardOutput = FileHandle.nullDevice
    launcher.standardError = FileHandle.nullDevice
    try launcher.run()
    // Do NOT waitUntilExit — this process must outlive us

    await MainActor.run { NSApplication.shared.terminate(nil) }
}

// MARK: - Internal helpers (internal for testability)

func parseMountPoint(from output: String) -> String? {
    for line in output.components(separatedBy: "\n") {
        let parts = line.components(separatedBy: "\t")
        if let mountPt = parts.last?.trimmingCharacters(in: .whitespaces),
           mountPt.hasPrefix("/Volumes/") {
            return mountPt
        }
    }
    return nil
}

@discardableResult
func runProcess(_ executable: String, arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
        throw UpdateError.processFailure(executable, process.terminationStatus, output)
    }
    return output
}

// MARK: - Private

private func streamDownload(
    from url: URL,
    to destination: URL,
    onProgress: (Double) async -> Void
) async throws {
    var request = URLRequest(url: url)
    request.setValue("CalendarCloak-app", forHTTPHeaderField: "User-Agent")

    let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
    let total = (response as? HTTPURLResponse)
        .flatMap { $0.value(forHTTPHeaderField: "Content-Length") }
        .flatMap(Int64.init) ?? -1

    FileManager.default.createFile(atPath: destination.path, contents: nil)
    let handle = try FileHandle(forWritingTo: destination)
    defer { try? handle.close() }

    var buffer = Data(capacity: 65_536)
    var received: Int64 = 0

    for try await byte in asyncBytes {
        buffer.append(byte)
        received += 1
        if buffer.count >= 65_536 {
            handle.write(buffer)
            buffer.removeAll(keepingCapacity: true)
            if total > 0 {
                await onProgress(Double(received) / Double(total))
            }
        }
    }
    if !buffer.isEmpty {
        handle.write(buffer)
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

⌘U. All `UpdateInstallerTests` should pass (4 tests). All prior tests still pass.

- [ ] **Step 5: Commit**

```bash
git add CalendarCloak/Update/UpdateInstaller.swift CalendarCloakTests/UpdateInstallerTests.swift
git commit -m "feat: add UpdateInstaller with DMG download, mount, and relaunch"
```

---

## Task 4: AppCoordinator — fire check after engine starts

**Files:**
- Modify: `CalendarCloak/AppCoordinator.swift:16-27`

The `bootstrap` method's happy-path currently calls `engine.start()` then falls through. Add the detached check immediately after.

- [ ] **Step 1: Add detached update check after engine.start()**

In `AppCoordinator.swift`, find the block:

```swift
if settings.hasCompletedSetup && settings.selectedCalendarIDs.count >= 2 {
    engine.start()
} else {
```

Replace it with:

```swift
if settings.hasCompletedSetup && settings.selectedCalendarIDs.count >= 2 {
    engine.start()
    Task.detached(priority: .background) {
        if let info = await checkForUpdate() {
            await MainActor.run {
                state.updateState = .available(version: info.version, dmgUrl: info.dmgUrl)
            }
        }
    }
} else {
```

- [ ] **Step 2: Build to confirm it compiles**

Product → Build (⌘B). No errors expected.

- [ ] **Step 3: Run tests**

⌘U. All existing tests still pass (the new detached task returns nil in `#if DEBUG`).

- [ ] **Step 4: Commit**

```bash
git add CalendarCloak/AppCoordinator.swift
git commit -m "feat: fire update check after engine starts"
```

---

## Task 5: TrayMenuView — inline update section

**Files:**
- Modify: `CalendarCloak/UI/TrayMenuView.swift`

- [ ] **Step 1: Add updateSection computed property and wire it into body**

Replace `CalendarCloak/UI/TrayMenuView.swift` with:

```swift
import SwiftUI

struct TrayMenuView: View {
    @Environment(\.openSettings) private var openSettings
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusSection
            if state.updateState != .idle {
                Divider()
                updateSection
            }
            Divider()
            Button("Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    @ViewBuilder
    private var updateSection: some View {
        switch state.updateState {
        case .idle:
            EmptyView()
        case let .available(version, dmgUrl):
            Button("Update to \(version)") {
                Task.detached {
                    do {
                        try await installUpdate(dmgUrl: dmgUrl) { newState in
                            await MainActor.run { state.updateState = newState }
                        }
                    } catch {
                        await MainActor.run {
                            state.updateState = .available(version: version, dmgUrl: dmgUrl)
                        }
                    }
                }
            }
        case let .downloading(pct):
            updateStatusText("Downloading… \(Int(pct * 100))%")
        case .installing:
            updateStatusText("Installing…")
        case .restarting:
            updateStatusText("Restarting…")
        }
    }

    private func updateStatusText(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private var lastSyncLabel: String {
        guard let date = state.lastSyncDate else { return "Last sync: Never" }
        return "Last sync: \(Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date()))"
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**

⌘B. No errors expected.

- [ ] **Step 3: Run tests**

⌘U. All tests still pass.

- [ ] **Step 4: Smoke-test the update section manually**

In `AppCoordinator.swift`, temporarily override the detached task to force an `.available` state (revert after):

```swift
// Temporary smoke-test override — revert before commit
Task.detached(priority: .background) {
    await MainActor.run {
        state.updateState = .available(
            version: "v99.0.0",
            dmgUrl: URL(string: "https://example.com/fake.dmg")!
        )
    }
}
```

Run the app (⌘R). Open the tray — you should see "Update to v99.0.0" above Settings. Revert the override.

- [ ] **Step 5: Revert the smoke-test override, commit**

```bash
git add CalendarCloak/UI/TrayMenuView.swift
git commit -m "feat: show inline update section in tray menu"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| `UpdateChecker.swift` — `checkForUpdate() async -> UpdateInfo?` | Task 2 |
| `#if DEBUG` returns nil | Task 2 |
| Hits GitHub releases API for `nodepoint-solutions/calendarcloak` | Task 2 |
| Semver parse + compare | Task 2 |
| Reads `CFBundleShortVersionString` | Task 2 |
| Prefers arch-specific DMG | Task 2 |
| `UpdateInstaller.swift` — `installUpdate(dmgUrl:onProgress:)` | Task 3 |
| Stream download with progress | Task 3 |
| `hdiutil attach` | Task 3 |
| Copy to staging | Task 3 |
| `xattr -cr` strip quarantine | Task 3 |
| Detached relaunch shell script | Task 3 |
| `NSApplication.terminate` | Task 3 |
| `AppState.updateState: UpdateState` | Task 1 |
| `UpdateState` enum cases | Task 1 |
| `AppCoordinator` fires check after `engine.start()` | Task 4 |
| Tray shows update button / progress / status | Task 5 |
| Errors reset to `.available` for retry | Task 5 |

No gaps found.

**Placeholder scan:** No TBDs, no "implement later", no vague steps. All code blocks are complete.

**Type consistency:**
- `UpdateInfo(version: String, dmgUrl: URL)` — defined Task 2, consumed Task 4 ✓
- `UpdateState` cases — defined Task 1, used Task 3 (`onProgress`) and Task 5 (switch) ✓
- `parseSemver` / `isNewer` — defined Task 2, tested Task 2 ✓
- `parseMountPoint` / `runProcess` — defined Task 3, `parseMountPoint` tested Task 3 ✓
- `installUpdate(dmgUrl:onProgress:)` — defined Task 3, called Task 5 ✓
- `checkForUpdate()` — defined Task 2, called Task 4 ✓
