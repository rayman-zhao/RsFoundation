import Foundation
import Logging
import Synchronization

// MARK: - Global Logger

private let logLabel = "swiftworks"

/// The call stack of the first access to the global ``log``, captured once by
/// the logger's initializer and read by
/// ``FileLogging/bootstrap(directory:prefix:keepDays:level:)`` to name the
/// culprit when the ordering contract was violated. Symbol quality is
/// platform-dependent — Swift's DWARF-in-PE is not resolved by
/// `Thread.callStackSymbols`, so Windows stacks read as bare frames; the
/// debug-time failure message therefore also points at the initializer, the
/// stable spot to breakpoint and re-run.
let logFirstUse = Mutex<String?>(nil)

/// The global logger for the application.
///
/// A single, directly-referenced instance. It materializes lazily on first
/// use, with the level from ``LoggingPolicy`` and whatever backend
/// `LoggingSystem` was bootstrapped with — so a ``FileLogging`` bootstrap that
/// runs before any logging is picked up here automatically. The property is a
/// constant: level policy is this library's standardization job, not a
/// per-call-site decision.
public let log: Logger = {
    logFirstUse.withLock { $0 = Thread.callStackSymbols.prefix(8).joined(separator: "\n") }
    var log = Logger(label: logLabel)
    log.logLevel = LoggingPolicy.effectiveLevel
    return log
}()

// MARK: - Level Policy

/// Chooses the global logger's level for the current environment.
enum LoggingPolicy {

    private static let override = Mutex<Logger.Level?>(nil)

    /// Returns the default level for a process, so that test processes log
    /// everything, debug builds log informational records, and release builds
    /// log only warnings and above.
    ///
    /// - Parameter processName: The name of the process to classify. Defaults
    ///   to the current process; injectable so tests can cover every branch.
    static func defaultLevel(processName: String = ProcessInfo.processInfo.processName) -> Logger.Level {
        switch processName {
        case "xctest", "swift-testing":
            return .trace
        default:
            #if DEBUG
                return .info
            #else
                return .warning
            #endif
        }
    }

    /// The level the global logger uses: the level passed to
    /// ``FileLogging/bootstrap(directory:prefix:keepDays:level:)`` when it
    /// has run, otherwise the environment default.
    static var effectiveLevel: Logger.Level {
        override.withLock { $0 } ?? defaultLevel()
    }

    static func setLevelOverride(_ level: Logger.Level?) {
        override.withLock { $0 = level }
    }
}

// MARK: - File Log Handler

/// A `LogHandler` that appends one line per record to a per-day log file,
/// rotating to a new file at midnight in `TimeZone.current` — which some
/// Windows setups without a detectable zone report as GMT.
///
/// The file is `<fileNamePrefix>-yyyy-MM-dd.log` inside `directory`, created
/// lazily on the first write. Each record is a single line:
/// `<ISO-8601 timestamp> <level padded to 8> <label>: [source] <message> {metadata}`,
/// with CR/LF inside the message escaped to literals so tooling can rely on
/// one record per line. Metadata composes as in ``StreamLogHandler`` —
/// handler, then ``metadataProvider``, then per-event metadata, with an
/// associated error rendered as `error.message`/`error.type`. The handler is
/// safe to share across threads; a failed open drops records silently and
/// retries on the next day rollover.
struct FileLogHandler: LogHandler {
    private struct State {
        var handle: FileHandle?
        var timestampFormatter: ISO8601DateFormatter
        var dayFormatter: DateFormatter
        var dayStamp: String
        var openFailed = false
    }

    /// The shared, lock-guarded state. A final class because the noncopyable
    /// `Mutex` cannot be stored inside a value-semantic struct; every copy of
    /// the handler appends through the same sink. The formatters live in the
    /// state because `DateFormatter` and `ISO8601DateFormatter` are not
    /// sendable.
    private final class Sink: @unchecked Sendable {
        let state: Mutex<State>

        init(openingOn date: Date) {
            let dayFormatter = DateFormatter()
            dayFormatter.locale = Locale(identifier: "en_US_POSIX")
            dayFormatter.dateFormat = "yyyy-MM-dd"

            let timestampFormatter = ISO8601DateFormatter()
            timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestampFormatter.timeZone = .current

            state = Mutex(State(
                handle: nil,
                timestampFormatter: timestampFormatter,
                dayFormatter: dayFormatter,
                dayStamp: dayFormatter.string(from: date)
            ))
        }
    }

    private let sink: Sink
    private let now: @Sendable () -> Date

    let directory: URL
    let fileNamePrefix: String
    let label: String

