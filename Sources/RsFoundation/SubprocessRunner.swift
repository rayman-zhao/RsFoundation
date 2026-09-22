import AsyncAlgorithms
import Foundation
import Subprocess
import SystemPackage

private let newLineAndQuotes: CharacterSet = {
    var characterSet = CharacterSet()  // CharacterSet.whitespacesAndNewlines
    characterSet.insert(charactersIn: "\"")
    characterSet.insert(charactersIn: "\r")
    characterSet.insert(charactersIn: "\n")

    return characterSet
}()

#if os(Windows)
// Windows treats ":" as a location separator (drive letter), so it disqualifies
// a bare name just like "/" and "\" do.
private let pathSeparators: Set<Character> = ["/", "\\", ":"]
#else
private let pathSeparators: Set<Character> = ["/"]
#endif

public class SubprocessRunner {
    var procPath: String!
    var procTask: Task<Void, any Error>!

    public init() {
    }

    public func start(
        executable: String, arguments: [String], workingDirectory: String,
        outputHandler: @escaping @Sendable (String) -> Void = { (_) in }
    ) {
        log.info("Starting \(executable)")
        log.info("with \(arguments.joined(separator: " "))")
        log.info("in \(workingDirectory)")

        procPath = executable
        procTask = Task {
            _ = try await run(
                executable.contains(where: pathSeparators.contains)
                    ? .path(FilePath(executable)) : .name(executable),
                arguments: Arguments(arguments),
                workingDirectory: workingDirectory.isEmpty ? nil : FilePath(workingDirectory),
                input: .none,
                output: .sequence,
                error: .sequence
            ) { execution in
                for try await message in merge(
                    execution.standardOutput.strings(),
                    execution.standardError.strings()
                ) {
                    outputHandler(message.trimmingCharacters(in: newLineAndQuotes))
                }
            }
        }
    }

    public func stop() {
        if let procPath, let procTask {
            log.info("Stopping \(procPath)")

            Task {
                procTask.cancel()
                try? await procTask.value
                log.info("Stopped \(procPath)")
            }
        }
    }
}
