import Foundation
import Testing
@testable import Rosewood

struct JSONValueCodecTests {
    private struct Payload: Codable, Equatable {
        let name: String
        let count: Int
        let tags: [String]
    }

    private func decodedString(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    // MARK: - data(from:)

    @Test
    func dataFromNilProducesJSONNull() throws {
        let data = try JSONValueCodec.data(from: nil)
        #expect(decodedString(data) == "null")
    }

    @Test
    func dataFromNSNullProducesJSONNull() throws {
        let data = try JSONValueCodec.data(from: NSNull())
        #expect(decodedString(data) == "null")
    }

    @Test
    func dataFromDictionaryProducesValidJSON() throws {
        let data = try JSONValueCodec.data(from: ["key": "value"])
        let object = try JSONSerialization.jsonObject(with: data)
        let dictionary = try #require(object as? [String: String])
        #expect(dictionary["key"] == "value")
    }

    @Test
    func dataFromEmptyDictionaryProducesEmptyObject() throws {
        let data = try JSONValueCodec.data(from: [String: Any]())
        let object = try JSONSerialization.jsonObject(with: data)
        let dictionary = try #require(object as? [String: Any])
        #expect(dictionary.isEmpty)
    }

    @Test
    func dataFromArrayProducesValidJSON() throws {
        let data = try JSONValueCodec.data(from: [1, 2, 3])
        let object = try JSONSerialization.jsonObject(with: data)
        #expect(object as? [Int] == [1, 2, 3])
    }

    @Test
    func dataFromNestedStructureRoundTripsThroughSerialization() throws {
        let value: [String: Any] = [
            "name": "rosewood",
            "version": 2,
            "features": ["tabs", "search"],
            "nested": ["deep": true]
        ]

        let data = try JSONValueCodec.data(from: value)
        let restored = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(restored["name"] as? String == "rosewood")
        #expect(restored["version"] as? Int == 2)
        #expect(restored["features"] as? [String] == ["tabs", "search"])
        #expect((restored["nested"] as? [String: Any])?["deep"] as? Bool == true)
    }

    @Test
    func dataFromTopLevelStringFallsBackToEncoder() throws {
        // A bare string is not a valid top-level JSON object, so JSONSerialization is
        // skipped and the AnyCodable encoder path emits a quoted JSON string.
        let data = try JSONValueCodec.data(from: "hello")
        #expect(decodedString(data) == "\"hello\"")
    }

    @Test
    func dataFromTopLevelNumberFallsBackToEncoder() throws {
        let data = try JSONValueCodec.data(from: 42)
        #expect(decodedString(data) == "42")
    }

    @Test
    func dataFromTopLevelBoolFallsBackToEncoder() throws {
        let data = try JSONValueCodec.data(from: true)
        #expect(decodedString(data) == "true")
    }

    // MARK: - object(from:)

    @Test
    func objectFromEncodableProducesJSONObject() throws {
        let payload = Payload(name: "rosewood", count: 3, tags: ["a", "b"])
        let object = try JSONValueCodec.object(from: payload)
        let dictionary = try #require(object as? [String: Any])

        #expect(dictionary["name"] as? String == "rosewood")
        #expect(dictionary["count"] as? Int == 3)
        #expect(dictionary["tags"] as? [String] == ["a", "b"])
    }

    @Test
    func objectFromEncodableRoundTripsBackThroughData() throws {
        let payload = Payload(name: "rw", count: 1, tags: [])

        let object = try JSONValueCodec.object(from: payload)
        let data = try JSONValueCodec.data(from: object)
        let restored = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(restored["name"] as? String == "rw")
        #expect(restored["count"] as? Int == 1)
        #expect(restored["tags"] as? [String] == [])
    }
}
