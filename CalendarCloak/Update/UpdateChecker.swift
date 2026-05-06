import Foundation

struct UpdateInfo {
    let version: String
    let dmgURL: URL
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

    guard let url = URL(string: "https://api.github.com/repos/nodepoint-solutions/calendarcloak/releases/latest") else { return nil }
    var request = URLRequest(url: url)
    request.setValue("CalendarCloak-app", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 10

    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        guard let latest = parseSemver(release.tagName), isNewer(latest, than: current) else {
            return nil
        }

        #if arch(arm64)
        let archSuffix = "arm64"
        #else
        let archSuffix = "x86_64"
        #endif

        let dmgAsset = release.assets.first { $0.name.contains(archSuffix) && $0.name.hasSuffix(".dmg") }
                    ?? release.assets.first { $0.name.hasSuffix(".dmg") }

        guard let asset = dmgAsset, let dmgURL = URL(string: asset.browserDownloadURL) else {
            return nil
        }
        return UpdateInfo(version: release.tagName, dmgURL: dmgURL)
    } catch {
        return nil
    }
    #endif
}

// MARK: - Private

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}
