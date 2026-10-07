// A JSON value: what the Steam panel sends and receives for a setting, and what the
// CLI prints. Integers only; the settings hold no fractions.

import Foundation

public enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Int)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .number(value)
        } else if let value = try? container.decode(Double.self) {
            guard value.rounded() == value, abs(value) < 1e15 else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not an integer")
            }
            self = .number(Int(value))
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    public var bool: Bool? { if case let .bool(v) = self { v } else { nil } }
    public var number: Int? { if case let .number(v) = self { v } else { nil } }
    public var string: String? { if case let .string(v) = self { v } else { nil } }
    public var array: [JSONValue]? { if case let .array(v) = self { v } else { nil } }
    public var object: [String: JSONValue]? { if case let .object(v) = self { v } else { nil } }

    public static func parse(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    /// Compact JSON with sorted keys, as the CLI prints it.
    public var text: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? String(decoding: encoder.encode(self), as: UTF8.self)) ?? "null"
    }

    public static func encode<T: Encodable>(_ value: T) -> JSONValue {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
            let decoded = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return .null }
        return decoded
    }
}

extension L10n {
    public var json: JSONValue {
        .object(["en": .string(en), "uk": .string(uk), "ru": .string(ru)])
    }
}
