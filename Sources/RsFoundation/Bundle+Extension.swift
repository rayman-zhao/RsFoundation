import Foundation

public extension Bundle {
    /// Get full path of a resource file.
    /// 
    /// When bundle resource files in SPM like:
    /// 
    /// resources: [
    /// .copy("Resources/"),
    /// ],
    /// 
    /// SPM and XCode will have different bundle structure on macOS and Windows. This function simplified condition check.
    /// 
    /// - Parameter fileName: A resource file name, like "test.txt"
    /// - Returns: Full file path
    func path(forResource fileName: String) -> String? {
        let url = URL(filePath: fileName)
        let ext = url.pathExtension
        let name = url.deletingPathExtension().lastPathComponent

        return self.path(forResource: name, ofType: ext) ?? // For SPM
               self.path(forResource: name, ofType: ext, inDirectory: "Resources") // For XCode
    }
}
