import AsyncAlgorithms
import Foundation
import Subprocess
import SystemPackage

private let newLineAndQuotes: CharacterSet = {
    var characterSet = CharacterSet()  //CharacterSet.whitespacesAndNewlines
    characterSet.insert(charactersIn: "\"")
    characterSet.insert(charactersIn: "\r")
    characterSet.insert(charactersIn: "\n")

    return characterSet
}()

public class SubprocessRunner {
    var procPath: String!
    var procTask: Task<Void, any Error>!

    public init() {
    }

    public func start(executable: String, arguments: [String], workingDirectory: String, outputHandler: @escaping @Sendable (String) -> Void = { (_) in }) {
        log.info("Starting \(executable)")
        log.info("with \(arguments.joined(separator: " "))")
        log.info("in \(workingDirectory)")

        procPath = executable
        procTask = Task {
            _ = try await run(
                .name(executable),
                arguments: Arguments(arguments),
                workingDirectory: workingDirectory.isEmpty ? nil : FilePath(workingDirectory),
                preferredBufferSize: 1
            ) { exec, input, stdout, stderr in
                for try await message in merge(stdout.lines(), stderr.lines()) {
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
