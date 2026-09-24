import Foundation
import Testing

@testable import RsFoundation

/// 仅验证启动与正常退出。swift-subprocess 在 Windows 上的 graceful shutdown 会向共享
/// 控制台发送 CTRL_C_EVENT(Subprocess/Teardown.swift 第 2 步),在测试宿主里对 ping 这类
/// 同控制台子进程调用 stop() 会连同 shell 一起杀掉,故 stop() 无法用控制台子进程做单元
/// 测试;Ruslan 实际停止的 javaw.exe 是 GUI 子系统进程,不受该路径影响。
@Test
func testStartStop() async throws {
    let runner = SubprocessRunner()
    runner.start(
        executable: "C:/Windows/System32/ping.exe",
        arguments: ["-n", "3", "127.0.0.1"],
        workingDirectory: ""
    ) {
        print("output: \($0)")
    }

    let result = await runner.procTask?.result
    if case .success = result {
    } else {
        #expect(Bool(false))
    }
}
