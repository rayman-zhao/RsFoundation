import Testing
import Foundation
@testable import RsFoundation

@Test
func testStartStop() async throws {
    let runner = SubprocessRunner()
    runner.start(
        exe: "C:/Windows/System32/ping.exe",
        args: ["127.0.0.1", "-t"],
        pwd: "") {
            print("output: \($0)")
        }
    try? await Task.sleep(for: .seconds(3))
    runner.stop()

    let result = await runner.procTask.result
    if case .success = result {
    } else {
        #expect(Bool(false))
    }
}
