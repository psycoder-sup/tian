import ArgumentParser
import Foundation

struct ConfigGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage .tian/config.toml.",
        subcommands: [
            ConfigAutoSet.self,
        ]
    )
}

struct ConfigAutoSet: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "auto-set",
        abstract: "Generate .tian/config.toml using claude -p.",
        discussion: """
            Analyzes the current repository with `claude -p` (read-only \
            tools) and writes a .tian/config.toml populated with \
            [[setup]] and [[copy]] sections. Must be run from inside a \
            git repository; refuses to overwrite an existing file unless \
            --force is passed.
            """
    )

    @Flag(name: .long, help: "Overwrite an existing .tian/config.toml.")
    var force: Bool = false

    @Option(name: .long, help: "Claude model passed to `claude -p --model`.")
    var model: String = "sonnet"

    @Option(name: .long, help: "Override path to the claude executable.")
    var claudePath: String?

    func run() throws {
        // Enforce TIAN_SOCKET for UX consistency with other subcommands
        // (we do not send an IPC request — the check only validates we're
        // running inside a tian session).
        _ = try TianEnvironment.fromEnvironment()

        let invoker = ProcessClaudeInvoker(claudePath: claudePath)
        let runner = ConfigAutoSetRunner(invoker: invoker)

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let result = try runner.run(cwd: cwd, force: force, model: model)

        let setupWord = result.setupCount == 1 ? "setup command" : "setup commands"
        let copyWord = result.copyCount == 1 ? "copy rule" : "copy rules"
        FileHandle.standardError.write(Data(
            "Wrote .tian/config.toml (\(result.setupCount) \(setupWord), \(result.copyCount) \(copyWord))\n".utf8
        ))
    }
}
