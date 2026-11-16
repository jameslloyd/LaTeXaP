import Foundation

public enum AcademicPreflightService {
    public static func analyze(
        source: String,
        bibEntries: [BibEntry],
        diagnostics: [LaTeXDiagnostic] = [],
        documentDirectory: URL? = nil,
        tempFiguresDirectory: URL? = nil,
        stats: AcademicDocumentStats = AcademicDocumentStats(),
        rubricTargets: RubricTargetConfig = RubricTargetConfig()
    ) -> AcademicPreflightReport {
        var items: [AcademicPreflightItem] = []

        // 1. Compilation blockers
        let compileErrors = diagnostics.filter { $0.severity == .error }
        if !compileErrors.isEmpty {
            let first = compileErrors[0]
            items.append(
                AcademicPreflightItem(
                    id: "compile-errors",
                    category: "Hygiene",
                    severity: .blocker,
                    title: "\(compileErrors.count) LaTeX Compilation Error(s)",
                    detail: first.message,
                    line: first.line
                )
            )
        }

        // 2. Unresolved citations (\cite, \parencite, \textcite, etc.)
        let citationUses = BibliographyService.extractCitations(from: source)
        let knownBibKeys = Set(bibEntries.map(\.key))
        var unresolvedCitations: [String] = []
        var seenUnresolvedCiteKeys = Set<String>()

        for use in citationUses where !knownBibKeys.contains(use.key) {
            if seenUnresolvedCiteKeys.insert(use.key).inserted {
                unresolvedCitations.append(use.key)
            }
            items.append(
                AcademicPreflightItem(
                    id: "unresolved-cite-\(use.key)-\(use.line)",
                    category: "Citations",
                    severity: .blocker,
                    title: "Unresolved citation '\(use.key)'",
                    detail: "Line \(use.line): '\(use.key)' was cited, but no matching entry exists in references.bib or \\bibitem.",
                    line: use.line
                )
            )
        }

        // 3. Uncited bibliography entries
        let citedKeys = Set(citationUses.map(\.key))
        var uncitedBibKeys: [String] = []
        for entry in bibEntries where !citedKeys.contains(entry.key) {
            uncitedBibKeys.append(entry.key)
            items.append(
                AcademicPreflightItem(
                    id: "uncited-bib-\(entry.key)",
                    category: "Citations",
                    severity: .warning,
                    title: "Uncited bibliography entry '\(entry.key)'",
                    detail: "'\(entry.title)' is in your bibliography library but never cited in the paper.",
                    line: nil
                )
            )
        }

        // 4. Unresolved cross-references (\ref, \eqref, \cref, etc.)
        let refUses = BibliographyService.extractReferences(from: source)
        let knownLabels = Set(BibliographyService.extractLabels(from: source).map(\.label))
        var unresolvedReferences: [String] = []
        var seenUnresolvedRefs = Set<String>()

        for use in refUses where !knownLabels.contains(use.label) {
            if seenUnresolvedRefs.insert(use.label).inserted {
                unresolvedReferences.append(use.label)
            }
            items.append(
                AcademicPreflightItem(
                    id: "unresolved-ref-\(use.label)-\(use.line)",
                    category: "Cross-Refs",
                    severity: .blocker,
                    title: "Broken cross-reference '\\ref{\(use.label)}'",
                    detail: "Line \(use.line): No matching \\label{\(use.label)} was found in the document.",
                    line: use.line
                )
            )
        }

        // 5. Figure paths & missing figure files
        let figureRefs = extractFigurePaths(from: source)
        var missingFigurePaths: [String] = []
        var seenMissingPaths = Set<String>()

        if !figureRefs.isEmpty {
            let hasGraphicx = source.range(
                of: #"\\usepackage(?:\[[^\]]*\])?\{[^}]*\bgraphicx\b[^}]*\}"#,
                options: .regularExpression
            ) != nil
            let isBeamer = source.range(
                of: #"\\documentclass(?:\[[^\]]*\])?\{beamer\}"#,
                options: .regularExpression
            ) != nil
            if !hasGraphicx && !isBeamer {
                items.append(
                    AcademicPreflightItem(
                        id: "missing-pkg-graphicx",
                        category: "Figures",
                        severity: .blocker,
                        title: "Missing \\usepackage{graphicx} for figures",
                        detail: "\\includegraphics requires the graphicx package in the preamble.",
                        line: figureRefs.first?.line,
                        fixButtonTitle: "Add \\usepackage{graphicx}",
                        fixOperation: .insertPackage(packageName: "graphicx", options: "")
                    )
                )
            }
        }

        for ref in figureRefs {
            let path = ref.path
            if path.hasPrefix("/") || path.hasPrefix("~") || path.contains("..") || path.contains("\\") {
                if seenMissingPaths.insert(path).inserted {
                    missingFigurePaths.append(path)
                }
                items.append(
                    AcademicPreflightItem(
                        id: "nonportable-fig-\(ref.line)-\(path)",
                        category: "Figures",
                        severity: .warning,
                        title: "Non-portable figure path on line \(ref.line)",
                        detail: "'\(path)' is an absolute or traversing path. Move images into a relative figures/ folder before submitting.",
                        line: ref.line
                    )
                )
            } else if !figureExists(relativePath: path, documentDirectory: documentDirectory, tempFiguresDirectory: tempFiguresDirectory) {
                if seenMissingPaths.insert(path).inserted {
                    missingFigurePaths.append(path)
                }
                items.append(
                    AcademicPreflightItem(
                        id: "missing-fig-\(ref.line)-\(path)",
                        category: "Figures",
                        severity: .blocker,
                        title: "Missing figure file '\(path)'",
                        detail: "Line \(ref.line): Image asset '\(path)' could not be found in the project directory or TempFigures staging folder.",
                        line: ref.line
                    )
                )
            }
        }

        // 6. BibLaTeX command compatibility check
        let usesBibLaTeXCommands = source.range(
            of: #"\\(?:parencite|textcite|autocite|footcite|printbibliography)\b"#,
            options: .regularExpression
        ) != nil
        if usesBibLaTeXCommands {
            let hasBibLaTeX = source.range(
                of: #"\\usepackage(?:\[[^\]]*\])?\{[^}]*\bbiblatex\b[^}]*\}"#,
                options: .regularExpression
            ) != nil
            if !hasBibLaTeX {
                items.append(
                    AcademicPreflightItem(
                        id: "missing-pkg-biblatex",
                        category: "Citations",
                        severity: .blocker,
                        title: "Missing \\usepackage{biblatex}",
                        detail: "Commands like \\parencite, \\textcite, or \\printbibliography require biblatex.",
                        line: nil,
                        fixButtonTitle: "Add \\usepackage{biblatex}",
                        fixOperation: .insertPackage(packageName: "biblatex", options: "style=authoryear,backend=bibtex")
                    )
                )
            }
        }

        // 7. Layout Overfull \hbox warnings
        for diag in diagnostics where diag.message.contains("Overfull \\hbox") {
            items.append(
                AcademicPreflightItem(
                    id: "overfull-\(diag.line ?? 0)-\(diag.message.hashValue)",
                    category: "Hygiene",
                    severity: .warning,
                    title: "Margin overflow (Overfull \\hbox)",
                    detail: diag.message,
                    line: diag.line
                )
            )
        }

        // 8. Rubric Budget checks
        if let targetWords = rubricTargets.targetProseWords, targetWords > 0, stats.proseWordCount > targetWords {
            let over = stats.proseWordCount - targetWords
            items.append(
                AcademicPreflightItem(
                    id: "budget-words",
                    category: "Budget",
                    severity: .warning,
                    title: "Prose word count over rubric limit",
                    detail: "\(stats.proseWordCount) words written (\(over) words over your \(targetWords)-word target).",
                    line: nil
                )
            )
        }
        if let maxAbstract = rubricTargets.maxAbstractWords, maxAbstract > 0, stats.abstractWordCount > maxAbstract {
            let over = stats.abstractWordCount - maxAbstract
            items.append(
                AcademicPreflightItem(
                    id: "budget-abstract",
                    category: "Budget",
                    severity: .warning,
                    title: "Abstract exceeds word limit",
                    detail: "Abstract has \(stats.abstractWordCount) words (\(over) over the \(maxAbstract)-word limit).",
                    line: nil
                )
            )
        }
        if let maxPages = rubricTargets.maxPageCount, maxPages > 0, stats.pageCount > maxPages {
            let over = stats.pageCount - maxPages
            items.append(
                AcademicPreflightItem(
                    id: "budget-pages",
                    category: "Budget",
                    severity: .warning,
                    title: "Page count exceeds rubric maximum",
                    detail: "Document is \(stats.pageCount) pages (\(over) page(s) over the \(maxPages)-page limit).",
                    line: nil
                )
            )
        }

        let hasBlocker = items.contains { $0.severity == .blocker }
        return AcademicPreflightReport(
            items: items,
            unresolvedCitations: unresolvedCitations,
            unresolvedReferences: unresolvedReferences,
            uncitedBibKeys: uncitedBibKeys,
            missingFigurePaths: missingFigurePaths,
            isSubmissionReady: !hasBlocker
        )
    }

