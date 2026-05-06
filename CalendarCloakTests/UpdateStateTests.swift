import XCTest
@testable import CalendarCloak

@MainActor
final class UpdateStateTests: XCTestCase {
    func test_idle_equatable() {
        XCTAssertEqual(UpdateState.idle, UpdateState.idle)
    }

    func test_available_equatable_same() {
        let url = URL(string: "https://example.com/update.dmg")!
        XCTAssertEqual(
            UpdateState.available(version: "1.2.3", dmgURL: url),
            UpdateState.available(version: "1.2.3", dmgURL: url)
        )
    }

    func test_available_equatable_different_version() {
        let url = URL(string: "https://example.com/update.dmg")!
        XCTAssertNotEqual(
            UpdateState.available(version: "1.2.3", dmgURL: url),
            UpdateState.available(version: "1.2.4", dmgURL: url)
        )
    }

    func test_available_equatable_different_url() {
        let url1 = URL(string: "https://example.com/v1.dmg")!
        let url2 = URL(string: "https://example.com/v2.dmg")!
        XCTAssertNotEqual(
            UpdateState.available(version: "1.0.0", dmgURL: url1),
            UpdateState.available(version: "1.0.0", dmgURL: url2)
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
