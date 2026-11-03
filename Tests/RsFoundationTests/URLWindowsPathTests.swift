import Foundation
import RsFoundation
import Testing

/// `windowsPath` 的形态契约：反斜杠分隔、非盘根无尾分隔符。
/// folders 列表等 shell 形态存储依赖裸串比较，正斜杠/尾缀差异会破坏去重。
@Suite("URL windowsPath Tests")
struct URLWindowsPathTests {

    @Test("directory keeps no trailing separator")
    func testDirectory() {
        let url = URL(filePath: "D:/slides/MDSX", directoryHint: .isDirectory)
        #expect(url.filePath == "D:/slides/MDSX/")
        #expect(url.windowsPath == "D:\\slides\\MDSX")
    }

    @Test("drive root keeps its trailing separator")
    func testDriveRoot() {
        let url = URL(filePath: "z:/", directoryHint: .isDirectory)
        #expect(url.windowsPath == "z:\\")
    }

    @Test("file path is separator-swapped only")
    func testFile() {
        let url = URL(filePath: "D:\\slides\\a.svs")
        #expect(url.windowsPath == "D:\\slides\\a.svs")
    }

    @Test("UNC share root loses the trailing separator")
    func testUNCRoot() {
        let url = URL(filePath: #"\\med-dev\transfer\zhaoyu"#, directoryHint: .isDirectory)
        #expect(url.windowsPath == #"\\med-dev\transfer\zhaoyu"#)
    }
}