    var logLevel: Logger.Level = .info
    var metadata: Logger.Metadata = [:]
    var metadataProvider: Logger.MetadataProvider?

    /// Creates a handler writing into `directory`, naming files after
    /// `fileNamePrefix` and the local calendar day.
    ///
    /// - Parameters:
    ///   - label: The swift-log label to include in every record.
    ///   - directory: The directory to create per-day log files in.
    ///   - fileNamePrefix: The file name without the `-yyyy-MM-dd.log` suffix.
    ///   - now: The clock to consult; injectable so tests can cross midnight.
    init(
        label: String,
        directory: URL,
        fileNamePrefix: String,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.label = label
        self.directory = directory
        self.fileNamePrefix = fileNamePrefix
        self.now = now
        self.sink = Sink(openingOn: now())
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        let effectiveMetadata = Self.composedMetadata(
            base: metadata, provider: metadataProvider, event: event)

        let date = now()
        let source = event.source
        sink.state.withLock { state in
            let dayStamp = state.dayFormatter.string(from: date)
            if dayStamp != state.dayStamp {
                try? state.handle?.close()
                state.handle = nil
                state.dayStamp = dayStamp
                state.openFailed = false
            }
            guard !state.openFailed else { return }
            if state.handle == nil {
                do {
                    state.handle = try Self.openLogFile(
                        in: directory, fileNamePrefix: fileNamePrefix, dayStamp: dayStamp)
                } catch {
                    state.openFailed = true
                    return
                }
            }

            let levelName = event.level.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)
            var text = "\(state.timestampFormatter.string(from: date)) \(levelName) \(label): [\(source)] \(event.message.singleLine)"
            if let effectiveMetadata, !effectiveMetadata.isEmpty {
                text += " {" + Self.renderedMetadata(effectiveMetadata) + "}"
            }
            text += "\n"

            try? state.handle?.write(contentsOf: Data(text.utf8))
        }
    }

    /// Lays handler metadata, provider metadata, event metadata, and the
    /// event's error on top of each other, in increasing precedence. Returns
    /// nil when nothing contributed so records stay free of an empty `{}`.
    private static func composedMetadata(
        base: Logger.Metadata,
        provider: Logger.MetadataProvider?,
        event: LogEvent
    ) -> Logger.Metadata? {
        let provided = provider?.get() ?? [:]
        guard !provided.isEmpty || !(event.metadata?.isEmpty ?? true) || event.error != nil else {
            return nil
        }

        var composed = base
        if !provided.isEmpty {
            composed.merge(provided, uniquingKeysWith: { _, provided in provided })
        }
        if let eventMetadata = event.metadata, !eventMetadata.isEmpty {
            composed.merge(eventMetadata, uniquingKeysWith: { _, event in event })
        }
        if let error = event.error {
            composed["error.message"] = "\(error)"
            composed["error.type"] = "\(String(reflecting: type(of: error)))"
        }
        return composed
    }

    private static func openLogFile(in directory: URL, fileNamePrefix: String, dayStamp: String) throws -> FileHandle {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(component: logFileName(prefix: fileNamePrefix, dayStamp: dayStamp))
        if !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            _ = FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
        }
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        return handle
    }

    private static func renderedMetadata(_ metadata: Logger.Metadata) -> String {
        metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")
    }

    /// Deletes dated log files of `fileNamePrefix` that have not been modified
    /// within `days` days; `days` less than 1 disables pruning.
    static func prune(fileNamePrefix: String, in directory: URL, olderThanDays days: Int) {
        guard days >= 1 else { return }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys))
        else { return }

        let cutoff = Date(timeIntervalSinceNow: -Double(days) * 86_400)
        for child in children
        where isDatedLogFile(child.lastPathComponent, prefix: fileNamePrefix) {
            let modified = (try? child.resourceValues(forKeys: keys))?.contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: child)
            }
        }
    }

    private static func isDatedLogFile(_ name: String, prefix: String) -> Bool {
        let date: Substring
        if prefix.isEmpty {
            guard name.hasSuffix(".log") else { return false }
            date = name.dropLast(".log".count)
        } else {
            guard name.hasPrefix("\(prefix)-"), name.hasSuffix(".log") else { return false }
            date = name.dropFirst(prefix.count + 1).dropLast(".log".count)
        }
        return date.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil
    }

    private static func logFileName(prefix: String, dayStamp: String) -> String {
        prefix.isEmpty ? "\(dayStamp).log" : "\(prefix)-\(dayStamp).log"
    }
}

