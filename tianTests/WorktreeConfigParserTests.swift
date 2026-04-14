import Testing
import Foundation
@testable import tian

struct WorktreeConfigParserTests {

    // MARK: - Full Config

    @Test func parseValidConfigWithAllFields() throws {
        let toml = """
        worktree_dir = ".wt"
        setup_timeout = 120
        shell_ready_delay = 1.0

        [[copy]]
        source = ".env*"
        dest = "."

        [[copy]]
        source = "config/credentials/*.yml"
        dest = "config/credentials/"

        [[setup]]
        command = "npm install"

        [[setup]]
        command = "npm run build"

        [layout]
        direction = "horizontal"
        ratio = 0.6

        [layout.first]
        command = "npm run dev"

        [layout.second]
        direction = "vertical"
        ratio = 0.5

        [layout.second.first]
        command = "npm run test"

        [layout.second.second]
        """

        let config = try WorktreeConfigParser.parse(tomlString: toml)

        #expect(config.worktreeDir == ".wt")
        #expect(config.setupTimeout == 120)
        #expect(config.shellReadyDelay == 1.0)
        #expect(config.copyRules.count == 2)
        #expect(config.copyRules[0].source == ".env*")
        #expect(config.copyRules[0].dest == ".")
        #expect(config.copyRules[1].source == "config/credentials/*.yml")
        #expect(config.copyRules[1].dest == "config/credentials/")
        #expect(config.setupCommands == ["npm install", "npm run build"])

        // Layout: horizontal split -> pane + vertical split -> pane + pane
        guard case .split(let dir, let ratio, let first, let second) = config.layout else {
            Issue.record("Expected split layout at root")
            return
        }
        #expect(dir == .horizontal)
        #expect(ratio == 0.6)

        guard case .pane(let cmd1) = first else {
            Issue.record("Expected pane as first child")
            return
        }
        #expect(cmd1 == "npm run dev")

        guard case .split(let dir2, let ratio2, let second1, let second2) = second else {
            Issue.record("Expected split as second child")
            return
        }
        #expect(dir2 == .vertical)
        #expect(ratio2 == 0.5)

        guard case .pane(let cmd2) = second1 else {
            Issue.record("Expected pane as second.first")
            return
        }
        #expect(cmd2 == "npm run test")

        guard case .pane(let cmd3) = second2 else {
            Issue.record("Expected pane as second.second")
            return
        }
        #expect(cmd3 == nil)
    }

    // MARK: - Defaults

    @Test func parseEmptyConfigUsesDefaults() throws {
        let config = try WorktreeConfigParser.parse(tomlString: "")

        #expect(config.worktreeDir == "~/.worktrees")
        #expect(config.setupTimeout == 300)
        #expect(config.shellReadyDelay == 0.5)
        #expect(config.copyRules.isEmpty)
        #expect(config.setupCommands.isEmpty)
        #expect(config.layout == nil)
    }

    @Test func parseMissingOptionalFieldsUsesDefaults() throws {
        let toml = """
        worktree_dir = "trees"
        """

        let config = try WorktreeConfigParser.parse(tomlString: toml)

        #expect(config.worktreeDir == "trees")
        #expect(config.setupTimeout == 300)
        #expect(config.shellReadyDelay == 0.5)
        #expect(config.copyRules.isEmpty)
        #expect(config.setupCommands.isEmpty)
        #expect(config.layout == nil)
    }

    // MARK: - Invalid Types

    @Test func parseInvalidTypesUsesDefaults() throws {
        let toml = """
        worktree_dir = 123
        setup_timeout = "not a number"
        shell_ready_delay = true
        """

        let config = try WorktreeConfigParser.parse(tomlString: toml)

        #expect(config.worktreeDir == "~/.worktrees")
        #expect(config.setupTimeout == 300)
        #expect(config.shellReadyDelay == 0.5)
    }

    // MARK: - Layout

    @Test func parseNestedLayoutTree() throws {
        let toml = """
        [layout]
        direction = "horizontal"
        ratio = 0.7

        [layout.first]
        direction = "vertical"
        ratio = 0.4

        [layout.first.first]
        command = "top"

        [layout.first.second]

        [layout.second]
        command = "vim"
        """

        let config = try WorktreeConfigParser.parse(tomlString: toml)

        guard case .split(.horizontal, 0.7, let first, let second) = config.layout else {
            Issue.record("Expected horizontal split at root")
            return
        }

        guard case .split(.vertical, 0.4, let first1, let first2) = first else {
            Issue.record("Expected vertical split as first child")
            return
        }

        guard case .pane(let cmd1) = first1 else {
            Issue.record("Expected pane as first.first")
            return
        }
        #expect(cmd1 == "top")

        guard case .pane(let cmd2) = first2 else {
            Issue.record("Expected pane as first.second")
            return
        }
        #expect(cmd2 == nil)

        guard case .pane(let cmd3) = second else {
            Issue.record("Expected pane as second")
            return
        }
        #expect(cmd3 == "vim")
    }

    @Test func parseConfigWithNoLayout() throws {
        let toml = """
        worktree_dir = ".wt"

        [[setup]]
        command = "make build"
        """

        let config = try WorktreeConfigParser.parse(tomlString: toml)
        #expect(config.layout == nil)
        #expect(config.setupCommands == ["make build"])
    }

    // MARK: - Malformed TOML

    @Test func parseMalformedTOMLThrowsError() throws {
        let toml = """
        worktree_dir = "valid"
        this is not valid toml !!!
        """

        #expect(throws: WorktreeError.self) {
            try WorktreeConfigParser.parse(tomlString: toml)
        }
    }

    // MARK: - Copy Rules

    @Test func parseCopyRulesWithGlobPatterns() throws {
        let toml = """
        [[copy]]
        source = ".env*"
        dest = "."

        [[copy]]
        source = "**/*.secret"
        dest = "secrets/"

        [[copy]]
        source = "Makefile"
        dest = "Makefile"
        """

        let config = try WorktreeConfigParser.parse(tomlString: toml)

        #expect(config.copyRules.count == 3)
        #expect(config.copyRules[0] == CopyRule(source: ".env*", dest: "."))
        #expect(config.copyRules[1] == CopyRule(source: "**/*.secret", dest: "secrets/"))
        #expect(config.copyRules[2] == CopyRule(source: "Makefile", dest: "Makefile"))
    }

    @Test func parseCopyRulesMissingRequiredFieldsSkips() throws {
        let toml = """
        [[copy]]
        source = ".env"

        [[copy]]
        dest = "."

        [[copy]]
        source = "valid"
        dest = "also-valid"
        """

        let config = try WorktreeConfigParser.parse(tomlString: toml)
        #expect(config.copyRules.count == 1)
        #expect(config.copyRules[0].source == "valid")
    }

    // MARK: - Layout Edge Cases

    @Test func parseLayoutClampsRatio() throws {
        let toml = """
        [layout]
        direction = "horizontal"
        ratio = 1.5

        [layout.first]

        [layout.second]
        """

        let config = try WorktreeConfigParser.parse(tomlString: toml)

        guard case .split(_, let ratio, _, _) = config.layout else {
            Issue.record("Expected split layout")
            return
        }
        #expect(ratio == 1.0)
    }
}
