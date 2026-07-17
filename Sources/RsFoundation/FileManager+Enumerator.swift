import Foundation

private final class WindowsDirectoryEnumerator: FileManager.DirectoryEnumerator {
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

    override var fileAttributes: [FileAttributeKey: Any]? {
        return baseEnumerator.fileAttributes
    }

    override var directoryAttributes: [FileAttributeKey: Any]? {
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
extension FileManager {
    /// Returns an improved directory enumerator.
    ///
    /// On Windows, `enumerator.skipDescendants()` causes abnormal file traversal interruption,
    /// not only skipping the subdirectories of the current directory but also incorrectly
    /// affecting subsequent sibling directory traversal.
    ///
    /// This method returns a fixed enumerator that works correctly on Windows.
    ///
    /// - Parameters: Same as `FileManager.enumerator(at:includingPropertiesForKeys:options:errorHandler:)`.
    /// - Returns: Same as `FileManager.enumerator(at:includingPropertiesForKeys:options:errorHandler:)`.
    public func enumerator2(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]? = nil,
        options mask: FileManager.DirectoryEnumerationOptions = [],
        errorHandler handler: ((URL, any Error) -> Bool)? = nil
    ) -> DirectoryEnumerator? {
        guard
            let baseEnumerator = self.enumerator(
                at: url,
                includingPropertiesForKeys: keys,
                options: mask,
                errorHandler: handler
            )
        else {
            return nil
        }

        #if os(Windows)
            return WindowsDirectoryEnumerator(wrapping: baseEnumerator)
        #else
            return baseEnumerator
        #endif
    }
}
