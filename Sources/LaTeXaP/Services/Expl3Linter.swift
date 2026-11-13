import Foundation

public struct DocumentStats: Equatable, Sendable {
    public let wordCount: Int
    public let charCount: Int
    public let mathCount: Int
    public let expl3SymbolCount: Int

    public init(wordCount: Int = 0, charCount: Int = 0, mathCount: Int = 0, expl3SymbolCount: Int = 0) {
        self.wordCount = wordCount
        self.charCount = charCount
        self.mathCount = mathCount
        self.expl3SymbolCount = expl3SymbolCount
    }
}

public enum Expl3Linter {
    private static let validVarSuffixes: Set<String> = [
        "tl", "str", "clist", "seq", "prop", "int", "fp", "dim", "skip",
        "muskip", "box", "coffin", "ior", "iow", "bool", "regex", "bitset", " fparray", "intarray"
    ]

    /// Runs instant static analysis on `\ExplSyntaxOn ... \ExplSyntaxOff` regions to catch
    /// LaTeX3 variable naming violations and function signature arity mismatches.
    public static func lint(source: String) -> [LaTeXDiagnostic] {
        var diagnostics: [LaTeXDiagnostic] = []
        let lines = source.components(separatedBy: .newlines)

        var inExpl3 = false
        var expl3StartLine: Int?

        let varDeclRegex = try? NSRegularExpression(
            pattern: #"\\(tl|str|clist|seq|prop|int|fp|dim|skip|muskip|box|coffin|bool|regex)_new:N\s*\{?(\\[a-zA-Z0-9_@]+)\}?"#
        )
        let csDefRegex = try? NSRegularExpression(
            pattern: #"\\cs_(?:new|set)(?:_protected|_nopar)?_?(?:eq)?:\w+\s*\{?(\\[a-zA-Z0-9_@]+):([a-zA-Z]*)\}?\s*([#0-9\s]*)"#
        )

        for (idx, rawLine) in lines.enumerated() {
            let lineNum = idx + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("%") { continue }

            // Strip inline trailing comment
            let codeOnly: String
            if let commentRange = rawLine.range(of: #"(?<!\\)%.*$"#, options: .regularExpression) {
                codeOnly = String(rawLine[..<commentRange.lowerBound])
            } else {
                codeOnly = rawLine
            }

            if codeOnly.contains("\\ExplSyntaxOn") {
                inExpl3 = true
                expl3StartLine = lineNum
            }
            if codeOnly.contains("\\ExplSyntaxOff") {
                inExpl3 = false
                expl3StartLine = nil
            }

            guard inExpl3 else { continue }

            let nsLine = codeOnly as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)

            // 1. Check expl3 variable declaration conventions: \tl_new:N \l_module_name_tl
            if let match = varDeclRegex?.firstMatch(in: codeOnly, range: fullRange), match.numberOfRanges >= 3 {
                let declaredType = nsLine.substring(with: match.range(at: 1))
                let varName = nsLine.substring(with: match.range(at: 2))

                let hasScopePrefix = varName.hasPrefix("\\l_") || varName.hasPrefix("\\g_") || varName.hasPrefix("\\c_")
                let hasMatchingSuffix = varName.hasSuffix("_\(declaredType)")

                if !hasScopePrefix || !hasMatchingSuffix {
                    let expectedExample = "\\l_module_name_\(declaredType)"
                    diagnostics.append(
                        LaTeXDiagnostic(
                            line: lineNum,
                            severity: .warning,
                            message: "expl3 Lint: Variable '\(varName)' should start with \\l_, \\g_, or \\c_ and end with '_\(declaredType)' (e.g., '\(expectedExample)')."
                        )
                    )
                }
            }

            // 2. Check \cs_new:Npn \module_func:nn #1#2 signature arity vs parameter tokens
            if let match = csDefRegex?.firstMatch(in: codeOnly, range: fullRange), match.numberOfRanges >= 4 {
                let funcBase = nsLine.substring(with: match.range(at: 1))
                let argSpec = nsLine.substring(with: match.range(at: 2))
                let paramPart = nsLine.substring(with: match.range(at: 3))

                // Only check when parameters or opening brace appear on the same line or paramPart has # tokens
                let expectedCount = argSpec.count
                let paramDigits = paramPart.split(separator: "#").compactMap { Int($0.trimmingCharacters(in: .whitespaces).prefix(1)) }
                let highestParam = paramDigits.max() ?? 0

                if !paramDigits.isEmpty && highestParam != expectedCount {
                    diagnostics.append(
                        LaTeXDiagnostic(
                            line: lineNum,
                            severity: .warning,
                            message: "expl3 Lint: Function '\(funcBase):\(argSpec)' declares \(expectedCount) argument(s) in signature ':\(argSpec)', but parameter list specifies #\((1...highestParam).map(String.init).joined(separator: "#"))."
                        )
                    )
                }
            }
        }

        if inExpl3, let start = expl3StartLine {
            diagnostics.append(
                LaTeXDiagnostic(
                    line: start,
                    severity: .warning,
                    message: "expl3 Lint: Unclosed \\ExplSyntaxOn block (missing matching \\ExplSyntaxOff)."
                )
            )
        }

        return diagnostics
    }

    /// Computes live prose word count, character count, math block count, and expl3 symbol count.
    public static func computeStatistics(source: String) -> DocumentStats {
        guard !source.isEmpty else { return DocumentStats() }

        // Extract body after \begin{document} if present so preamble macros don't inflate prose word count
        let bodySlice: String
        if let beginRange = source.range(of: "\\begin{document}") {
            let afterBegin = source[beginRange.upperBound...]
            if let endRange = afterBegin.range(of: "\\end{document}") {
                bodySlice = String(afterBegin[..<endRange.lowerBound])
            } else {
                bodySlice = String(afterBegin)
            }
        } else {
            bodySlice = source
        }

        // Count math environments ($...$, \[...\], \begin{equation|align|gather})
        let mathRegex = try? NSRegularExpression(pattern: #"(\$[^$\n]+\$|\\\[[\s\S]*?\\\]|\\begin\{(?:equation|align|gather)\*?\})"#)
        let nsBody = bodySlice as NSString
        let mathCount = mathRegex?.numberOfMatches(in: bodySlice, range: NSRange(location: 0, length: nsBody.length)) ?? 0

        // Count expl3 symbols in entire source
        let expl3Regex = try? NSRegularExpression(pattern: #"\\[a-zA-Z@]+_[a-zA-Z0-9_@]+(?::[a-zA-Z]*)?"#)
        let nsFull = source as NSString
        let expl3Count = expl3Regex?.numberOfMatches(in: source, range: NSRange(location: 0, length: nsFull.length)) ?? 0

        // Strip comments and LaTeX control sequences to estimate prose word count
        var stripped = bodySlice
        if let commentRegex = try? NSRegularExpression(pattern: #"(?<!\\)%.*$"#, options: [.anchorsMatchLines]) {
            stripped = commentRegex.stringByReplacingMatches(in: stripped, range: NSRange(location: 0, length: (stripped as NSString).length), withTemplate: " ")
        }
        if let cmdRegex = try? NSRegularExpression(pattern: #"\\[a-zA-Z@_*:]+"#) {
            stripped = cmdRegex.stringByReplacingMatches(in: stripped, range: NSRange(location: 0, length: (stripped as NSString).length), withTemplate: " ")
        }

        let words = stripped
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 || $0.first?.isLetter == true }

        return DocumentStats(
            wordCount: words.count,
            charCount: source.count,
            mathCount: mathCount,
            expl3SymbolCount: expl3Count
        )
    }
}
