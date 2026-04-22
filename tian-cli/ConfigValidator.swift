import Foundation
import TOMLKit

/// Counts of well-formed entries in a validated config.
struct ConfigValidationResult: Equatable {
    let setupCount: Int
    let copyCount: Int
}

/// Validates the TOML produced by `claude -p` has well-formed
/// `[[setup]]` and `[[copy]]` entries.
///
/// Does **not** validate the full `WorktreeConfig` schema — that is the
/// app's job when it reads the file at worktree-creation time. We only
/// check the two sections this CLI is meant to generate.
enum ConfigValidator {
    static func validate(tomlString: String) throws -> ConfigValidationResult {
        let table: TOMLTable
        do {
            table = try TOMLTable(string: tomlString)
        } catch let error as TOMLParseError {
            throw CLIError.general(
                "Claude returned invalid TOML: line \(error.source.begin.line): \(error.description)"
            )
        } catch {
            throw CLIError.general(
                "Claude returned invalid TOML: \(error.localizedDescription)"
            )
        }

        var setupCount = 0
        if let setupArray = table["setup"]?.array {
            for (i, item) in setupArray.enumerated() {
                guard let setupTable = item.table else {
                    throw CLIError.general(
                        "Invalid [[setup]] entry #\(i + 1): not a table."
                    )
                }
                guard setupTable["command"]?.string != nil else {
                    throw CLIError.general(
                        "Invalid [[setup]] entry #\(i + 1): missing required 'command' field."
                    )
                }
                setupCount += 1
            }
        }

        var copyCount = 0
        if let copyArray = table["copy"]?.array {
            for (i, item) in copyArray.enumerated() {
                guard let copyTable = item.table else {
                    throw CLIError.general(
                        "Invalid [[copy]] entry #\(i + 1): not a table."
                    )
                }
                guard copyTable["source"]?.string != nil else {
                    throw CLIError.general(
                        "Invalid [[copy]] entry #\(i + 1): missing required 'source' field."
                    )
                }
                guard copyTable["dest"]?.string != nil else {
                    throw CLIError.general(
                        "Invalid [[copy]] entry #\(i + 1): missing required 'dest' field."
                    )
                }
                copyCount += 1
            }
        }

        return ConfigValidationResult(setupCount: setupCount, copyCount: copyCount)
    }
}
