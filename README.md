# RsFoundation
Enhancement of Swift Foundation

## Logging

The global `log` (swift-log) is always available and writes to stderr. Install
the file backend once, at the very beginning of app startup and before any
other code touches `log` — the global logger materializes lazily against the
installed backend. This ordering is enforced: a debug build fails fast when a
log call preceded bootstrap; a release build records an error and leaves the
global logger on stderr:

```swift
import RsFoundation

FileLogging.bootstrap(
    directory: FileLogging.defaultDirectory(group: "SwiftWorks", product: "Ruslan"))
log.info("started")   // stderr + <directory>/2026-10-19.log
```

`directory` is required — the app decides where logs live. Unpackaged apps
usually pass ``defaultDirectory(group:product:)``; MSIX-packaged apps pass
their package's writable LocalState folder:

```swift
FileLogging.bootstrap(directory: localStateLogsURL)
```

Records are single lines — `<ISO-8601 timestamp> <level> <label>: [source] <message> {metadata}` —
appended to a per-day file named `<prefix>-yyyy-MM-dd.log`, rotating at
midnight, with files unmodified for `keepDays` days (default 7, `0` keeps
everything) pruned during bootstrap. The `prefix` defaults to empty — the
directory usually already identifies the app — giving bare `yyyy-MM-dd.log`
files. Level policy is standardized by the library (`.trace` in tests,
`.info` in debug builds, `.warning` in release); `bootstrap(level:)` is the
one override point, and `log` itself is read-only for consumers.
