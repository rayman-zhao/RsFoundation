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
    ("lena.png", true),
    ("test.txt", false),
])
func dataTypes(_ fn: String, _ img: Bool) async throws {
    let url = URL(filePath: try #require(Bundle.module.path(forResource: fn)))
    let d = try Data(contentsOf: url)
    #expect(d.isImage == img)
}
@Test(arguments: [
    // The first segment marker is not constrained: Adobe APP14, not JFIF/Exif/DQT.
    ([0xFF, 0xD8, 0xFF, 0xEE, 0x41, 0x64, 0x6F, 0x62, 0x65, 0xFF, 0xD9], true),
    // Trailing bytes after EOI still reject.
    ([0xFF, 0xD8, 0xFF, 0xEE, 0x41, 0x64, 0x6F, 0x62, 0x65, 0xFF, 0xD9, 0x0A], false),
    // SOI followed by EOI only.
    ([0xFF, 0xD8, 0xFF, 0xD9], false),
])
func dataJPEG(_ bytes: [UInt8], _ jpeg: Bool) async throws {
    #expect(Data(bytes).isJPEG == jpeg)
}

private let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
private let pngIEND: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]
// Signature + a stubbed IHDR chunk header + IEND.
private let pngMinimal: [UInt8] = pngSignature + [0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52] + pngIEND
private let pngTrailingByte: [UInt8] = pngMinimal + [0x0A]

@Test(arguments: [
    (pngMinimal, true),
    // Trailing bytes after IEND still reject.
    (pngTrailingByte, false),
    // Signature alone, shorter than the IEND trailer.
    (pngSignature, false),
])
func dataPNG(_ bytes: [UInt8], _ png: Bool) async throws {
    #expect(Data(bytes).isPNG == png)
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
            (
                "multiple interpolations", "Interpolation %lld as int, and %@ as string",
                "插值 %lld 整数，以及 %@ 字符串"
            ),
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
func string() async throws {
    let str = "<hello & world>'foo'"
    #expect(str.xmlEscaped() == "&lt;hello &amp; world&gt;&apos;foo&apos;")
    #expect(str.xmlEscaped().xmlUnescaped() == str)
}

@Test
func stringXMLEntities() async throws {
    // Text that itself looks like an entity: the escaped &amp; must not be unescaped twice.
    let entity = "a &lt; b &amp; c"
    #expect(entity.xmlEscaped() == "a &amp;lt; b &amp;amp; c")
    #expect(entity.xmlEscaped().xmlUnescaped() == entity)

    #expect("&amp;lt;".xmlUnescaped() == "&lt;")
    #expect("&nbsp;".xmlUnescaped() == "&nbsp;")
}

@Test
func url() async throws {
    let test_txt = Bundle.module.path(forResource: "test.txt")!
    let url = URL(filePath: test_txt)
    #expect(url.fileSize == 0)
    #expect(url.filePath == test_txt)
    #expect(url.isDirectory == false)
    #expect(url.reachableSibling(named: "test2.txt") != nil)
    #expect(url.reachableSibling(named: "test2.txt")?.fileSize == 0)

    let url2 = Bundle.module.resourceURL?.reachableChild(named: "test2.txt")
    #expect(url2 != nil)

    // Directory detection must rely on the file system, not on how the URL was constructed.
    var resourceDirPath = Bundle.module.resourceURL!.filePath
    while resourceDirPath.last == "/" || resourceDirPath.last == "\\" {
        resourceDirPath.removeLast()
    }
    let noHintDir = URL(filePath: resourceDirPath)
    #expect(noHintDir.hasDirectoryPath == false)
    #expect(noHintDir.isDirectory)
    #expect(noHintDir.reachableChild(named: "test.txt") != nil)

    let hintedFile = URL(filePath: test_txt, directoryHint: .isDirectory)
    #expect(hintedFile.isDirectory == false)
    #expect(hintedFile.reachableSibling(named: "test2.txt") != nil)

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

    #if os(Windows)
        // Network paths: the \\server\share prefix must survive filePath, whether the
        // server is encoded as the leading "//" of the path or as the URL host.
        let unc = URL(filePath: "//med-dev/transfer/file.txt")
        #expect(unc.filePath == "//med-dev/transfer/file.txt")
        #expect(URL(filePath: unc.filePath).filePath == unc.filePath)

        let uncHosted = URL(string: "file://med-dev/transfer/file.txt")!
        #expect(uncHosted.filePath == "//med-dev/transfer/file.txt")
    #endif
}

@Test
func availableChild() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "RsFoundationTest_AvailableChild_\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for name in ["report.txt", "report 2.txt"] {
        try Data().write(to: directory.appendingPathComponent(name))
    }

    #expect(directory.availableChild(baseNamed: "report.txt")?.lastPathComponent == "report 3.txt")

    var dirPath = directory.filePath
    while dirPath.last == "/" || dirPath.last == "\\" {
        dirPath.removeLast()
    }
    #expect(URL(filePath: dirPath).availableChild(baseNamed: "report.txt")?.lastPathComponent == "report 3.txt")
}

@Test
func reachableChildMatching() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "RsFoundationTest_ReachableChildMatching_\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for name in ["Report.txt", "img_1234.jpg", "PHOTO.JPEG", "notes.md"] {
        try Data().write(to: directory.appendingPathComponent(name))
    }

    #expect(directory.reachableChild(matching: /\.jpg$/)?.lastPathComponent == "img_1234.jpg")
    // (?i) for case-insensitivity; jpe?g covers both the jpg and jpeg extensions.
    #expect(directory.reachableChild(matching: /^(?i)photo\.jpe?g$/)?.lastPathComponent == "PHOTO.JPEG")
    #expect(directory.reachableChild(matching: /(?i)port/)?.lastPathComponent == "Report.txt")
    #expect(directory.reachableChild(matching: /^(?i)report\.txt$/)?.lastPathComponent == "Report.txt")
    #expect(directory.reachableChild(matching: /^img_.{4}\.jpg$/)?.lastPathComponent == "img_1234.jpg")
    #expect(directory.reachableChild(matching: /^img_.{3}\.jpg$/) == nil)
    #expect(directory.reachableChild(matching: /\.pdf$/) == nil)
    #expect(directory.appendingPathComponent("Report.txt").reachableChild(matching: /./) == nil)
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

    let books = try XMLDocument(
        xmlString: """
        <books><book id="1001"><name>The Great Gatsby</name></book><empty/></books>
        """)
    var elementCount = 0
    var nameValue: String?
    books.forEachElement { _, name, attribute, value in
        guard attribute == nil else { return }
        elementCount += 1
        if name == "name" { nameValue = value }
    }
    #expect(nameValue == "The Great Gatsby")
    #expect(elementCount == 3)
}
