import Foundation

fileprivate final class WindowsDirectoryEnumerator: FileManager.DirectoryEnumerator {
    private let baseEnumerator: FileManager.DirectoryEnumerator
    private var skipPaths: Set<String> = []
    private var lastReturnedURL: URL?
    
    fileprivate init(wrapping enumerator: FileManager.DirectoryEnumerator) {
        self.baseEnumerator = enumerator
        super.init()
    }
    
    override func nextObject() -> Any? {
        while let file = baseEnumerator.nextObject() as? URL {
            let filePath = file.path
            
            let shouldSkip = skipPaths.contains { skipPath in
                filePath.hasPrefix(skipPath + "/") || filePath == skipPath
            }
            
            if shouldSkip {
                continue
            }
            
            lastReturnedURL = file
            return file
        }
        return nil
    }

    override var fileAttributes: [FileAttributeKey : Any]? {
        return baseEnumerator.fileAttributes
    }

    override var directoryAttributes: [FileAttributeKey : Any]? {
        return baseEnumerator.directoryAttributes
    }

    override var level: Int {
        return baseEnumerator.level
    }

    override func skipDescendants() {
        if let url = lastReturnedURL {
            skipPaths.insert(url.path)
        }
    }
}

public extension FileManager {
    /// 返回改进的目录枚举器。
    /// 
    /// 在 Windows 平台上，enumerator.skipDescendants() 方法会导致文件遍历异常中断，不仅跳过当前目录的子内容，
    /// 还错误地影响后续同级目录的遍历。
    /// 
    /// 本方法返回改进的枚举器，可在Windows平台上正常使用。
    /// 
    /// - Parameters: 与enumerator相同。
    /// - Returns: 与enumerator相同。
    func enumerator2(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]? = nil,
        options mask: FileManager.DirectoryEnumerationOptions = [],
        errorHandler handler: ((URL, any Error) -> Bool)? = nil
    ) -> DirectoryEnumerator? {
        // 使用系统的 FileManager 创建枚举器
        guard let baseEnumerator = self.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask,
            errorHandler: handler
        ) else {
            return nil
        }
        
    #if os(Windows)
        // Windows 平台返回修复版本
        return WindowsDirectoryEnumerator(wrapping: baseEnumerator)
    #else
        // 其他平台返回原始实现
        return baseEnumerator
    #endif
    }
}
