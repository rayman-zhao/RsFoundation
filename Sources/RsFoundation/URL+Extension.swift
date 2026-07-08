import Foundation
#if os(Windows)
import WinSDK

fileprivate func getVSFixedFileInfo(_ filename: String) -> String? {
    guard let block = getFileVersionInfo(filename) else { return nil }
    guard let value = verQueryValue(block, "\\") else { return nil }

    guard value.count >= MemoryLayout<VS_FIXEDFILEINFO>.size else { return nil }
    return value.withUnsafeBytes { rawBuffer in
        let fixedInfo = rawBuffer.load(as: VS_FIXEDFILEINFO.self)
        let major = Int((fixedInfo.dwFileVersionMS >> 16) & 0xffff)
        let minor = Int(fixedInfo.dwFileVersionMS & 0xffff)
        let build = Int((fixedInfo.dwFileVersionLS >> 16) & 0xffff)
        let revision = Int(fixedInfo.dwFileVersionLS & 0xffff)

        return "\(major).\(minor).\(build).\(revision)"
    }
}

fileprivate func verQueryValue(_ block: [UInt8], _ subBlock: String) -> [UInt8]? {
     var buffer: UnsafeMutableRawPointer? = nil
     var len: UINT = 0

     let ok = VerQueryValueW(block, subBlock.wideString, &buffer, &len)
     
     guard ok, let buffer else { return nil }
     return [UInt8](UnsafeRawBufferPointer(start: buffer, count: Int(len)))
}

fileprivate func getFileVersionInfo(_ filename: String) -> [UInt8]? {
    let size = getFileVersionInfoSize(filename)
    guard size > 0 else { return nil }

    var data = [UInt8](repeating: 0, count: Int(size))
    let ok = data.withUnsafeMutableBytes { rawBuffer in
        GetFileVersionInfoW(filename.wideString, 0, DWORD(size), rawBuffer.baseAddress)
    }

    guard ok else { return nil }
    return data
}

fileprivate func getFileVersionInfoSize(_ filename: String) -> Int {
    return Int(GetFileVersionInfoSizeW(filename.wideString, nil))
}

public extension URL {
    /// Stadard directory as macOS.
    static var applicationSupportDirectory: URL {
         guard let appSupportDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Can't find applicationSupportDirectory with FileManager")
        }
        
        return appSupportDir
    }

    /// Version info of EXE/DLL files.
    var version: String? {
        return getVSFixedFileInfo(self.path)
    }
}
#endif

public extension URL {
    /// The size of the file URL. -1 when failed to obtain.
    var fileSize: Int {
        let rv = try? resourceValues(forKeys: [.fileSizeKey])
        return rv?.fileSize ?? -1
    }

    /// The file path of the URL.
    /// 
    /// On Windows, the deprecated URL.path has not sufix "/" for directories, and URL.path() has unnecessary prefix "/".
    var filePath: String {
        var p = self.path(percentEncoded: false)

        #if os(Windows)
            if p.hasPrefix("/") {
                p.removeFirst()
            }
        #endif

        return p
    }

    /// Simplified reachability check.
    var reachable: Bool {
        return (try? checkResourceIsReachable()) ?? false
    }
    
    /// Get the URL of a child file in a directory
    /// 
    /// The URL self should be a directory.
    /// 
    /// - Parameter child: The file name of the child file in the directory.
    /// - Returns: Child URL, or nil if can't find it in the directory.
    func reachableChild(named child: String) -> URL? {
        guard self.hasDirectoryPath else { return nil }

        let url = self.appending(component: child)
        return url.reachable ? url : nil
    }

    /// Get the URL of a child in subfolders of a directory.
    /// 
    /// - Parameter child: The path to the child like f1/f2/child.ext
    /// - Returns: Child URL, or nil if can't make it in the directory.
    func reachingChild(named child: String) -> URL? {
        guard self.hasDirectoryPath else { return nil }

        let url = self.appending(path: child)
        let dir = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        if !dir.reachable {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                return nil
            }
        }

        return url
    }
    
    /// Get the URL of a sibling file in same directory
    /// 
    /// - Parameter sibling: The file name of sibling file in the same directory.
    /// - Returns: Sibling URL, or nil if can't find it in the same directory.
    func reachableSibling(named sibling: String) -> URL? {
        guard self.hasDirectoryPath == false else { return nil }
        
        let url = self.deletingLastPathComponent().appending(component: sibling)
        return url.reachable ? url : nil
    }
}
