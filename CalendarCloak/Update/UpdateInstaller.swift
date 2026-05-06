import Foundation
import AppKit

enum UpdateError: Error {
    case downloadFailed
    case mountFailed(String)
    case noAppBundle
    case processFailure(String, Int32, String)
}

func installUpdate(dmgURL: URL, onProgress: @escaping (UpdateState) async -> Void) async throws {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cc-update-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let dmgPath = tmpDir.appendingPathComponent("update.dmg")

    // 1. Download
    await onProgress(.downloading(pct: 0))
    try await streamDownload(from: dmgURL, to: dmgPath) { pct in
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
