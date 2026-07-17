import Foundation
import RsFoundation
import Testing

#if os(macOS)
#else
    import FoundationXML
#endif

@Test
func bundle() async throws {
    #expect(Bundle.module.path(forResource: "test.txt") != nil)
    #expect(Bundle.module.path(forResource: "testx.txt") == nil)
}
@Test
func data() async throws {
    var d = Data()
    #expect(d.count == 0)

    d.append(0)
    #expect(d.count == 8)
    #expect(d.hashUUID == UUID(uuidString: "7DEA362B-3FAC-5E00-956A-4952A3D4F474"))

    d.append("Hello World".cString(using: .utf8)!)
    #expect(d.count == 8 + 12)
    #expect(d.last == 0)
}
@Test(arguments: [
    ("lena.jpg", true),
    ("lena.png", false),
    ("test.txt", false),
])
func dataTypes(_ fn: String, _ img: Bool) async throws {
    let url = URL(filePath: try #require(Bundle.module.path(forResource: fn)))
    let d = try Data(contentsOf: url)
    #expect(d.isImage == img)
}
@Test
func logger() async throws {
    log.error("Hello World")
}

#if os(Windows)
    @Suite
    struct LocalizedString {
        @Test(arguments: [
            ("hello", "Hello", "你好"),
            ("interpolation", "Interpolation %@ as string", "插值 %@ 字符串"),
            ("multiple interpolations", "Interpolation %lld as int, and %@ as string", "插值 %lld 整数，以及 %@ 字符串"),
        ])
        func localize(_ key: String, _ eng: String, _ chn: String) async throws {
            let en = Locale(identifier: "en")
            let cn = Locale(identifier: "zh-Hans")

            #expect(String(localized: key, table: "test", bundle: Bundle.module, locale: en) == eng)
            #expect(String(localized: key, table: "test", bundle: Bundle.module, locale: cn) == chn)
        }

        @Test
        func localize2() async throws {
            let en = Locale(identifier: "en")
            let cn = Locale(identifier: "zh-Hans")

            #expect(String(localized: "world", bundle: Bundle.module, locale: en) == "World")
            #expect(String(localized: "world", bundle: Bundle.module, locale: cn) == "世界")
        }
    }

    @Test func oemString() {
        let str = "ABC中文测试"
        let wstr = str.wideString
        let str2 = String(utf16: wstr)
        #expect(str == str2)

        let oemstr = str.oemCString
        let str3 = oemstr.withUnsafeBytes {
            String(oemCString: $0)
        }
        #expect(str == str3)
    }
#endif

@Test
func url() async throws {
    let test_txt = Bundle.module.path(forResource: "test.txt")!
    let url = URL(filePath: test_txt)
    #expect(url.fileSize == 0)
    #expect(url.filePath == test_txt)
    #expect(url.reachableSibling(named: "test2.txt") != nil)
    #expect(url.reachableSibling(named: "test2.txt")?.fileSize == 0)

    let url2 = Bundle.module.resourceURL?.reachableChild(named: "test2.txt")
    #expect(url2 != nil)

    let dir = URL.applicationSupportDirectory
    #expect(dir.filePath.hasSuffix("/") && !dir.filePath.hasPrefix("/"))
    #expect(try dir.checkResourceIsReachable())

    let dir2 = dir.ensuringChild(named: "A/B/C")
    #expect(dir2?.reachable ?? false == false)
    let dir3 = dir.ensuringChild(named: "A/B/C/")
    #expect(dir3?.reachable ?? false)

    try? FileManager.default.removeItem(at: dir3!)
    try? FileManager.default.removeItem(at: dir.ensuringChild(named: "A/B")!)
    try? FileManager.default.removeItem(at: dir.ensuringChild(named: "A/")!)
}
@Test
func xml() async throws {
    // let xml = try XMLDocument(xmlString:
    // """
    // <?xml version="1.0" encoding="UTF-8"?>
    // <books>
    // <book id="1001">
    // <name>The Great Gatsby</name>
    // <author>F. Scott Fitzgerald</author>
    // <price>10.99</price>
    // </book>
    // <book id="1002">
    // <name>To Kill a Mockingbird</name>
    // <author>Harper Lee</author>
    // <price>7.99</price>
    // </book>
    // </books>
    // """)
    let data = try Data(contentsOf: URL(filePath: Bundle.module.path(forResource: "utf16le.txt")!))
    let xml = try XMLDocument(utf16Data: data, options: .documentTidyXML)
    var cnt = 0

    xml.forEachElement { parent, name, attribute, value in
        print("parent: \(parent)")
        print("name: \(name)")
        print("attribute: \(attribute)")
        print("value: \(value)")

        cnt += 1
    }

    #expect(cnt == 4)

    #expect(throws: Error.self) {
        _ = try XMLDocument(utf16Data: Data())
    }
}
