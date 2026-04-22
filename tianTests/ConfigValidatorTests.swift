import Testing
import Foundation

struct ConfigValidatorTests {

    @Test func emptyTOMLIsValidWithZeroCounts() throws {
        let result = try ConfigValidator.validate(tomlString: "")
        #expect(result.setupCount == 0)
        #expect(result.copyCount == 0)
    }

    @Test func commentsOnlyIsValid() throws {
        let toml = "# nothing to configure\n"
        let result = try ConfigValidator.validate(tomlString: toml)
        #expect(result.setupCount == 0)
        #expect(result.copyCount == 0)
    }

    @Test func countsSetupEntries() throws {
        let toml = """
        [[setup]]
        command = "bun install"

        [[setup]]
        command = "cp .env.example .env"
        """
        let result = try ConfigValidator.validate(tomlString: toml)
        #expect(result.setupCount == 2)
        #expect(result.copyCount == 0)
    }

    @Test func countsCopyEntries() throws {
        let toml = """
        [[copy]]
        source = ".env*"
        dest = "."

        [[copy]]
        source = "config/local.yml"
        dest = "config/"
        """
        let result = try ConfigValidator.validate(tomlString: toml)
        #expect(result.setupCount == 0)
        #expect(result.copyCount == 2)
    }

    @Test func rejectsMalformedTOML() {
        let toml = "this is = = not valid toml"
        #expect(throws: CLIError.self) {
            try ConfigValidator.validate(tomlString: toml)
        }
    }

    @Test func rejectsSetupMissingCommand() {
        let toml = """
        [[setup]]
        # missing `command`
        """
        #expect(throws: CLIError.self) {
            try ConfigValidator.validate(tomlString: toml)
        }
    }

    @Test func rejectsCopyMissingSourceOrDest() {
        let toml1 = """
        [[copy]]
        dest = "."
        """
        #expect(throws: CLIError.self) {
            try ConfigValidator.validate(tomlString: toml1)
        }

        let toml2 = """
        [[copy]]
        source = ".env*"
        """
        #expect(throws: CLIError.self) {
            try ConfigValidator.validate(tomlString: toml2)
        }
    }

    @Test func ignoresUnknownTopLevelFields() throws {
        let toml = """
        worktree_dir = "~/.worktrees"

        [[setup]]
        command = "bun install"
        """
        let result = try ConfigValidator.validate(tomlString: toml)
        #expect(result.setupCount == 1)
    }
}
