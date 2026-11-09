import Foundation

#if os(Windows)
    import Synchronization
    import WinSDK

    /// A parsed .xcstrings string catalog, decoded once and shared across threads.
    private struct StringCatalog: Sendable, Codable {
        var strings: [String: Entry]

        struct Entry: Codable { var localizations: [String: Localization]? }
        struct Localization: Codable { var stringUnit: StringUnit? }
        struct StringUnit: Codable { var value: String }
    }

    extension String {
        static nonisolated(unsafe) private let interpolationParameters = /\d+\$\(\w+\)/
        static private let localizations = Mutex<[String: StringCatalog]>([:])

        public init(
            localized keyAndValue: String,
            table: String? = nil,
            bundle: Bundle = Bundle.main,
            locale: Locale = .current,
            comment: String? = nil
        ) {
            self = keyAndValue

            let table = table ?? "Localizable"
            guard let path = bundle.path(forResource: "\(table).xcstrings") else {
                log.info("Failed to find string catalog \(table) in \(bundle.bundleURL.path)")
                return
            }

            let catalog: StringCatalog? = String.localizations.withLock { cache in
                if let catalog = cache[path] { return catalog }
                guard
                    let fileData = try? Data(contentsOf: URL(filePath: path)),
                    let catalog = try? JSONDecoder().decode(StringCatalog.self, from: fileData)
                else {
                    log.info("Failed to load string catalog \(path)")
                    return nil
                }
                cache[path] = catalog
                log.info("Cached \(path)")
                return catalog
            }

            // A load failure was already logged; keep the key as the value.
            guard let catalog else { return }

            guard
                let value = catalog.strings[keyAndValue]?
                    .localizations?[locale.identifier]?.stringUnit?.value
            else {
                log.info("Failed to find \(keyAndValue) of \(locale.identifier)")
                return
            }

            self = value.replacing(String.interpolationParameters, with: "")  // Ignore parameter, use format instead.
        }

        public init(utf16: [UInt16]) {
            let cnt = utf16.last == 0 ? utf16.count - 1 : utf16.count
            // Not String(bytes:encoding:.utf16): without a BOM it assumes
            // big-endian (the Unicode default), silently misreading the
            // little-endian wide-char data Windows APIs produce. Verified on
            // Swift 6.4.2 / Windows: returns swapped garbage, not nil.
            self = String(utf16CodeUnits: utf16, count: cnt)
        }

        /// Creates a string from a null-terminated wide-character string, as
        /// received across the Win32 C ABI. Returns nil for a null pointer.
        public init?(cWideString: UnsafePointer<CWideChar>?) {
            guard let cWideString else { return nil }
            var length = 0
            while cWideString[length] != 0 { length += 1 }
            self = String(utf16CodeUnits: cWideString, count: length)
        }

        public init(utf16Data: Data) {
            self = utf16Data.withUnsafeBytes { buf in
                let utf16 = Array(buf.bindMemory(to: UInt16.self))
                return String(utf16: utf16)
            }
        }

        public init(oemCString: UnsafeRawBufferPointer) {
            let length = MultiByteToWideChar(
                UINT(CP_OEMCP),
                0,
                oemCString.baseAddress,
                Int32(oemCString.count),
                nil,
                Int32(0)
            )

            guard length > 0 else {
                self = ""
                return
            }
            var utf16 = [UInt16](repeating: 0, count: Int(length))

            MultiByteToWideChar(
                UINT(CP_OEMCP),
                0,
                oemCString.baseAddress,
                Int32(oemCString.count),
                &utf16,
                Int32(utf16.count)
            )

            self = String(utf16: utf16)
        }

        public var wideString: [WCHAR] {
            self.utf16 + [0]
        }

        public var oemCString: [CChar] {
            let utf16 = self.wideString
            let utf16Count = Int32(utf16.count)

            let length = WideCharToMultiByte(
                UINT(CP_OEMCP),
                0,
                utf16,
                utf16Count,
                nil,
                0,
                nil,
                nil
            )

            guard length > 0 else { return [CChar](repeating: 0, count: 1) }
            var bytes = [CChar](repeating: 0, count: Int(length))

            WideCharToMultiByte(
                UINT(CP_OEMCP),
                0,
                utf16,
                utf16Count,
                &bytes,
                length,
                nil,
                nil
            )

            return bytes
        }
    }

#endif

extension String {
    /// XML 特殊字符转义（写入XML文本节点/属性值）
    public func xmlEscaped() -> String {
        let entities: [Substring: String] = [
            "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&apos;",
        ]
        return replacing(/[&<>'"]/) { entities[$0.output] ?? String($0.output) }
    }

    /// XML 反转义
    ///
    /// 单遍替换：`&amp;lt;` 反转义为字面 `&lt;`，而不会先解出 `&` 再被 `&lt;` 规则二次命中。
    public func xmlUnescaped() -> String {
        let entities: [Substring: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        ]
        return replacing(/&(amp|lt|gt|quot|apos);/) { entities[$0.output.1] ?? String($0.output.0) }
    }
}
