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

    /// `availableChild` 在 Windows 网络路径(UNC 与映射盘)上应正常编号,且返回 URL 的
    /// `filePath` 保留 `\\server\share` 前缀、能 round-trip 回网络文件夹。
    @Test("availableChild on network paths")
    func testAvailableChildOnNetworkPaths() {
        let targets: [(label: String, dir: URL)] = [
            ("UNC \\\\med-dev\\transfer\\zhaoyu", URL(filePath: #"\\med-dev\transfer\zhaoyu"#, directoryHint: .isDirectory)),
            ("mapped drive z:/", URL(filePath: "z:/", directoryHint: .isDirectory)),
        ]

        for target in targets {
            guard target.dir.isDirectory else {
                print("Skipping \(target.label): not reachable")
                continue
            }

            let dir = target.dir.appending(
                component: "rsf_avail_\(UUID().uuidString)", directoryHint: .isDirectory)
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                Issue.record("\(target.label): failed to create scratch directory: \(error)")
                continue
            }
            defer { try? FileManager.default.removeItem(at: dir) }

            for name in ["report.txt", "report 2.txt"] {
                try? Data().write(to: dir.appending(component: name))
            }

            guard let child = dir.availableChild(baseNamed: "report.txt") else {
                Issue.record("\(target.label): availableChild returned nil")
                continue
            }
            #expect(child.lastPathComponent == "report 3.txt", "\(target.label)")
            #expect(child.filePath.hasPrefix(dir.filePath), "\(target.label): \(child.filePath)")

            try? Data().write(to: child)
            #expect(URL(filePath: child.filePath).reachable, "\(target.label): filePath should round-trip to the network folder")
        }
    }
}
