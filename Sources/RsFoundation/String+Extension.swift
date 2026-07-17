import Foundation

#if os(Windows)
    import WinSDK

    extension String {
        static private let lock = NSLock()
        static nonisolated(unsafe) private let interpolationParameters = /\d+\$\(\w+\)/
        static nonisolated(unsafe) private var localizations: [String: [String: Any]] = [:]

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

            String.lock.lock()
            defer { String.lock.unlock() }

            if !String.localizations.keys.contains(path) {
                guard let fileData = try? Data(contentsOf: URL(filePath: path)) else {
                    log.info("Failed to read localization data of \(path)")
                    return
                }
                guard let jsonObj = try? JSONSerialization.jsonObject(with: fileData) as? [String: Any] else {
                    log.info("Failed to parse JSON of \(path)")
                    return
                }
                guard let strings = jsonObj["strings"] as? [String: Any] else {
                    log.info("Failed to load strings from \(path)")
                    return
                }
                String.localizations[path] = strings
                log.info("Cached \(path)")
            }

            guard let strings = String.localizations[path],
                let kv = strings[keyAndValue] as? [String: Any],
                let loc = kv["localizations"] as? [String: Any],
                let trans = loc[locale.identifier] as? [String: Any],
                let unit = trans["stringUnit"] as? [String: Any],
                let v = unit["value"] as? String
            else {
                log.info("Failed to find \(keyAndValue) of \(locale.identifier)")
                return
            }

            self = v.replacing(String.interpolationParameters, with: "")  // Ignore parameter, use format instead.
        }

        public init(utf16: [UInt16]) {
            let cnt = utf16.last == 0 ? utf16.count - 1 : utf16.count
            self = String(utf16CodeUnits: utf16, count: cnt)  // Have to do this, since String(encoding:utf16) can't work on Winodws.
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
