import Foundation
import RsFoundation
import Testing

@Suite("Data Network Path Tests")
struct DataNetworkPathTests {

    /// `Data.write` 到 Windows 网络路径（UNC `\\med-dev\transfer\zhaoyu` 与映射盘 `z:/`）。
    ///
    /// 非原子写入（默认）在两种路径上均应成功。`.atomic` 依赖
    /// `SetFileInformationByHandle(FileRenameInfoEx)` 改名，而 SMB 重定向器不支持该调用
    /// （返回 Win32 87）；swift-foundation 在 6.4 之前收到 87 不会回退到 `MoveFileExW`。
    /// 因此在 Swift 6.3.x 工具链上，本测试会对两个网络目标的 atomic 写入记录失败，
    /// 升级到 6.4 及以后应全部通过。
    @Test("Data writes to network paths")
    func testWriteToNetworkPaths() {
        let data = Data("RsFoundation network path test".utf8)
        let fileName = "rsf_net_\(UUID().uuidString).txt"

        let targets: [(label: String, dir: URL)] = [
            ("UNC \\\\med-dev\\transfer\\zhaoyu", URL(filePath: #"\\med-dev\transfer\zhaoyu"#, directoryHint: .isDirectory)),
            ("mapped drive z:/", URL(filePath: "z:/", directoryHint: .isDirectory)),
        ]

        for target in targets {
            guard target.dir.isDirectory else {
                print("Skipping \(target.label): not reachable")
                continue
            }

            let url = target.dir.appending(component: fileName)

            do {
                try data.write(to: url)
                #expect((try? Data(contentsOf: url)) == data, "\(target.label): plain write should succeed")
            } catch {
                Issue.record("\(target.label): plain write failed: \(error)")
            }
            try? FileManager.default.removeItem(at: url)

            do {
                try data.write(to: url, options: .atomic)
                #expect((try? Data(contentsOf: url)) == data, "\(target.label): atomic write should succeed")
            } catch {
                Issue.record("\(target.label): atomic write failed: \(error)")
            }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
