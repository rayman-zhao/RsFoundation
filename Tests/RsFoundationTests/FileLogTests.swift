import Foundation
import Logging
import Synchronization
import Testing

@testable import RsFoundation

// FileLogging.bootstrap itself is intentionally not covered here:
// LoggingSystem.bootstrap may run only once per process, and calling it would
// repoint every other suite's `log` at a scratch directory.

// MARK: - Level Policy

@Suite("Logging Policy Tests")
struct LoggingPolicyTests {

    @Test("test processes log everything")
    func testProcessNames() {
        #expect(LoggingPolicy.defaultLevel(processName: "xctest") == .trace)
        #expect(LoggingPolicy.defaultLevel(processName: "swift-testing") == .trace)
    }

    #if DEBUG
        @Test("debug builds default to info")
        func testAppProcess() {
            #expect(LoggingPolicy.defaultLevel(processName: "Ruslan") == .info)
        }
    #else
        @Test("release builds default to warning")
        func testAppProcess() {
            #expect(LoggingPolicy.defaultLevel(processName: "Ruslan") == .warning)
        }
    #endif
}

// MARK: - File Log Handler

private struct BoomError: Error, CustomStringConvertible {
    var description: String { "boom" }
}

@Suite("File Log Handler Tests")
struct FileLogHandlerTests {

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                component: "RsFoundationTest_FileLog_\(UUID().uuidString)",
                directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeHandler(in directory: URL, at date: Date = Date()) -> FileLogHandler {
        let clock = Mutex<Date>(date)
        return FileLogHandler(
            label: "swiftworks", directory: directory, fileNamePrefix: "App",
            now: { clock.withLock { $0 } })
    }

    /// The file name stamp the handler derives from `date`.
    private func stamp(of date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func lines(in directory: URL, fileName: String) throws -> [String] {
        let text = try String(contentsOf: directory.appending(component: fileName), encoding: .utf8)
        return text.split(separator: "\n").map(String.init)
    }

    /// Feeds one event through the handler, bypassing `Logger`'s level check.
    private func emit(
        _ level: Logger.Level,
        _ message: Logger.Message,
        metadata: Logger.Metadata? = nil,
        to handler: FileLogHandler
    ) {
        handler.log(
            event: LogEvent(
                level: level, message: message, metadata: metadata, source: "App",
                file: #fileID, function: #function, line: #line))
    }

    @Test("records carry timestamp, padded level, label, and message")
    func testLineFormat() throws {
        let date = Date()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let handler = makeHandler(in: directory, at: date)
        emit(.warning, "disk is full", to: handler)

        let records = try lines(in: directory, fileName: "App-\(stamp(of: date)).log")
        // Extended delimiters keep the lexer from mistaking this for operators:
        // plain /.../ literals this complex exceed its trial-parse heuristic.
        let timestamp = #/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(Z|[+-]\d{2}:\d{2}) /#
        #expect(records.count == 1)
        #expect(records[0].firstMatch(of: timestamp) != nil)
        #expect(records[0].hasSuffix("warning  swiftworks: [App] disk is full"))
    }

    @Test("level filtering happens before the handler")
    func testLevelFiltering() throws {
        let date = Date()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let handler = makeHandler(in: directory, at: date)
        var logger = Logger(label: "swiftworks", factory: { _ in handler })
        logger.logLevel = .warning

        logger.info("dropped")
        logger.warning("kept")

        let records = try lines(in: directory, fileName: "App-\(stamp(of: date)).log")
        #expect(records.count == 1)
        #expect(records[0].hasSuffix("kept"))
    }

    @Test("metadata renders sorted after the message")
    func testMetadataRendered() throws {
        let date = Date()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var handler = makeHandler(in: directory, at: date)
        handler.metadata = ["pid": "42"]
        emit(.info, "connected", metadata: ["user": "ada"], to: handler)

        let records = try lines(in: directory, fileName: "App-\(stamp(of: date)).log")
        #expect(records.count == 1)
        #expect(records[0].hasSuffix("swiftworks: [App] connected {pid: 42, user: ada}"))
    }

    @Test("line breaks inside messages are escaped")
    func testMultilineEscaped() throws {
        let date = Date()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let handler = makeHandler(in: directory, at: date)
        emit(.info, "line 1\r\nline 2", to: handler)

        let records = try lines(in: directory, fileName: "App-\(stamp(of: date)).log")
        #expect(records.count == 1)
        #expect(records[0].hasSuffix(#"line 1\r\nline 2"#))
    }

    @Test("associated errors render as metadata")
    func testErrorRendered() throws {
        let date = Date()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let handler = makeHandler(in: directory, at: date)
        handler.log(
            event: LogEvent(
                level: .error, message: "request failed", error: BoomError(), metadata: nil,
                source: "App", file: #fileID, function: #function, line: #line))

        let records = try lines(in: directory, fileName: "App-\(stamp(of: date)).log")
        // String(reflecting:) of a private type carries an opaque context on
        // Windows, so only pin down the rendering shape, not the exact name.
        #expect(records.count == 1)
        #expect(records[0].contains("request failed {error.message: boom, error.type: "))
        #expect(records[0].hasSuffix("}"))
    }

    @Test("writing crosses midnight into a new file")
    func testMidnightRollover() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let dayOne = Date(timeIntervalSince1970: 0)
        let clock = Mutex<Date>(dayOne)
        let handler = FileLogHandler(
            label: "swiftworks", directory: directory, fileNamePrefix: "App",
            now: { clock.withLock { $0 } })

        emit(.info, "day one", to: handler)
        clock.withLock { $0 += 86_400 }
        emit(.info, "day two", to: handler)

        let dayTwo = dayOne.addingTimeInterval(86_400)
        let dayOneRecords = try lines(in: directory, fileName: "App-\(stamp(of: dayOne)).log")
        let dayTwoRecords = try lines(in: directory, fileName: "App-\(stamp(of: dayTwo)).log")
        #expect(dayOneRecords.count == 1)
        #expect(dayOneRecords[0].hasSuffix("day one"))
        #expect(dayTwoRecords.count == 1)
        #expect(dayTwoRecords[0].hasSuffix("day two"))
    }

    @Test("prune removes only old dated log files of the prefix")
    func testPrune() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        func touch(_ fileName: String, ageDays: Double) throws {
            let url = directory.appending(component: fileName)
            try Data("x".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: -ageDays * 86_400)],
                ofItemAtPath: url.path(percentEncoded: false))
        }

        func exists(_ fileName: String) -> Bool {
            FileManager.default.fileExists(
                atPath: directory.appending(component: fileName).path(percentEncoded: false))
        }

        let fresh = "App-\(stamp(of: Date())).log"
        try touch("App-2001-01-01.log", ageDays: 30)
        try touch(fresh, ageDays: 0)
        try touch("Other-2001-01-01.log", ageDays: 30)
        try touch("App-notes.txt", ageDays: 30)

        FileLogHandler.prune(fileNamePrefix: "App", in: directory, olderThanDays: 7)

        #expect(!exists("App-2001-01-01.log"))
        #expect(exists(fresh))
        #expect(exists("Other-2001-01-01.log"))
        #expect(exists("App-notes.txt"))

        try touch("App-2002-01-01.log", ageDays: 30)
        FileLogHandler.prune(fileNamePrefix: "App", in: directory, olderThanDays: 0)
        #expect(exists("App-2002-01-01.log"))
    }

    @Test("empty prefix yields bare date file names that still prune")
    func testEmptyPrefix() throws {
        let date = Date()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let handler = FileLogHandler(label: "swiftworks", directory: directory, fileNamePrefix: "")
        emit(.info, "no prefix", to: handler)
        #expect(try lines(in: directory, fileName: "\(stamp(of: date)).log").count == 1)

        func touch(_ fileName: String, ageDays: Double) throws {
            let url = directory.appending(component: fileName)
            try Data("x".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: -ageDays * 86_400)],
                ofItemAtPath: url.path(percentEncoded: false))
        }

