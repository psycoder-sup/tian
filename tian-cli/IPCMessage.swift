import Foundation

let ipcProtocolVersion = 1

// MARK: - Request

struct IPCRequest: Codable {
    let version: Int
    let command: String
    let params: [String: IPCValue]
    let env: IPCEnv
}

struct IPCEnv: Codable {
    let paneId: String
    let tabId: String
    let spaceId: String
    let workspaceId: String
}

// MARK: - Response

struct IPCResponse: Codable {
    let version: Int
    let ok: Bool
    let result: [String: IPCValue]?
    let error: IPCError?
}

struct IPCError: Codable {
    let code: Int
    let message: String
}

// MARK: - IPCValue

enum IPCValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case array([IPCValue])
    case object([String: IPCValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([IPCValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: IPCValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode IPCValue"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }
}
