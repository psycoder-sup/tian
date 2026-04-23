import Testing
import Foundation

struct AutoSetPromptTests {

    @Test func templateContainsTaskStatement() {
        let prompt = AutoSetPrompt.template
        #expect(prompt.contains("Analyze this repository"))
        #expect(prompt.contains("JSON Schema"))
    }

    @Test func templateDescribesStructuredFields() {
        let prompt = AutoSetPrompt.template
        #expect(prompt.contains("setup[].command"))
        #expect(prompt.contains("copy[].source"))
        #expect(prompt.contains("copy[].dest"))
        #expect(prompt.contains("notes"))
    }

    @Test func templateListsOutOfScopeFields() {
        let prompt = AutoSetPrompt.template
        #expect(prompt.contains("worktree_dir"))
        #expect(prompt.contains("layout"))
        #expect(prompt.contains("Out of scope"))
    }

    @Test func templateIncludesFewShotExamples() {
        let prompt = AutoSetPrompt.template
        #expect(prompt.contains("bun install"))
        #expect(prompt.contains("xcodegen generate"))
    }
}

struct AutoSetPayloadTests {

    @Test func schemaIsValidJSON_andDeclaresRequiredFields() throws {
        let data = Data(AutoSetPayload.jsonSchema.utf8)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj != nil)
        let required = obj?["required"] as? [String]
        #expect(required?.contains("setup") == true)
        #expect(required?.contains("copy") == true)
    }

    @Test func payloadRoundTripsThroughJSON() throws {
        let payload = AutoSetPayload(
            setup: [.init(command: "bun install")],
            copy: [.init(source: ".env.local", dest: ".")],
            notes: "demo"
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(AutoSetPayload.self, from: data)
        #expect(decoded == payload)
    }
}
