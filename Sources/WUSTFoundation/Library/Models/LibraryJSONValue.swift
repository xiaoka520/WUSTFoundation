import Foundation

public indirect enum LibraryJSONValue: Codable, Hashable, Sendable {
    case object([String: LibraryJSONValue])
    case array([LibraryJSONValue])
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([LibraryJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: LibraryJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported library JSON value.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var integerValue: Int? {
        switch self {
        case .integer(let value): Int(exactly: value)
        case .number(let value) where value.rounded() == value: Int(exactly: value)
        case .string(let value): Int(value)
        default: nil
        }
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
}
