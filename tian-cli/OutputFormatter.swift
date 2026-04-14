import ArgumentParser
import Foundation

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case table
    case json
}

enum OutputFormatter {

    /// Formats rows as an aligned table with headers.
    /// Prefix active row with `*`, others with ` `.
    static func formatTable(
        headers: [String],
        rows: [[String]],
        activeIndex: Int? = nil
    ) -> String {
        guard !headers.isEmpty else { return "" }

        // Calculate column widths
        var widths = headers.map(\.count)
        for row in rows {
            for (i, cell) in row.enumerated() where i < widths.count {
                widths[i] = max(widths[i], cell.count)
            }
        }

        var lines: [String] = []

        // Header row
        let header = "  " + headers.enumerated().map { i, h in
            h.padding(toLength: widths[i], withPad: " ", startingAt: 0)
        }.joined(separator: "  ")
        lines.append(header)

        // Data rows
        for (rowIndex, row) in rows.enumerated() {
            let prefix = rowIndex == activeIndex ? "* " : "  "
            let line = prefix + row.enumerated().map { i, cell in
                let w = i < widths.count ? widths[i] : cell.count
                return cell.padding(toLength: w, withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    /// Pretty-prints an IPCValue as JSON.
    static func formatJSON(_ value: IPCValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
