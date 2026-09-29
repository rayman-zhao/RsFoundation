import Foundation

#if os(Windows)
    import WinSDK

    /// Reads a date/time picture configured in the user's regional settings.
    private func windowsDatePicture(_ lcType: LCTYPE) -> String? {
        // LOCALE_NAME_USER_DEFAULT maps to nil in Swift.
        let size = GetLocaleInfoEx(nil, DWORD(lcType), nil, 0)
        guard size > 0 else { return nil }
        var buffer = [WCHAR](repeating: 0, count: Int(size))
        let result = GetLocaleInfoEx(nil, DWORD(lcType), &buffer, size)
        guard result > 0 else { return nil }
        return String(decodingCString: buffer, as: UTF16.self)
    }

    /// Converts a Windows date/time picture (e.g. "yyyy/M/d") into an ICU pattern.
    /// The two largely agree, apart from:
    ///   Windows: dddd/ddd (weekday full/abbreviated), tt (AM/PM)
    ///   ICU:     EEEE/EEE (weekday full/abbreviated), a  (AM/PM)
    /// The plain replacements ignore quoted literals, which the system
    /// short-date/time pictures never contain in practice.
    private func convertWindowsPictureToICU(_ winPicture: String) -> String {
        var result = winPicture
        result = result.replacingOccurrences(of: "dddd", with: "EEEE")
        result = result.replacingOccurrences(of: "ddd", with: "EEE")
        result = result.replacingOccurrences(of: "tt", with: "a")
        return result
    }
#endif

extension DateFormatter {
    /// Creates a formatter whose format follows the date/time pictures
    /// configured in the operating system's regional settings.
    ///
    /// Foundation's own `dateStyle`/`timeStyle` resolve to ICU's canned
    /// patterns for the locale identifier and ignore the per-locale format
    /// customizations configured in Windows, so on Windows they do not match
    /// what other native apps show. This initializer reads the configured
    /// pictures via `GetLocaleInfoEx` instead, and falls back to `.short`
    /// styles when those queries fail.
    ///
    /// - Parameters:
    ///   - systemDate: The formatted string contains a date part.
    ///   - systemTime: The formatted string contains a time part.
    ///   - systemTimeWithSeconds: The time part includes seconds.
    public convenience init(
        systemDate: Bool, systemTime: Bool, systemTimeWithSeconds: Bool = false
    ) {
        self.init()

        #if os(Windows)
            // Keep the literal pattern; the locale would rewrite it otherwise.
            locale = Locale(identifier: "en_US_POSIX")

            var parts: [String] = []
            if systemDate, let picture = windowsDatePicture(LCTYPE(LOCALE_SSHORTDATE)) {
                parts.append(convertWindowsPictureToICU(picture))
            }
            if systemTime {
                let lcType = LCTYPE(
                    systemTimeWithSeconds ? LOCALE_STIMEFORMAT : LOCALE_SSHORTTIME)
                if let picture = windowsDatePicture(lcType) {
                    parts.append(convertWindowsPictureToICU(picture))
                }
            }

            if parts.isEmpty {
                dateStyle = .short
            } else {
                dateFormat = parts.joined(separator: " ")
            }
        #else
            // Foundation on Darwin already tracks the system locale.
            dateStyle = systemDate ? .short : .none
            timeStyle = systemTime ? (systemTimeWithSeconds ? .medium : .short) : .none
        #endif
    }
}
