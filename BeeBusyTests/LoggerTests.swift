import XCTest
@testable import BeeBusy

final class LoggerTests: XCTestCase {
    var tempDir: URL!
    var logFile: URL!
    var logger: Logger!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        logFile = tempDir.appendingPathComponent("test.log")
        logger = Logger(fileURL: logFile)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_info_writesLineToFile() throws {
        logger.info("hello world")
        logger.syncFlush()
        let contents = try String(contentsOf: logFile)
        XCTAssertTrue(contents.contains("[INFO] hello world"))
    }

    func test_error_writesLineToFile() throws {
        logger.error("something broke")
        logger.syncFlush()
        let contents = try String(contentsOf: logFile)
        XCTAssertTrue(contents.contains("[ERROR] something broke"))
    }

    func test_multipleEntries_appendedInOrder() throws {
        logger.info("first")
        logger.info("second")
        logger.syncFlush()
        let contents = try String(contentsOf: logFile)
        let firstRange = contents.range(of: "first")!
        let secondRange = contents.range(of: "second")!
        XCTAssertLessThan(firstRange.lowerBound, secondRange.lowerBound)
    }

    func test_logFileWrite_doesNotThrowOnFailure() {
        let badURL = URL(fileURLWithPath: "/nonexistent/path/test.log")
        let badLogger = Logger(fileURL: badURL)
        badLogger.info("this should not crash")
        badLogger.syncFlush()
    }

    func test_rotation_triggeredWhenFileSizeExceeded() throws {
        // Each log line is ~90 bytes ([timestamp] [INFO] + 60 x's + newline).
        // maxFileSizeBytes must be < 90 so the check before the second write sees the first line
        // and triggers rotation (the check runs before writing, not after).
        let smallLogger = Logger(fileURL: logFile, maxFileSizeBytes: 80)
        let longLine = String(repeating: "x", count: 60)
        smallLogger.info(longLine)
        smallLogger.info(longLine)  // should trigger rotation
        smallLogger.syncFlush()
        let backup = logFile.deletingPathExtension().appendingPathExtension("log.1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
    }
}
