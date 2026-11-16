import Foundation

public enum AcademicToolsGenerator {
    public static let maxTableColumns = 12
    public static let maxTableRows = 30

    // MARK: - 2D Table Grid <-> CSV & Booktabs

    public static func tableGridToCSV(_ grid: TableGridData) -> String {
        var lines: [String] = []
        if !grid.headers.isEmpty {
            lines.append(grid.headers.map(escapeCSVField).joined(separator: ", "))
        }
        for row in grid.rows {
            lines.append(row.map(escapeCSVField).joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    public static func csvToTableGrid(_ csvText: String, base: TableGridData = TableGridData()) -> TableGridData {
        let parsedRows = parseDelimitedRows(csvText)
        guard !parsedRows.isEmpty else {
            return base
        }

        let colCount = min(maxTableColumns, max(1, parsedRows.map(\.count).max() ?? 1))
        let rawHeaders = parsedRows[0]
        let headers: [String] = (0..<colCount).map { colIdx in
            colIdx < rawHeaders.count ? rawHeaders[colIdx] : "Col \(colIdx + 1)"
        }

        let bodySlice = Array(parsedRows.dropFirst().prefix(maxTableRows))
        let rows: [[String]] = bodySlice.map { row in
            (0..<colCount).map { colIdx in
                colIdx < row.count ? row[colIdx] : ""
            }
        }

        var alignments: [TableColumnAlignment] = []
        for idx in 0..<colCount {
            if idx < base.alignments.count {
                alignments.append(base.alignments[idx])
            } else {
                alignments.append(idx == 0 ? .left : .center)
            }
        }

        var updated = base
        updated.headers = headers
        updated.rows = rows.isEmpty ? [Array(repeating: "", count: colCount)] : rows
        updated.alignments = alignments
        return updated
    }

    public static func generateBooktabsTable(from grid: TableGridData) -> String {
        let colCount = min(maxTableColumns, max(1, grid.headers.count))
        let safeHeaders = (0..<colCount).map { idx -> String in
            let raw = idx < grid.headers.count ? grid.headers[idx] : "Col \(idx + 1)"
            let escaped = AcademicSanitizer.escapeLaTeXText(raw, allowSafeInlineMath: true)
            return grid.boldHeader ? "\\textbf{\(escaped)}" : escaped
        }

        let colSpec = (0..<colCount).map { idx -> String in
            idx < grid.alignments.count ? grid.alignments[idx].rawValue : "c"
        }.joined()

        let bodyRows = Array(grid.rows.prefix(maxTableRows)).map { row -> String in
            let cells = (0..<colCount).map { idx -> String in
                let raw = idx < row.count ? row[idx] : ""
                return AcademicSanitizer.escapeLaTeXText(raw, allowSafeInlineMath: true)
            }
            return "    \(cells.joined(separator: " & ")) \\\\"
        }

        let safeCaption = AcademicSanitizer.escapeLaTeXText(grid.caption, allowSafeInlineMath: true)
        let rawLabel = grid.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLabel = AcademicSanitizer.sanitizeIdentifier(rawLabel, fallback: "tab:table")
        let finalLabel = cleanLabel.hasPrefix("tab:") ? cleanLabel : "tab:\(cleanLabel)"

        var lines: [String] = [
            "\\begin{table}[htbp]",
            "  \\centering"
        ]
        if !safeCaption.isEmpty {
            lines.append("  \\caption{\(safeCaption)}")
        }
        lines.append("  \\label{\(finalLabel)}")
        lines.append("  \\begin{tabular}{@{}\(colSpec)@{}}")
        lines.append("    \\toprule")
        lines.append("    \(safeHeaders.joined(separator: " & ")) \\\\")
        lines.append("    \\midrule")
        if bodyRows.isEmpty {
            lines.append("    " + Array(repeating: "--", count: colCount).joined(separator: " & ") + " \\\\")
        } else {
            lines.append(contentsOf: bodyRows)
        }
        lines.append("    \\bottomrule")
        lines.append("  \\end{tabular}")
        lines.append("\\end{table}")
        return lines.joined(separator: "\n")
    }

    // MARK: - PGFPlots Chart Builder

    public static func generatePGFPlotChart(from config: PGFPlotChartConfig) -> String {
        let rows = parseDelimitedRows(config.csvText)
        var seriesName = "Series 1"
        var dataStartIndex = 0
        if let first = rows.first, first.count >= 2, Double(first[1].trimmingCharacters(in: .whitespaces)) == nil {
            seriesName = AcademicSanitizer.escapeLaTeXText(first[1])
            dataStartIndex = 1
        }

        var points: [(xRaw: String, xNumeric: Double?, y: Double)] = []
        for row in rows.dropFirst(dataStartIndex) where row.count >= 2 {
            let xRaw = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let yRaw = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !xRaw.isEmpty, let yVal = parseFiniteDecimalNumber(yRaw) else { continue }
            let xNumeric = parseFiniteDecimalNumber(xRaw)
            points.append((xRaw: xRaw, xNumeric: xNumeric, y: yVal))
        }

        if points.isEmpty {
            points = [("1", 1.0, 1.0), ("2", 2.0, 2.0), ("3", 3.0, 3.0)]
        }

        let allNumericX = points.allSatisfy { $0.xNumeric != nil }
        let safeTitle = AcademicSanitizer.escapeLaTeXText(config.title, allowSafeInlineMath: true)
        let safeXLabel = AcademicSanitizer.escapeLaTeXText(config.xLabel, allowSafeInlineMath: true)
        let safeYLabel = AcademicSanitizer.escapeLaTeXText(config.yLabel, allowSafeInlineMath: true)
        let safeCaption = AcademicSanitizer.escapeLaTeXText(config.caption, allowSafeInlineMath: true)
        let rawLabel = AcademicSanitizer.sanitizeIdentifier(config.label, fallback: "fig:chart")
        let finalLabel = rawLabel.hasPrefix("fig:") ? rawLabel : "fig:\(rawLabel)"

        var axisOptions: [String] = [
            "width=0.88\\textwidth",
            "height=0.52\\textwidth"
        ]
        if !safeTitle.isEmpty {
            axisOptions.append("title={\(safeTitle)}")
        }
        if !safeXLabel.isEmpty {
            axisOptions.append("xlabel={\(safeXLabel)}")
        }
        if !safeYLabel.isEmpty {
            axisOptions.append("ylabel={\(safeYLabel)}")
        }
        if config.showGrid {
            axisOptions.append("grid=major")
        }
        if config.showLegend {
            axisOptions.append("legend pos=north west")
        }

        let plotModifier: String
        switch config.chartType {
        case .line:
            plotModifier = "+[thick, mark=*]"
        case .bar:
            axisOptions.append("ybar")
            axisOptions.append("bar width=18pt")
            axisOptions.append("enlarge x limits=0.2")
            plotModifier = "+[fill=blue!45, draw=blue!80!black]"
        case .scatter:
            plotModifier = "+[only marks, mark=*, mark size=2.5pt]"
        }

        var symbolicNames: [String] = []
        let coordPairs: [String] = points.map { pt in
            if allNumericX, let xVal = pt.xNumeric {
                let formattedX = formatPlotNumber(xVal)
                let formattedY = formatPlotNumber(pt.y)
                return "(\(formattedX), \(formattedY))"
            } else {
                let safeX = AcademicSanitizer.sanitizeIdentifier(pt.xRaw, fallback: "Item")
                symbolicNames.append(safeX)
                return "(\(safeX), \(formatPlotNumber(pt.y)))"
            }
        }

        if !allNumericX && !symbolicNames.isEmpty {
            axisOptions.append("symbolic x coords={\(symbolicNames.joined(separator: ","))}")
            axisOptions.append("xtick=data")
        }

        var lines: [String] = [
            "\\begin{figure}[htbp]",
            "  \\centering",
            "  \\begin{tikzpicture}",
            "    \\begin{axis}["
        ]
        for (idx, opt) in axisOptions.enumerated() {
            let comma = idx < axisOptions.count - 1 ? "," : ""
            lines.append("      \(opt)\(comma)")
        }
        lines.append("    ]")
        lines.append("      \\addplot\(plotModifier) coordinates {")
        lines.append("        \(coordPairs.joined(separator: " "))")
        lines.append("      };")
        if config.showLegend && !seriesName.isEmpty {
            lines.append("      \\addlegendentry{\(seriesName)}")
        }
        lines.append("    \\end{axis}")
        lines.append("  \\end{tikzpicture}")
        if !safeCaption.isEmpty {
            lines.append("  \\caption{\(safeCaption)}")
        }
        lines.append("  \\label{\(finalLabel)}")
        lines.append("\\end{figure}")
        return lines.joined(separator: "\n")
    }

    // MARK: - Figure & Subfigure Generator

    public static func generateFigureSnippet(from config: FigureInsertConfig) -> String {
        let safePlacement = AcademicSanitizer.sanitizePlacement(config.placement)
        let primaryPath = safeFigureRelativePath(config.primaryRelativePath)
        let widthStr = String(format: "%.2f", min(max(config.widthFraction, 0.25), 1.0))
        let safeCaption = AcademicSanitizer.escapeLaTeXText(config.caption, allowSafeInlineMath: true)
        let rawLabel = AcademicSanitizer.sanitizeIdentifier(config.label, fallback: "fig:figure")
        let finalLabel = rawLabel.hasPrefix("fig:") ? rawLabel : "fig:\(rawLabel)"

        if let secondaryRaw = config.secondaryRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !secondaryRaw.isEmpty {
            let secondaryPath = safeFigureRelativePath(secondaryRaw)
            let subWidth = String(format: "%.2f", min(max(config.widthFraction * 0.48, 0.25), 0.49))
            let capA = AcademicSanitizer.escapeLaTeXText(config.primarySubcaption, allowSafeInlineMath: true)
            let capB = AcademicSanitizer.escapeLaTeXText(config.secondarySubcaption, allowSafeInlineMath: true)
            return """
\\begin{figure}[\(safePlacement)]
  \\centering
  \\begin{subfigure}[b]{\(subWidth)\\textwidth}
    \\centering
    \\includegraphics[width=\\linewidth]{\(primaryPath)}
    \\caption{\(capA)}
    \\label{\(finalLabel)-a}
  \\end{subfigure}
  \\hfill
  \\begin{subfigure}[b]{\(subWidth)\\textwidth}
    \\centering
    \\includegraphics[width=\\linewidth]{\(secondaryPath)}
    \\caption{\(capB)}
    \\label{\(finalLabel)-b}
  \\end{subfigure}
  \\caption{\(safeCaption)}
  \\label{\(finalLabel)}
\\end{figure}
"""
        } else {
            return """
\\begin{figure}[\(safePlacement)]
  \\centering
  \\includegraphics[width=\(widthStr)\\textwidth]{\(primaryPath)}
  \\caption{\(safeCaption)}
  \\label{\(finalLabel)}
\\end{figure}
"""
        }
    }

    // MARK: - Private Parsing & Formatting Helpers

    public static func parseDelimitedRows(_ text: String) -> [[String]] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let rawLines = normalized.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !rawLines.isEmpty else { return [] }

        let delimiter: Character = rawLines[0].contains("\t") ? "\t" : ","
        return rawLines.map { parseCSVLine($0, delimiter: delimiter) }
    }

    private static func parseCSVLine(_ line: String, delimiter: Character) -> [String] {
        var cells: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0

        while i < chars.count {
            let ch = chars[i]
            if ch == "\"" {
                if inQuotes && i + 1 < chars.count && chars[i + 1] == "\"" {
                    current.append("\"")
                    i += 2
                    continue
                }
                inQuotes.toggle()
            } else if ch == delimiter && !inQuotes {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
            i += 1
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func escapeCSVField(_ field: String) -> String {
        let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(",") || trimmed.contains("\"") || trimmed.contains("\n") {
            let doubled = trimmed.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(doubled)\""
        }
        return trimmed
    }

    private static func safeFigureRelativePath(_ raw: String) -> String {
        if let valid = AcademicSanitizer.validatedRelativeAssetPath(raw) {
            return valid
        }
        return "figures/\(AcademicSanitizer.sanitizeFigureFileName(raw))"
    }

    private static func parseFiniteDecimalNumber(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$"#, options: .regularExpression) != nil,
              let value = Double(trimmed),
              value.isFinite else {
            return nil
        }
        return value
    }

    private static func formatPlotNumber(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value.rounded() == value && abs(value) < 1_000_000 {
            return String(Int(value))
        }
        return String(format: "%.4g", value)
    }
}
