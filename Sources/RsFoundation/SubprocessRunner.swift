import Foundation
import Subprocess
import AsyncAlgorithms
import SystemPackage

let newLineAndQuotes: CharacterSet = {
    var characterSet = CharacterSet() //CharacterSet.whitespacesAndNewlines
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

    public func start(exe: String, args: [String], pwd: String, outputHandler: @escaping @Sendable (String) -> Void = { (_) in }) {
        log.info("Starting \(exe)")
        log.info("with \(args.joined(separator: " "))")
        log.info("in \(pwd)")

        procPath = exe
        procTask = Task {    
            _ = try await run(
                .name(exe),
                arguments: Arguments(args),
                workingDirectory: pwd.isEmpty ? nil : FilePath(pwd),
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
