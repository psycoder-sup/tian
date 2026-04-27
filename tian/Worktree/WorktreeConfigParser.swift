import Foundation
import TOMLKit

/// Parses `.tian/config.toml` into a `WorktreeConfig`.
enum WorktreeConfigParser {
    /// Parse a TOML config file at the given URL.
    static func parse(fileURL: URL) throws -> WorktreeConfig {
        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw WorktreeError.configParseError(message: "Cannot read file: \(error.localizedDescription)")
        }
        return try parse(tomlString: content)
    }

    /// Parse a TOML config from a raw string.
    static func parse(tomlString: String) throws -> WorktreeConfig {
        let table: TOMLTable
        do {
            table = try TOMLTable(string: tomlString)
        } catch let error as TOMLParseError {
            throw WorktreeError.configParseError(
                message: "line \(error.source.begin.line): \(error.description)"
            )
        }

        var config = WorktreeConfig()

        // Scalar fields with defaults
        if let value = table["worktree_dir"]?.string {
            config.worktreeDir = value
        } else if table["worktree_dir"] != nil {
            Log.worktree.warning("worktree_dir has invalid type, using default")
        }

        if let value = table["setup_timeout"]?.int {
            config.setupTimeout = TimeInterval(value)
        } else if let value = table["setup_timeout"]?.double {
            config.setupTimeout = value
        } else if table["setup_timeout"] != nil {
            Log.worktree.warning("setup_timeout has invalid type, using default")
        }

        if let value = table["shell_ready_delay"]?.double {
            config.shellReadyDelay = value
        } else if let value = table["shell_ready_delay"]?.int {
            config.shellReadyDelay = TimeInterval(value)
        } else if table["shell_ready_delay"] != nil {
            Log.worktree.warning("shell_ready_delay has invalid type, using default")
        }

        if let value = table["setup_kill_grace"]?.double {
            config.setupKillGrace = value
        } else if let value = table["setup_kill_grace"]?.int {
            config.setupKillGrace = TimeInterval(value)
        } else if table["setup_kill_grace"] != nil {
            Log.worktree.warning("setup_kill_grace has invalid type, using default")
        }

        // [[copy]] array of tables
        if let copyArray = table["copy"]?.array {
            for item in copyArray {
                guard let copyTable = item.table else {
                    Log.worktree.warning("Skipping non-table entry in [[copy]]")
                    continue
                }
                guard let source = copyTable["source"]?.string else {
                    Log.worktree.warning("Skipping [[copy]] entry missing 'source'")
                    continue
                }
                guard let dest = copyTable["dest"]?.string else {
                    Log.worktree.warning("Skipping [[copy]] entry missing 'dest'")
                    continue
                }
                config.copyRules.append(CopyRule(source: source, dest: dest))
            }
        }

        // [[setup]] array of tables
        if let setupArray = table["setup"]?.array {
            for item in setupArray {
                guard let setupTable = item.table else {
                    Log.worktree.warning("Skipping non-table entry in [[setup]]")
                    continue
                }
                guard let command = setupTable["command"]?.string else {
                    Log.worktree.warning("Skipping [[setup]] entry missing 'command'")
                    continue
                }
                config.setupCommands.append(command)
            }
        }

        // [[archive]] array of tables
        if let archiveArray = table["archive"]?.array {
            for item in archiveArray {
                guard let archiveTable = item.table else {
                    Log.worktree.warning("Skipping non-table entry in [[archive]]")
                    continue
                }
                guard let command = archiveTable["command"]?.string else {
                    Log.worktree.warning("Skipping [[archive]] entry missing 'command'")
                    continue
                }
                config.archiveCommands.append(command)
            }
        }

        // [layout] table
        if let layoutTable = table["layout"]?.table {
            config.layout = parseLayoutNode(layoutTable)
        }

        Log.worktree.info(
            "Parsed .tian/config.toml: \(config.copyRules.count) copy rules, \(config.setupCommands.count) setup commands, \(config.archiveCommands.count) archive commands, layout=\(config.layout != nil ? "yes" : "no")"
        )

        return config
    }

    // MARK: - Private

    private static func parseLayoutNode(_ table: TOMLTable) -> LayoutNode? {
        if let directionStr = table["direction"]?.string {
            // Split node
            guard let direction = SplitDirection.from(stateValue: directionStr) else {
                Log.worktree.warning("Invalid layout direction '\(directionStr)', skipping node")
                return nil
            }

            var ratio = table["ratio"]?.double
                ?? table["ratio"]?.int.map(Double.init)
                ?? 0.5
            ratio = min(max(ratio, 0.0), 1.0)

            guard let firstTable = table["first"]?.table,
                  let first = parseLayoutNode(firstTable) else {
                Log.worktree.warning("Layout split node missing valid 'first' child")
                return nil
            }

            guard let secondTable = table["second"]?.table,
                  let second = parseLayoutNode(secondTable) else {
                Log.worktree.warning("Layout split node missing valid 'second' child")
                return nil
            }

            return .split(direction: direction, ratio: ratio, first: first, second: second)
        } else {
            // Pane node
            let command = table["command"]?.string
            return .pane(command: command)
        }
    }
}
