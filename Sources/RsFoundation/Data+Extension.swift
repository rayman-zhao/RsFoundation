import Foundation

#if os(macOS)
    import CryptoKit
#else
    import Crypto
#endif

extension Data {
    /// Append bytes of an integer to the data.
    ///
    /// - Parameter value: The integer will be appended
    public mutating func append(_ value: Int) {
        Swift.withUnsafeBytes(of: value) { append(contentsOf: $0) }
    }

    /// Append bytes of a C-string to the data.
    ///
    /// The end of the C-string NULL (\0) will be appended.
    ///
    /// - Parameter cString: The C-string will be appended.
    public mutating func append(_ cString: UnsafePointer<CChar>) {
        let length = strlen(cString) + 1  // Include end \0
        cString.withMemoryRebound(to: UInt8.self, capacity: length) {
            append($0, count: length)
        }
    }

    /// A name-based UUID (version 5) generated from the MD5 hash of the data bytes.
    ///
    /// - Complexity: O(*n*), where *n* is the number of bytes in the data.
    public var hashUUID: UUID {
        let hasher = Insecure.MD5.self
        assert(hasher.byteCount >= 16)

        // Set UUID version to 5 (name-based UUID)
        var bytes = [UInt8](hasher.hash(data: self))
        bytes[6] = (bytes[6] & 0x0F) | 0x50  // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // RFC 4122 variant

        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }

    /// A boolean value indicating whether the buffer is JPEG data.
    ///
    /// Detects the SOI magic at the start and an EOI marker searched from the
    /// end, without constraining the first segment marker. Real-world buffers
    /// put the EOI at (or within a few padding bytes of) the end, so the search
    /// completes immediately almost always; bytes trailing after the EOI are
    /// tolerated.
    public var isJPEG: Bool {
        guard count > 4, starts(with: [0xFF, 0xD8, 0xFF]) else { return false }

        var i = count - 2
        while i > 0 {
            if self[i] == 0xFF, self[i + 1] == 0xD9 {
                return true
            }
            i -= 1
        }
        return false
    }

    /// A boolean value indicating whether the buffer is PNG data.
    ///
    /// Detects the 8-byte signature at the start and the IEND chunk at the end;
    /// buffers with trailing bytes after IEND are rejected.
    public var isPNG: Bool {
        count >= 8 + 12
            && starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            && suffix(12).elementsEqual([0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
    }

    /// A boolean value indicating whether the buffer is image data.
    ///
    /// Only JPEG and PNG are recognized currently.
    public var isImage: Bool {
        return isJPEG || isPNG
    }
}
