import Foundation

/// Should have the default initializer
public protocol ExpressibleByEmptyLiteral {
    init()
}

/// A type that can be saved and loaded as a preference value.
public typealias PreferenceValue = Codable & ExpressibleByEmptyLiteral

/// Protocol for enum types saved/loaded by their raw value.
public protocol RawPreferenceValue: RawRepresentable, PreferenceValue {}

private enum RawPreferenceValueCodingKey: String, CodingKey {
    case value
}

/// A container that can load and save preference values from/to persistent storage.
extension RawPreferenceValue where RawValue: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RawPreferenceValueCodingKey.self)
        try container.encode(self.rawValue, forKey: .value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RawPreferenceValueCodingKey.self)
        let rawValue = try container.decode(RawValue.self, forKey: .value)
        guard let instance = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid \(Self.self) value: \(rawValue)"))
        }
        self = instance
    }
}

/// A container that can load and save preference values from/to persistent storage.
public protocol Preferences {
    func load<T: PreferenceValue>(for preferenceValueType: T.Type) -> T
    func save<T: PreferenceValue>(_ preferenceValue: T)
}

/// A JSON-based preferences file implementation.
public struct JSONPreferences: Preferences {
    let jsonFile: URL

    public func load<T: PreferenceValue>(for preferenceValueType: T.Type) -> T {
        guard jsonFile.reachable else {
            log.info("No preferences file found at \(jsonFile.path). Use defaults.")
            return T()
        }
        guard let fileData = try? Data(contentsOf: jsonFile) else {
            log.info("Failed open preferences file at \(jsonFile.path). Use defaults.")
            return T()
        }
        guard let jsonObj = try? JSONSerialization.jsonObject(with: fileData) as? [String: Any] else {
            log.info("Invalid JSON format at \(jsonFile.path). Use defaults.")
            return T()
        }
        guard let prefObj = jsonObj[String(describing: preferenceValueType)] else {
            log.info("No module \(preferenceValueType) found in \(jsonObj). Use defaults.")
            return T()
        }
        guard let prefData = try? JSONSerialization.data(withJSONObject: prefObj) else {
            log.info("Invalid module data \(prefObj). Use defaults")
            return T()
        }
        guard let pref = try? JSONDecoder().decode(preferenceValueType, from: prefData) else {
            log.info("Invalid module json \(String(data: prefData, encoding: .utf8)!). Use defaults")
            return T()
        }

        return pref
    }

    public func save<T: PreferenceValue>(_ preferenceValue: T) {
        guard let prefData = try? JSONEncoder().encode(preferenceValue) else {
            log.info("Failed to encode \(T.self) as json")
            return
        }
        guard let prefObj = try? JSONSerialization.jsonObject(with: prefData) else {
            log.info("Failed to encode \(prefData) as json object")
            return
        }

        var jsonObj: [String: Any] = [:]

        if let fileData = try? Data(contentsOf: jsonFile),
            let existingObj = try? JSONSerialization.jsonObject(with: fileData) as? [String: Any]
        {
            //log.info("Load existing \(existingObj.count) preferences")
            jsonObj = existingObj
        }

        jsonObj[String(describing: T.self)] = prefObj
        if let newFileData = try? JSONSerialization.data(withJSONObject: jsonObj) {
            try? newFileData.write(to: jsonFile)
        }
    }

    /// Creates a standard application preference file.
    public static func makeStandard(group: String, product: String, name: String = "app") -> Preferences {
        let fn = "\(group)/\(product)/\(name).json"
        guard let pref = URL.applicationSupportDirectory.ensuringChild(named: fn) else {
            fatalError("Can't reach preference file at \(fn)")
        }

        return JSONPreferences(jsonFile: pref)
    }
}
