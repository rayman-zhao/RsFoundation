import Foundation
import Testing
import RsFoundation

final class TestPref : Preferable {
    var key1: String = "value1"
    var key2: Int = 42

    init() {
    }

    init(key1: String, key2: Int) {
        self.key1 = key1
        self.key2 = key2
    }
}

struct TestPref2 : Preferable {
    var key1: String = "value2"
    var key2: Int = 999
}

enum Theme: String, RawValuePreferable {
    case dark
    case light

    public init() {
        self = .light
    }
}

enum Theme2: String, RawValuePreferable {
    case auto

    public init() {
        self = .auto
    }
}

func defaultPref(_ pref: Preferences) {
    let t = pref.load(for: TestPref.self)
    #expect(t.key1 == "value1")
    #expect(t.key2 == 42)
}

@Suite
struct PreferencesTests {
    @Test
    func notExistAppPref() async throws {
        let pref = JsonPreferences.makeAppStandard(group: "SwiftWorks", product: "Ruslan", name: "tempxxx")
        defaultPref(pref)
    }

    @Test
    func emptyAppPref() async throws {
        let pref = JsonPreferences.makeAppStandard(group: "SwiftWorks", product: "Ruslan", name: "temp")
        let content = ""
        let url = URL.applicationSupportDirectory.appending(path: "/SwiftWorks/Ruslan/temp.json")
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer {
            try! FileManager.default.removeItem(at: url)
        }

        defaultPref(pref)
    }

    @Test
    func emptyJsonAppPref() async throws {
        let pref = JsonPreferences.makeAppStandard(group: "SwiftWorks", product: "Ruslan", name: "temp2")
        let content = "{}"
        let url = URL.applicationSupportDirectory.appending(path: "/SwiftWorks/Ruslan/temp2.json")
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer {
            try! FileManager.default.removeItem(at: url)
        }

        defaultPref(pref)
    }

    @Test
    func nomoduleJsonAppPref() async throws {
        let pref = JsonPreferences.makeAppStandard(group: "SwiftWorks", product: "Ruslan", name: "temp3")
        let content = """
        {
            "abc": {"key1": "123", "key2": 777}
        }
        """
        let url = URL.applicationSupportDirectory.appending(path: "/SwiftWorks/Ruslan/temp3.json")
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer {
            try! FileManager.default.removeItem(at: url)
        }

        defaultPref(pref)
    }

    @Test
    func moduleJsonAppPref() async throws {
        let pref = JsonPreferences.makeAppStandard(group: "SwiftWorks", product: "Ruslan", name: "temp4")
        let content = """
        {
            "TestPref": {"key1": "123", "key2": 777, "theme": "auto"},
            "Theme":{"value":"dark"},
            "Theme2":{"value":"dark"}
        }
        """
        let url = URL.applicationSupportDirectory.appending(path: "/SwiftWorks/Ruslan/temp4.json")
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer {
            try! FileManager.default.removeItem(at: url)
        }

        let testPref = pref.load(for: TestPref.self)
        #expect(testPref.key1 == "123")
        #expect(testPref.key2 == 777)

        let theme = pref.load(for: Theme.self)
        #expect(theme == .dark)

        let theme2 = pref.load(for: Theme2.self)
        #expect(theme2 == .auto)
    }

    @Test
    func saveModulePref() async throws {
        let pref = JsonPreferences.makeAppStandard(group: "SwiftWorks", product: "Ruslan", name: "temp5")
        defer {
            try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: "/SwiftWorks/Ruslan/temp5.json"))
        }
        
        let test = TestPref(key1: "abcd", key2: 666)
        pref.save(test)

        let test2 = pref.load(for: TestPref.self)
        #expect(test2.key1 == "abcd")
        #expect(test2.key2 == 666)

        let theme: Theme  = .dark
        pref.save(theme)
    }

    @Test
    func saveModulePrefWithOthers() async throws {
        let pref = JsonPreferences.makeAppStandard(group: "SwiftWorks", product: "Ruslan", name: "temp6")
        defer {
            try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: "/SwiftWorks/Ruslan/temp6.json"))
        }
        
        pref.save(TestPref())
        pref.save(TestPref2(key1: "####", key2: -1))

        let test = TestPref(key1: "abcd", key2: 666)
        pref.save(test)

        let test2 = pref.load(for: TestPref2.self)
        #expect(test2.key1 == "####")
        #expect(test2.key2 == -1)
    }
}