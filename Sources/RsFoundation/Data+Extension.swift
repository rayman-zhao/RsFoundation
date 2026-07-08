import Foundation
#if os(macOS)
import CryptoKit
#else
import Crypto
#endif

public extension Data {
    /// Append bytes of an integer to the data.
    /// 
    /// - Parameter value: The integer will be appended
    mutating func append(_ value: Int) {
        append(Swift.withUnsafeBytes(of: value) { Data($0) })
    }
    
    /// Append bytes of a C-string to the data.
    /// 
    /// The end of the C-string NULL (\0) will be appended.
    /// 
    /// - Parameter cString: The C-string will be appended.
    mutating func append(_ cString: UnsafePointer<CChar>) {
        let length = strlen(cString) + 1 // Include end \0
        cString.withMemoryRebound(to: UInt8.self, capacity: length) {
            append($0, count: length)
        }
    }

    /// UUID type hash value of data bytes.
    var hashUUID: UUID {
        let hasher = Insecure.MD5.self
        assert(hasher.byteCount >= 16)
        
        // 设置 UUID 版本为 5（基于名称的 UUID）
        var bytes = [UInt8](hasher.hash(data: self))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // 版本 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 变体
        
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// A boolean value indicating whether the buffer is JPEG data.
    var isJPEG: Bool {
        let cnt = self.count
        return cnt > 6
            && self[0] == 0xFF && self[1] == 0xD8 && self[2] == 0xFF
            && (self[3] == 0xE0 || self[3] == 0xE1 || self[3] == 0xDB)
            && self[cnt - 2] == 0xFF && self.last == 0xD9

    }

    /// A boolean value indicating whether the buffer is any kind of image data.
    var isImage: Bool {
        return isJPEG
    }
}