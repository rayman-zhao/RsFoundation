import Testing
import Foundation
import RsFoundation

@Suite("FileManager Enumerator2 Tests")
struct FileManagerEnumeratorTests {
    
    @Test("Basic enumeration works with enumerator2")
    func testBasicEnumeration() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RsHelperTest_Basic_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let testFile = tempDir.appendingPathComponent("test.txt")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)
        
        // 使用 enumerator2 方法
        let enumerator = FileManager.default.enumerator2(
            at: tempDir, 
            includingPropertiesForKeys: [.nameKey, .isDirectoryKey]
        )
        #expect(enumerator != nil)
        
        var foundFiles: [URL] = []
        while let file = enumerator?.nextObject() as? URL {
            foundFiles.append(file)
        }
        
        #expect(foundFiles.count > 0)
        let foundNames = foundFiles.map { $0.lastPathComponent }
        #expect(foundNames.contains("test.txt"))
    }
    
    @Test("Skip descendants functionality with enumerator2")
    func testSkipDescendants() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RsHelperTest_Skip_\(UUID().uuidString)")
        let subDir = tempDir.appendingPathComponent("subdir")
        let deepDir = subDir.appendingPathComponent("deep")
        try FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let rootFile = tempDir.appendingPathComponent("root.txt")
        let subFile = subDir.appendingPathComponent("sub.txt")
        let deepFile = deepDir.appendingPathComponent("deep.txt")
        
        try "root content".write(to: rootFile, atomically: true, encoding: .utf8)
        try "sub content".write(to: subFile, atomically: true, encoding: .utf8)
        try "deep content".write(to: deepFile, atomically: true, encoding: .utf8)
        
        let enumerator = FileManager.default.enumerator2(
            at: tempDir, 
            includingPropertiesForKeys: [.nameKey, .isDirectoryKey]
        )
        var foundItems: [URL] = []
        
        while let item = enumerator?.nextObject() as? URL {
            foundItems.append(item)
            if item.lastPathComponent == "subdir" {
                enumerator?.skipDescendants()
            }
        }
        
        let foundNames = foundItems.map { $0.lastPathComponent }
        
        #expect(foundNames.contains("root.txt"))
        #expect(foundNames.contains("subdir"))
        #expect(!foundNames.contains("sub.txt"))
        #expect(!foundNames.contains("deep"))
        #expect(!foundNames.contains("deep.txt"))
    }
    
    @Test("Multiple skip descendants calls with enumerator2")
    func testMultipleSkipDescendants() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RsHelperTest_Multiple_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        for i in 1...3 {
            let subDir = tempDir.appendingPathComponent("dir\(i)")
            try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
            
            let subFile = subDir.appendingPathComponent("file\(i).txt")
            try "content \(i)".write(to: subFile, atomically: true, encoding: .utf8)
        }
        
        let enumerator = FileManager.default.enumerator2(at: tempDir)
        var foundItems: [URL] = []
        
        while let item = enumerator?.nextObject() as? URL {
            foundItems.append(item)
            if item.hasDirectoryPath {
                enumerator?.skipDescendants()
            }
        }
        
        let foundNames = foundItems.map { $0.lastPathComponent }
        
        #expect(foundNames.contains("dir1"))
        #expect(foundNames.contains("dir2"))
        #expect(foundNames.contains("dir3"))
        #expect(!foundNames.contains("file1.txt"))
        #expect(!foundNames.contains("file2.txt"))
        #expect(!foundNames.contains("file3.txt"))
    }
    
    @Test("Empty directory enumeration with enumerator2")
    func testEmptyDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RsHelperTest_Empty_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let enumerator = FileManager.default.enumerator2(at: tempDir, includingPropertiesForKeys: nil)
        #expect(enumerator != nil)
        
        // 空目录应该没有任何项目
        let firstItem = enumerator?.nextObject()
        #expect(firstItem == nil)
    }
    
    @Test("Enumerator2 options are respected") 
    func testEnumeratorOptions() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RsHelperTest_Options_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // 创建一个隐藏文件（以 . 开头）
        let hiddenFile = tempDir.appendingPathComponent(".hidden")
        try "hidden content".write(to: hiddenFile, atomically: true, encoding: .utf8)
        
        let normalFile = tempDir.appendingPathComponent("normal.txt")
        try "normal content".write(to: normalFile, atomically: true, encoding: .utf8)
        
        // 测试跳过隐藏文件的选项
        let enumerator = FileManager.default.enumerator2(
            at: tempDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        
        var foundItems: [URL] = []
        while let item = enumerator?.nextObject() as? URL {
            foundItems.append(item)
        }
        
        let foundNames = foundItems.map { $0.lastPathComponent }
        print("Found files with .skipsHiddenFiles: \(foundNames)")
        
        // 应该包含普通文件
        #expect(foundNames.contains("normal.txt"))
        
        // Windows 和 Unix 对隐藏文件的定义不同，所以放宽测试要求
        #if os(Windows)
        // 在 Windows 上，以 . 开头的文件可能不被认为是隐藏文件
        // 只验证至少找到了普通文件
        #expect(foundNames.count >= 1, "Should find at least the normal file")
        print("Note: Windows may handle dot-files differently than Unix systems")
        #else
        // 在 Unix 系统上，不应该包含以 . 开头的隐藏文件
        #expect(!foundNames.contains(".hidden"), "Should not find dot-files on Unix systems")
        #endif
    }
    
    @Test("Compare enumerator vs enumerator2")
    func testCompareEnumerators() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RsHelperTest_Compare_\(UUID().uuidString)")
        let subDir = tempDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // 创建测试文件
        let rootFile = tempDir.appendingPathComponent("root.txt")
        let subFile = subDir.appendingPathComponent("sub.txt")
        try "root".write(to: rootFile, atomically: true, encoding: .utf8)
        try "sub".write(to: subFile, atomically: true, encoding: .utf8)
        
        // 使用原始 enumerator
        var originalCount = 0
        if let enum1 = FileManager.default.enumerator(
            at: tempDir,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: nil
        ) {
            while enum1.nextObject() != nil { originalCount += 1 }
        }
        
        // 使用 enumerator2
        var enumerator2Count = 0
        if let enum2 = FileManager.default.enumerator2(at: tempDir) {
            while enum2.nextObject() != nil { enumerator2Count += 1 }
        }
        
        print("Original enumerator: \(originalCount) items")
        print("Enumerator2: \(enumerator2Count) items")
        
        // 在没有 skipDescendants 调用的情况下，两者应该返回相同结果
        #expect(originalCount == enumerator2Count, "Both enumerators should find same number of items")
    }
}