    public static func extractFigurePaths(from source: String) -> [(path: String, line: Int)] {
        var results: [(path: String, line: Int)] = []
        let lines = source.components(separatedBy: .newlines)
        guard let regex = try? NSRegularExpression(pattern: #"\\includegraphics(?:\[[^\]]*\])?\{([^}]+)\}"#) else {
            return results
        }
        for (idx, rawLine) in lines.enumerated() {
            let line: String
            if let commentRange = rawLine.range(of: #"(?<!\\)%.*$"#, options: .regularExpression) {
                line = String(rawLine[..<commentRange.lowerBound])
            } else {
                line = rawLine
            }
            let ns = line as NSString
            for m in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges >= 2 {
                let path = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    results.append((path: path, line: idx + 1))
                }
            }
        }
        return results
    }

    private static func figureExists(
        relativePath: String,
        documentDirectory: URL?,
        tempFiguresDirectory: URL?
    ) -> Bool {
        guard let validRel = AcademicSanitizer.validatedRelativeAssetPath(relativePath) else {
            return false
        }
        let fm = FileManager.default
        let candidateExtensions = ["", ".png", ".jpg", ".jpeg", ".pdf", ".tiff", ".eps"]

        var searchRoots: [URL] = []
        if let documentDirectory {
            searchRoots.append(documentDirectory)
        }
        if let tempFiguresDirectory {
            // `figures/foo.png` maps to `<tempFiguresDirectory>/foo.png`
            searchRoots.append(tempFiguresDirectory.deletingLastPathComponent())
        }

        for root in searchRoots {
            for ext in candidateExtensions {
                let candidateRel = (ext.isEmpty || !(validRel as NSString).pathExtension.isEmpty) ? validRel : validRel + ext
                let candidateURL = root.appendingPathComponent(candidateRel).standardizedFileURL
                if fm.fileExists(atPath: candidateURL.path) {
                    return true
                }
            }
        }

        // Direct fallback check inside tempFiguresDirectory by leaf filename if relativePath starts with "figures/"
        if let tempFiguresDirectory, validRel.hasPrefix("figures/") {
            let leaf = String(validRel.dropFirst("figures/".count))
            for ext in candidateExtensions {
                let candidateLeaf = (ext.isEmpty || !(leaf as NSString).pathExtension.isEmpty) ? leaf : leaf + ext
                let candidateURL = tempFiguresDirectory.appendingPathComponent(candidateLeaf).standardizedFileURL
                if fm.fileExists(atPath: candidateURL.path) {
                    return true
                }
            }
        }

        return false
    }
}
