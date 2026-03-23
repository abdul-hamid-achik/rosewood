import Foundation

enum JSONValueCodec {
    static func data(from value: Any?) throws -> Data {
        guard let value else {
            return Data("null".utf8)
        }

        if value is NSNull {
            return Data("null".utf8)
        }

        if JSONSerialization.isValidJSONObject(value) {
            return try JSONSerialization.data(withJSONObject: value)
        }

        return try JSONEncoder().encode(AnyCodable(value))
    }

    static func object<E: Encodable>(from encodable: E) throws -> Any {
        let data = try JSONEncoder().encode(encodable)
        return try JSONSerialization.jsonObject(with: data)
    }
}
