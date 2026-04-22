import Testing
import Foundation

struct AutoSetPromptTests {

    @Test func templateContainsTaskStatement() {
        let prompt = AutoSetPrompt.template
        #expect(prompt.contains("Output ONLY valid TOML"))
        #expect(prompt.contains("no markdown fences"))
    }

    @Test func templateContainsSchemaAnchors() {
        let prompt = AutoSetPrompt.template
        #expect(prompt.contains("[[setup]]"))
        #expect(prompt.contains("[[copy]]"))
        #expect(prompt.contains("command = "))
        #expect(prompt.contains("source = "))
        #expect(prompt.contains("dest = "))
    }

    @Test func templateListsOutOfScopeFields() {
        let prompt = AutoSetPrompt.template
        #expect(prompt.contains("worktree_dir"))
        #expect(prompt.contains("layout"))
        #expect(prompt.contains("intentionally out of scope"))
    }

    @Test func templateIncludesFewShotExamples() {
        let prompt = AutoSetPrompt.template
        #expect(prompt.contains("bun install"))
        #expect(prompt.contains("xcodegen generate"))
    }
}
