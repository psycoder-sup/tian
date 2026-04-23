import Foundation

/// Schema-validated payload that `claude -p --json-schema` returns for
/// `config auto-set`. Claude enforces the JSON Schema server-side, so by
/// the time we decode it we can trust the shape.
struct AutoSetPayload: Codable, Equatable {
    let setup: [SetupEntry]
    let copy: [CopyEntry]
    /// Optional human-readable notes, rendered as a comment block above
    /// the TOML body. Not part of the `WorktreeConfig` schema.
    let notes: String?

    struct SetupEntry: Codable, Equatable {
        let command: String
    }

    struct CopyEntry: Codable, Equatable {
        let source: String
        let dest: String
    }

    /// JSON Schema passed to `claude -p --json-schema`.
    ///
    /// Kept as a compact single-line string so it fits cleanly on the
    /// command line. Must stay in sync with the Codable shape above —
    /// the `AutoSetPayloadTests` suite pins this contract.
    static let jsonSchema: String = #"""
    {"type":"object","additionalProperties":false,"required":["setup","copy"],"properties":{"setup":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["command"],"properties":{"command":{"type":"string","minLength":1}}}},"copy":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["source","dest"],"properties":{"source":{"type":"string","minLength":1},"dest":{"type":"string","minLength":1}}}},"notes":{"type":"string"}}}
    """#
}

/// The envelope `claude -p --output-format json` wraps every response in.
/// We only decode the fields we actually use; the rest stay as unknown
/// keys (JSONDecoder ignores them by default).
struct ClaudeResultEnvelope: Decodable {
    let isError: Bool
    let subtype: String?
    let result: String?
    let structuredOutput: AutoSetPayload?

    enum CodingKeys: String, CodingKey {
        case isError = "is_error"
        case subtype
        case result
        case structuredOutput = "structured_output"
    }
}