private extension Logger.Message {
    /// The rendered message with CR/LF escaped to literals, keeping every log
    /// record on a single line.
    var singleLine: String {
        description
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

// MARK: - Setup

/// Entry point for installing the application's file logging backend.
public enum FileLogging {

    /// Guards `LoggingSystem.bootstrap`, which may be called only once per
    /// process.
    private static let isInstalled = Mutex(false)

    /// Installs a daily-rotating file backend for the global ``log``, keeping
    /// the stderr backend alongside it.
    ///
    /// Call this once, at the very beginning of application startup and before
    /// any other code touches ``log`` — the global logger materializes lazily
    /// against the backend this call installs. The ordering contract is
    /// enforced, not assumed: a debug build fails fast when any log call
    /// preceded bootstrap, and a release build records an error, leaves the
    /// global logger on stderr, and still gives loggers created from then on
    /// the file backend. Repeated calls log a warning and do nothing.
    ///
    /// Records go to `<prefix>-yyyy-MM-dd.log` (`yyyy-MM-dd.log` with the
    /// default empty prefix) in `directory`, rotating at midnight in
    /// `TimeZone.current`. Files not modified within `keepDays` days are
    /// deleted during this call.
    ///
    /// The app decides where logs live: unpackaged apps usually pass
    /// ``defaultDirectory(group:product:)``, MSIX-packaged apps their
    /// package's writable LocalState folder. When the directory cannot be
    /// created the process stays on stderr-only logging.
    ///
    /// - Parameters:
    ///   - directory: Where log files are created.
    ///   - prefix: The log file name prefix; the directory usually already
    ///     identifies the app, so the default is empty.
    ///   - keepDays: How many days of log files to keep. Less than 1 keeps
    ///     everything.
    ///   - level: The level for the global logger once installed. Defaults to
    ///     ``LoggingPolicy/defaultLevel()``.
    public static func bootstrap(
        directory: URL,
        prefix: String = "",
        keepDays: Int = 7,
        level: Logger.Level? = nil
    ) {
        let wasInstalled = isInstalled.withLock { (installed: inout Bool) -> Bool in
            let previous = installed
            installed = true
            return previous
        }
        guard !wasInstalled else {
            log.warning("FileLogging.bootstrap may only be called once; ignoring the repeated call.")
            return
        }

        // Ordering contract: a bootstrap that runs after the global log was
        // first used would split output between stderr and the file — a
        // client programming error. Surface it loudly instead of absorbing it,
        // naming where the first use came from.
        if let firstUse = logFirstUse.withLock({ $0 }) {
            let message = "FileLogging.bootstrap must run before any code touches the global log "
                + "(earlier records are stderr-only and the global logger stays on stderr). "
                + "First use came from:\n\(firstUse)\n"
                + "To catch it in the debugger, break at the start of the `log` initializer "
                + "in Logging+Extension.swift and re-run."
            #if DEBUG
                fatalError(message)
            #else
                log.error("\(message); loggers created from now on use the file backend")
            #endif
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            log.error(
                "FileLogging cannot create the log directory at \(directory.path(percentEncoded: false)), staying on stderr only: \(error)")
            return
        }

        FileLogHandler.prune(fileNamePrefix: prefix, in: directory, olderThanDays: keepDays)

        let configuredLevel = level ?? LoggingPolicy.defaultLevel()
        LoggingPolicy.setLevelOverride(configuredLevel)
        LoggingSystem.bootstrap { label in
            var handlers: [LogHandler] = [StreamLogHandler.standardError(label: label)]
            handlers.append(FileLogHandler(
                label: label, directory: directory, fileNamePrefix: prefix))
            var multiplex = MultiplexLogHandler(handlers)
            multiplex.logLevel = configuredLevel
            return multiplex
        }
    }

    /// Returns the default per-user log directory for `product`, namespaced
    /// by `group` the way ``JSONPreferences/makeStandard(group:product:name:)``
    /// namespaces its preference files. On Windows the root is the same
    /// ``URL/applicationSupportDirectory`` the preference files live under
    /// (`%LOCALAPPDATA%\<group>\<product>\Logs`); on macOS it is the
    /// platform's dedicated logs folder (`~/Library/Logs/<group>/<product>`).
    public static func defaultDirectory(group: String, product: String) -> URL {
        #if os(macOS)
            let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appending(component: "Library", directoryHint: .isDirectory)
            return library
                .appending(component: "Logs", directoryHint: .isDirectory)
                .appending(component: group, directoryHint: .isDirectory)
                .appending(component: product, directoryHint: .isDirectory)
        #else
            URL.applicationSupportDirectory
                .appending(component: group, directoryHint: .isDirectory)
                .appending(component: product, directoryHint: .isDirectory)
                .appending(component: "Logs", directoryHint: .isDirectory)
        #endif
    }
}
