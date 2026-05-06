import XCTest
@testable import CalendarCloak

@MainActor
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
