import XCTest
@testable import CalendarCloak

@MainActor
final class UpdateInstallerTests: XCTestCase {
    func test_parseMountPoint_findsVolumeLine() {
        let output = "/dev/disk4s1\tApple_HFS\t/Volumes/CalendarCloak 1.2.3\n"
        XCTAssertEqual(parseMountPoint(from: output), "/Volumes/CalendarCloak 1.2.3")
    }

    func test_parseMountPoint_skipsNonVolumeLines_returnsFirstMatch() {
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
