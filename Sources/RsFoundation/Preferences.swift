import Foundation

/// Should have the default initializer
public protocol ExpressibleByEmptyLiteral {
    init()
}

/// Protocol can be saved/loaded in a file
public typealias Preferable = Codable & ExpressibleByEmptyLiteral

/// Protocol for enum types saved/loaded by their raw value
public protocol RawValuePreferable: RawRepresentable, Preferable {}

fileprivate enum RawValueCodingKey: String, CodingKey {
    case value
}

public extension RawValuePreferable where RawValue: Codable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RawValueCodingKey.self)
        try container.encode(self.rawValue, forKey: .value)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RawValueCodingKey.self)
        let rawValue = try container.decode(RawValue.self, forKey: .value)
        guard let instance = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid \(Self.self) value: \(rawValue)"))
        }
        self = instance
    }
}

/// Preferences file protocol
public protocol Preferences {
    func load<T: Preferable>(for preferableType: T.Type) -> T
    func save<T: Preferable>(_ preferable: T)
}

/// JSON format preferences file implementation
public struct JsonPreferences : Preferences {
    let jsonFile: URL

    public func load<T: Preferable>(for preferableType: T.Type) -> T {
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
        guard let prefObj = jsonObj[String(describing: preferableType)] else {
            log.info("No module \(preferableType) found in \(jsonObj). Use defaults.")
            return T()
        }
        guard let prefData = try? JSONSerialization.data(withJSONObject: prefObj) else {
            log.info("Invalid module data \(prefObj). Use defaults")
            return T()
        }
        guard let pref = try? JSONDecoder().decode(preferableType, from: prefData) else {
            log.info("Invalid module json \(String(data: prefData, encoding: .utf8)!). Use defaults")
            return T()
        }
        
        return pref
    }

    public func save<T: Preferable>(_ preferable: T) {
        guard let prefData = try? JSONEncoder().encode(preferable) else {
            log.info("Failed to encode \(T.self) as json")
            return
        }
        guard let prefObj = try? JSONSerialization.jsonObject(with: prefData) else {
            log.info("Failed to encode \(prefData) as json object")
            return
        }

        var jsonObj: [String: Any] = [:]

        if let fileData = try? Data(contentsOf: jsonFile),
            let existingObj = try? JSONSerialization.jsonObject(with: fileData) as? [String: Any] {
                //log.info("Load existing \(existingObj.count) preferences")
                jsonObj = existingObj
        }

        jsonObj[String(describing: T.self)] = prefObj
        if let newFileData = try? JSONSerialization.data(withJSONObject: jsonObj) {
            try? newFileData.write(to: jsonFile)
        }
    }

    /// Factory method to make standard application preference file
    public static func makeAppStandard(group: String, product: String, name: String = "app") -> Preferences {
        let fn = "\(group)/\(product)/\(name).json"
        guard let pref = URL.applicationSupportDirectory.reachingChild(named: fn) else {
            fatalError("Can't reach preference file at \(fn)")
        }

        return JsonPreferences(jsonFile: pref)
    }
}