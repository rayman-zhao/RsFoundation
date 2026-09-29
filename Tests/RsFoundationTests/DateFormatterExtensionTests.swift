import Foundation
import RsFoundation
import Testing

#if os(Windows)
    import WinSDK

    @Suite("DateFormatter System Extension Tests")
    struct DateFormatterExtensionTests {
        /// A fixed instant, so the compared formatters render the same date.
        private let date = Date(timeIntervalSince1970: 1_760_000_000)

        private func rawPicture(_ lcType: LCTYPE) -> String? {
            let size = GetLocaleInfoEx(nil, DWORD(lcType), nil, 0)
            guard size > 0 else { return nil }
            var buffer = [WCHAR](repeating: 0, count: Int(size))
            guard GetLocaleInfoEx(nil, DWORD(lcType), &buffer, size) > 0 else { return nil }
            return String(decodingCString: buffer, as: UTF16.self)
        }

        /// The documented Windows-picture -> ICU-pattern mapping, as a test
        /// oracle independent of the implementation under test.
        private func toICU(_ winPicture: String) -> String {
            winPicture
                .replacingOccurrences(of: "dddd", with: "EEEE")
                .replacingOccurrences(of: "ddd", with: "EEE")
                .replacingOccurrences(of: "tt", with: "a")
        }

        @Test("date-only format follows the Windows short-date picture")
        func dateOnlyFollowsSystemPicture() throws {
            let picture = try #require(rawPicture(LCTYPE(LOCALE_SSHORTDATE)))
            let formatter = DateFormatter(systemDate: true, systemTime: false)
            #expect(formatter.dateFormat == toICU(picture))
        }

        @Test("short-time format follows the Windows short-time picture")
        func shortTimeFollowsSystemPicture() throws {
            let picture = try #require(rawPicture(LCTYPE(LOCALE_SSHORTTIME)))
            let formatter = DateFormatter(systemDate: false, systemTime: true)
            #expect(formatter.dateFormat == toICU(picture))
        }

        @Test("time with seconds follows the Windows long-time picture")
        func timeWithSecondsFollowsSystemPicture() throws {
            let picture = try #require(rawPicture(LCTYPE(LOCALE_STIMEFORMAT)))
            let formatter = DateFormatter(
                systemDate: false, systemTime: true, systemTimeWithSeconds: true)
            #expect(formatter.dateFormat == toICU(picture))
        }

        @Test("date and time pictures are joined with a space")
        func dateTimeCombinesPictures() throws {
            let datePicture = try #require(rawPicture(LCTYPE(LOCALE_SSHORTDATE)))
            let timePicture = try #require(rawPicture(LCTYPE(LOCALE_SSHORTTIME)))
            let formatter = DateFormatter(systemDate: true, systemTime: true)
            #expect(formatter.dateFormat == toICU(datePicture) + " " + toICU(timePicture))
        }

        @Test("Foundation's own short style does not follow the Windows regional setting")
        func foundationShortStyleDiffersFromSystem() throws {
            let picture = try #require(rawPicture(LCTYPE(LOCALE_SSHORTDATE)))

            let plain = DateFormatter()
            plain.dateStyle = .short
            plain.timeStyle = .none

            let ours = DateFormatter(systemDate: true, systemTime: false)

            // Foundation resolves .short through ICU for its own notion of the
            // locale (observed: Locale.current == en_001 -> "dd/MM/y"), which
            // does not track the format configured in the Windows regional
            // settings (observed: "yyyy/M/d"). For the same instant Foundation
            // renders 09/10/2025 while the system formatter renders 2025/10/9.
            // If this expectation starts failing, corelibs-foundation has
            // begun honoring the OS pictures and the GetLocaleInfoEx
            // workaround can be retired.
            #expect(plain.dateFormat != toICU(picture))
            #expect(ours.dateFormat == toICU(picture))
            #expect(plain.string(from: date) != ours.string(from: date))
        }
    }
#endif
