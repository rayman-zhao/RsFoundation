import Foundation

#if os(Windows)
    import WinSDK

    extension TimeZone {
        /// The time zone the OS is actually configured to (including DST state).
        ///
        /// Foundation's `TimeZone.current` always resolves to GMT on Windows —
        /// swift-foundation cannot read the system zone database (only POSIX
        /// offset `TZ` strings work, region names like `Asia/Shanghai` don't),
        /// and GUI processes have no `TZ` set anyway. This reads the Windows
        /// bias directly instead.
        public static var systemCurrent: TimeZone {
            var info = TIME_ZONE_INFORMATION()
            switch GetTimeZoneInformation(&info) {
            case DWORD(TIME_ZONE_ID_DAYLIGHT):
                // Windows: local = UTC − Bias − DaylightBias, minutes
                return TimeZone(secondsFromGMT: -Int(info.Bias + info.DaylightBias) * 60)!
            default:
                // STANDARD shares the same math; UNKNOWN falls back to raw Bias
                return TimeZone(secondsFromGMT: -Int(info.Bias + info.StandardBias) * 60)!
            }
        }
    }
#endif