        func exists(_ fileName: String) -> Bool {
            FileManager.default.fileExists(
                atPath: directory.appending(component: fileName).path(percentEncoded: false))
        }

        try touch("2001-01-01.log", ageDays: 30)  // bare dated file → deleted
        try touch("App-2001-01-01.log", ageDays: 30)  // another app's prefix → kept

        FileLogHandler.prune(fileNamePrefix: "", in: directory, olderThanDays: 7)

        #expect(!exists("2001-01-01.log"))
        #expect(exists("App-2001-01-01.log"))
    }

    @Test("default directory is group/product scoped")
    func testDefaultDirectory() {
        // directoryHint: .isDirectory leaves a trailing slash on the path.
        let path = FileLogging.defaultDirectory(group: "SwiftWorks", product: "Ruslan")
            .path(percentEncoded: false)
        #if os(macOS)
            #expect(path.hasSuffix("/Logs/SwiftWorks/Ruslan/"))
        #else
            #expect(path.hasSuffix("/SwiftWorks/Ruslan/Logs/"))
        #endif
    }
}

// MARK: - Global Logger

@Suite("Global Logger Tests", .serialized)
struct GlobalLoggerTests {

    @Test("the global log follows the level policy")
    func testLevelFollowsPolicy() {
        #expect(log.logLevel == LoggingPolicy.effectiveLevel)
    }

    @Test("copied loggers are independent and cannot drift the global")
    func testCopyIndependence() {
        var copy = log
        copy.logLevel = .debug

        #expect(log.logLevel == LoggingPolicy.effectiveLevel)
    }

    @Test("first use marks the global log as materialized")
    func testMaterialization() {
        #expect(logMaterialized.withLock { $0 })
    }

    @Test("a bootstrap level override replaces the effective level")
    func testLevelOverride() {
        LoggingPolicy.setLevelOverride(.debug)
        defer { LoggingPolicy.setLevelOverride(nil) }

        #expect(LoggingPolicy.effectiveLevel == .debug)
    }
}
