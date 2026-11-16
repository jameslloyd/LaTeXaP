import Foundation

// MARK: - Bibliography, Citations & Style Models

public enum CitationCommandStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case cite
    case parencite
    case textcite
    case autocite
    case footcite

    public var id: String { rawValue }

    public var command: String { "\\\(rawValue)" }

    public var displayName: String {
        switch self {
        case .cite:
            return "\\cite (Standard)"
        case .parencite:
            return "\\parencite (Author, Year)"
        case .textcite:
            return "\\textcite (In-Text)"
        case .autocite:
            return "\\autocite (Style-Auto)"
        case .footcite:
            return "\\footcite (Footnote)"
        }
    }

    public func format(key: String, pageLocator: String? = nil) -> String {
        let safeKey = AcademicSanitizer.sanitizeIdentifier(key, fallback: "citation")
        let safeLocator = AcademicSanitizer.sanitizeCitationLocator(pageLocator ?? "")
        if safeLocator.isEmpty {
            return "\(command){\(safeKey)}"
        } else {
            return "\(command)[\(safeLocator)]{\(safeKey)}"
        }
    }
}

public enum BibliographyStylePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case apa
    case ieee
    case acm
    case mla
    case chicago
    case nature

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .apa: return "APA (7th ed.)"
        case .ieee: return "IEEE"
        case .acm: return "ACM"
        case .mla: return "MLA"
        case .chicago: return "Chicago"
        case .nature: return "Nature"
        }
    }

    public var biblatexStyleOption: String {
        switch self {
        case .apa: return "authoryear"
        case .ieee: return "ieee"
        case .acm: return "numeric"
        case .mla: return "mla"
        case .chicago: return "chicago-authordate"
        case .nature: return "nature"
        }
    }

    public var description: String {
        switch self {
        case .apa:
            return "Author-year citations and reference formatting for Psychology, Education, and Social Sciences."
        case .ieee:
            return "Bracketed numeric citations [1] standard in Electrical Engineering and Computer Science."
        case .acm:
            return "Association for Computing Machinery reference style for CS conferences and journals."
        case .mla:
            return "Modern Language Association author-page format for Humanities and Literature."
        case .chicago:
            return "Chicago Manual of Style author-date citations for History and Humanities."
        case .nature:
            return "Superscript numbered citations used in Nature and Natural Sciences journals."
        }
    }
}

// MARK: - Paper Setup Wizard & Rubric Budget Models

public enum AcademicPaperSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case letterpaper
    case a4paper

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .letterpaper: return "US Letter (8.5 × 11 in)"
        case .a4paper: return "A4 (210 × 297 mm)"
        }
    }
}

public struct PaperSetupConfig: Equatable, Sendable {
    public var templateId: String
    public var title: String
    public var author: String
    public var institution: String
    public var courseOrVenue: String
    public var paperSize: AcademicPaperSize
    public var baseFontSizePt: Int
    public var doubleSpacing: Bool
    public var anonymizedBlindReview: Bool
    public var bibliographyStyle: BibliographyStylePreset

    public init(
        templateId: String = "apa7-student",
        title: String = "",
        author: String = "",
        institution: String = "",
        courseOrVenue: String = "",
        paperSize: AcademicPaperSize = .letterpaper,
        baseFontSizePt: Int = 12,
        doubleSpacing: Bool = false,
        anonymizedBlindReview: Bool = false,
        bibliographyStyle: BibliographyStylePreset = .apa
    ) {
        self.templateId = templateId
        self.title = title
        self.author = author
        self.institution = institution
        self.courseOrVenue = courseOrVenue
        self.paperSize = paperSize
        self.baseFontSizePt = min(max(baseFontSizePt, 10), 12)
        self.doubleSpacing = doubleSpacing
        self.anonymizedBlindReview = anonymizedBlindReview
        self.bibliographyStyle = bibliographyStyle
    }
}

public struct RubricTargetConfig: Codable, Equatable, Sendable {
    public var targetProseWords: Int?
    public var maxPageCount: Int?
    public var maxAbstractWords: Int?
    public var studentModeHideExpl3: Bool

    public init(
        targetProseWords: Int? = nil,
        maxPageCount: Int? = nil,
        maxAbstractWords: Int? = nil,
        studentModeHideExpl3: Bool = false
    ) {
        self.targetProseWords = targetProseWords
        self.maxPageCount = maxPageCount
        self.maxAbstractWords = maxAbstractWords
        self.studentModeHideExpl3 = studentModeHideExpl3
    }
}

public struct AcademicDocumentStats: Equatable, Sendable {
    public var proseWordCount: Int
    public var abstractWordCount: Int
    public var referenceCount: Int
    public var figureCount: Int
    public var tableCount: Int
    public var pageCount: Int
    public var estimatedReadingMinutes: Int

    public init(
        proseWordCount: Int = 0,
        abstractWordCount: Int = 0,
        referenceCount: Int = 0,
        figureCount: Int = 0,
        tableCount: Int = 0,
        pageCount: Int = 0,
        estimatedReadingMinutes: Int = 0
    ) {
        self.proseWordCount = proseWordCount
        self.abstractWordCount = abstractWordCount
        self.referenceCount = referenceCount
        self.figureCount = figureCount
        self.tableCount = tableCount
        self.pageCount = pageCount
        self.estimatedReadingMinutes = estimatedReadingMinutes
    }
}

// MARK: - Error Demystifier & Academic Pre-Flight Models

public enum AcademicFixOperation: Equatable, Sendable {
    case replaceLine(lineNumber: Int, originalSubstring: String, replacement: String)
    case insertPackage(packageName: String, options: String)
    case wrapLineInMath(lineNumber: Int)
    case appendMissingBrace(lineNumber: Int)
    case insertRawSnippet(snippet: String)
}

public struct DemystifiedDiagnostic: Identifiable, Equatable, Sendable {
    public let id: String
    public let line: Int?
    public let severity: DiagnosticSeverity
    public let shortTitle: String
    public let explanation: String
    public let rawMessage: String
    public let fixButtonTitle: String?
    public let fixOperation: AcademicFixOperation?

    public init(
        id: String,
        line: Int?,
        severity: DiagnosticSeverity,
        shortTitle: String,
        explanation: String,
        rawMessage: String,
        fixButtonTitle: String? = nil,
        fixOperation: AcademicFixOperation? = nil
    ) {
        self.id = id
        self.line = line
        self.severity = severity
        self.shortTitle = shortTitle
        self.explanation = explanation
        self.rawMessage = rawMessage
        self.fixButtonTitle = fixButtonTitle
        self.fixOperation = fixOperation
    }
}

public enum PreflightSeverity: String, Codable, Sendable {
    case pass
    case warning
    case blocker
}

public struct AcademicPreflightItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let category: String
    public let severity: PreflightSeverity
    public let title: String
    public let detail: String
    public let line: Int?
    public let fixButtonTitle: String?
    public let fixOperation: AcademicFixOperation?

    public init(
        id: String,
        category: String,
        severity: PreflightSeverity,
        title: String,
        detail: String,
        line: Int? = nil,
        fixButtonTitle: String? = nil,
        fixOperation: AcademicFixOperation? = nil
    ) {
        self.id = id
        self.category = category
        self.severity = severity
        self.title = title
        self.detail = detail
        self.line = line
        self.fixButtonTitle = fixButtonTitle
        self.fixOperation = fixOperation
    }
}

public struct AcademicPreflightReport: Equatable, Sendable {
    public let items: [AcademicPreflightItem]
    public let unresolvedCitations: [String]
    public let unresolvedReferences: [String]
    public let uncitedBibKeys: [String]
    public let missingFigurePaths: [String]
    public let isSubmissionReady: Bool

    public init(
        items: [AcademicPreflightItem] = [],
        unresolvedCitations: [String] = [],
        unresolvedReferences: [String] = [],
        uncitedBibKeys: [String] = [],
        missingFigurePaths: [String] = [],
        isSubmissionReady: Bool = true
    ) {
        self.items = items
        self.unresolvedCitations = unresolvedCitations
        self.unresolvedReferences = unresolvedReferences
        self.uncitedBibKeys = uncitedBibKeys
        self.missingFigurePaths = missingFigurePaths
        self.isSubmissionReady = isSubmissionReady
    }

    public static let empty = AcademicPreflightReport()
}

// MARK: - Visual Spreadsheet Table, pgfplots Chart & Figure Models

public enum TableColumnAlignment: String, Codable, CaseIterable, Sendable {
    case left = "l"
    case center = "c"
    case right = "r"

    public var displayName: String {
        switch self {
        case .left: return "L"
        case .center: return "C"
        case .right: return "R"
        }
    }
}

public struct TableGridData: Equatable, Sendable {
    public var headers: [String]
    public var rows: [[String]]
    public var alignments: [TableColumnAlignment]
    public var boldHeader: Bool
    public var caption: String
    public var label: String

    public init(
        headers: [String] = ["Method", "Metric", "Score"],
        rows: [[String]] = [
            ["Baseline", "Accuracy", "84.2%"],
            ["Proposed", "Accuracy", "91.6%"]
        ],
        alignments: [TableColumnAlignment] = [.left, .center, .right],
        boldHeader: Bool = true,
        caption: String = "Empirical performance comparison.",
        label: String = "tab:comparison"
    ) {
        self.headers = headers
        self.rows = rows
        self.alignments = alignments
        self.boldHeader = boldHeader
        self.caption = caption
        self.label = label
    }
}

public enum PGFPlotChartType: String, Codable, CaseIterable, Identifiable, Sendable {
    case line
    case bar
    case scatter

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .line: return "Line Plot"
        case .bar: return "Bar Chart"
        case .scatter: return "Scatter Plot"
        }
    }
}

public struct PGFPlotChartConfig: Equatable, Sendable {
    public var chartType: PGFPlotChartType
    public var title: String
    public var xLabel: String
    public var yLabel: String
    public var csvText: String
    public var showGrid: Bool
    public var showLegend: Bool
    public var caption: String
    public var label: String

    public init(
        chartType: PGFPlotChartType = .line,
        title: String = "Model Convergence",
        xLabel: String = "Epoch",
        yLabel: String = "Validation Loss",
        csvText: String = "x, y\n1, 1.42\n2, 0.94\n3, 0.63\n4, 0.45\n5, 0.34",
        showGrid: Bool = true,
        showLegend: Bool = true,
        caption: String = "Validation loss across training epochs.",
        label: String = "fig:convergence"
    ) {
        self.chartType = chartType
        self.title = title
        self.xLabel = xLabel
        self.yLabel = yLabel
        self.csvText = csvText
        self.showGrid = showGrid
        self.showLegend = showLegend
        self.caption = caption
        self.label = label
    }
}

public struct FigureInsertConfig: Equatable, Sendable {
    public var primaryRelativePath: String
    public var secondaryRelativePath: String?
    public var widthFraction: Double
    public var placement: String
    public var caption: String
    public var label: String
    public var primarySubcaption: String
    public var secondarySubcaption: String

    public init(
        primaryRelativePath: String = "figures/figure.png",
        secondaryRelativePath: String? = nil,
        widthFraction: Double = 0.75,
        placement: String = "htbp",
        caption: String = "Experimental results overview.",
        label: String = "fig:overview",
        primarySubcaption: String = "Condition A",
        secondarySubcaption: String = "Condition B"
    ) {
        self.primaryRelativePath = primaryRelativePath
        self.secondaryRelativePath = secondaryRelativePath
        self.widthFraction = min(max(widthFraction, 0.25), 1.0)
        self.placement = placement
        self.caption = caption
        self.label = label
        self.primarySubcaption = primarySubcaption
        self.secondarySubcaption = secondarySubcaption
    }
}

// MARK: - Caret-Accurate Insertion, Spellcheck & Submission Export Models

public struct EditorInsertionRequest: Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let cursorBacktrackOffset: Int

    public init(id: UUID = UUID(), text: String, cursorBacktrackOffset: Int = 0) {
        self.id = id
        self.text = text
        self.cursorBacktrackOffset = cursorBacktrackOffset
    }
}

public struct SpellingIssue: Identifiable, Equatable, Sendable {
    public let id: String
    public let word: String
    public let line: Int
    public let nsRange: NSRange
    public let suggestions: [String]

    public init(id: String? = nil, word: String, line: Int, nsRange: NSRange, suggestions: [String]) {
        self.id = id ?? "\(nsRange.location)-\(nsRange.length)-\(word)"
        self.word = word
        self.line = line
        self.nsRange = nsRange
        self.suggestions = suggestions
    }
}

public struct SubmissionExportResult: Equatable, Sendable {
    public let zipURL: URL
    public let includedFiles: [String]
    public let preflightWarnings: [String]
    public let compiledCleanly: Bool

    public init(
        zipURL: URL,
        includedFiles: [String],
        preflightWarnings: [String],
        compiledCleanly: Bool
    ) {
        self.zipURL = zipURL
        self.includedFiles = includedFiles
        self.preflightWarnings = preflightWarnings
        self.compiledCleanly = compiledCleanly
    }
}

// MARK: - Shared Security & LaTeX Text Sanitization Helpers

public enum AcademicSanitizer {
    private static let dangerousCommandPattern = #"\\(?:write18|immediate|openout|newwrite|catcode|input|include|@@input|verbatiminput|lstinputlisting|ShellEscape|pdffilemoddate|directlua)\b"#

    /// Strips dangerous TeX command invocations and normalizes arbitrary prose/metadata into
    /// safe LaTeX text with special characters escaped (`&`, `%`, `$`, `#`, `_`, `{`, `}`, `~`, `^`, `\`).
    public static func escapeLaTeXText(_ raw: String, allowSafeInlineMath: Bool = false) -> String {
        var cleaned = stripControlCharacters(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Neutralize dangerous primitive TeX commands before escaping
        if let regex = try? NSRegularExpression(pattern: dangerousCommandPattern, options: [.caseInsensitive]) {
            let ns = cleaned as NSString
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(location: 0, length: ns.length),
                withTemplate: ""
            )
        }

        if allowSafeInlineMath, containsBalancedSimpleMath(cleaned) {
            return escapeMixedMathAndProse(cleaned)
        }
        return escapePlainFragment(cleaned)
    }

    /// Sanitizes external metadata (CrossRef, arXiv, ISBN) by stripping TeX backslashes/braces
    /// and escaping metacharacters so external strings cannot alter TeX parser state.
    public static func sanitizeExternalMetadata(_ raw: String, fallback: String = "") -> String {
        let noControls = stripControlCharacters(raw)
        var stripped = ""
        for scalar in noControls.unicodeScalars {
            if scalar == "\\" || scalar == "{" || scalar == "}" {
                continue
            }
            stripped.unicodeScalars.append(scalar)
        }
        let escaped = escapePlainFragment(stripped.trimmingCharacters(in: .whitespacesAndNewlines))
        return escaped.isEmpty ? fallback : escaped
    }

    /// Sanitizes citation keys, `\label{...}` keys, and identifiers to `[a-zA-Z0-9_:-]`.
    public static func sanitizeIdentifier(_ raw: String, fallback: String = "item") -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = ""
        for scalar in trimmed.unicodeScalars {
            if (scalar.value >= 65 && scalar.value <= 90) ||
               (scalar.value >= 97 && scalar.value <= 122) ||
               (scalar.value >= 48 && scalar.value <= 57) ||
               scalar == "_" || scalar == ":" || scalar == "-" || scalar == "." {
                out.unicodeScalars.append(scalar)
            } else if scalar == " " {
                out.append("-")
            }
        }
        // Disallow path-like dots or empty strings
        while out.contains("..") {
            out = out.replacingOccurrences(of: "..", with: ".")
        }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: ".-:"))
        return out.isEmpty ? fallback : out
    }

    /// Sanitizes `[locator]` text inside `\cite[locator]{key}` or `\parencite[locator]{key}`.
    public static func sanitizeCitationLocator(_ raw: String) -> String {
        var forbidden = CharacterSet(charactersIn: "{}\\%$\r\n#&~^_[]\t\0")
        forbidden.formUnion(.controlCharacters)
        return String(raw.unicodeScalars.filter { !forbidden.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validates and sanitizes a relative figure filename (never allows directory traversal or slashes).
    public static func sanitizeFigureFileName(_ raw: String, defaultExtension: String = "png") -> String {
        let leaf = (raw as NSString).lastPathComponent
        let url = URL(fileURLWithPath: leaf)
        let ext = sanitizeIdentifier(url.pathExtension.lowercased(), fallback: defaultExtension)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ":", with: "")
        let stemRaw = url.deletingPathExtension().lastPathComponent
        let safeStem = FontLibraryService.sanitizeBaseFileName(stemRaw)
        let allowedExts: Set<String> = ["png", "jpg", "jpeg", "pdf", "tiff", "tif", "eps", "svg"]
        let finalExt = allowedExts.contains(ext) ? ext : defaultExtension
        return "\(safeStem).\(finalExt)"
    }

    /// Validates a relative path under a staging directory (`figures/foo.png`, `references.bib`, etc.).
    /// Rejects absolute paths, `..`, backslashes, colons, leading dots, or control characters.
    public static func validatedRelativeAssetPath(_ raw: String, allowedPrefixes: [String]? = nil) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("\\"),
              !trimmed.contains(".."),
              !trimmed.contains("\\"),
              !trimmed.contains(":"),
              !trimmed.contains("\0") else {
            return nil
        }
        let hasControl = trimmed.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        guard !hasControl else { return nil }

        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }

        if let allowedPrefixes, !allowedPrefixes.isEmpty {
            let matchesPrefix = allowedPrefixes.contains { prefix in
                trimmed == prefix || trimmed.hasPrefix(prefix + "/")
            }
            guard matchesPrefix else { return nil }
        }
        return components.joined(separator: "/")
    }

    public static func sanitizePlacement(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn: "htbpH!")
        let filtered = String(raw.unicodeScalars.filter { allowed.contains($0) })
        return filtered.isEmpty ? "htbp" : String(filtered.prefix(5))
    }

    private static func stripControlCharacters(_ input: String) -> String {
        String(input.unicodeScalars.filter { scalar in
            if scalar == " " { return true }
            if scalar == "\n" || scalar == "\r" || scalar == "\t" { return false }
            return !CharacterSet.controlCharacters.contains(scalar)
        })
    }

    private static func escapePlainFragment(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count + 8)
        for ch in text {
            switch ch {
            case "\\": result.append("\\textbackslash{}")
            case "{": result.append("\\{")
            case "}": result.append("\\}")
            case "&": result.append("\\&")
            case "%": result.append("\\%")
            case "$": result.append("\\$")
            case "#": result.append("\\#")
            case "_": result.append("\\_")
            case "~": result.append("\\textasciitilde{}")
            case "^": result.append("\\textasciicircum{}")
            default: result.append(ch)
            }
        }
        return result
    }

    private static let safeMathCommands: Set<String> = [
        "frac", "dfrac", "tfrac", "sqrt", "sum", "prod", "int", "lim",
        "sin", "cos", "tan", "log", "ln", "exp", "min", "max", "sup", "inf", "arg",
        "alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta", "eta",
        "theta", "vartheta", "iota", "kappa", "lambda", "mu", "nu", "xi",
        "pi", "rho", "sigma", "tau", "upsilon", "phi", "varphi", "chi", "psi", "omega",
        "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma", "Phi", "Psi", "Omega",
        "cdot", "times", "pm", "mp", "leq", "le", "geq", "ge", "neq", "approx", "equiv", "sim",
        "infty", "partial", "nabla", "mathbb", "mathcal", "mathrm", "mathbf", "text",
        "left", "right", "bar", "hat", "tilde", "vec", "dots", "ldots", "cdots",
        "to", "rightarrow", "leftarrow", "Rightarrow", "forall", "exists", "in", "notin", "subset", "cup", "cap"
    ]

    private static func containsBalancedSimpleMath(_ text: String) -> Bool {
        let dollarCount = text.filter { $0 == "$" }.count
        guard dollarCount >= 2, dollarCount % 2 == 0 else { return false }

        let parts = text.split(separator: "$", omittingEmptySubsequences: false).map(String.init)
        for (idx, part) in parts.enumerated() where idx % 2 == 1 {
            guard !part.isEmpty else { return false }
            guard isSafeMathSegment(part) else { return false }
        }
        return true
    }

    private static func isSafeMathSegment(_ segment: String) -> Bool {
        var braceDepth = 0
        let chars = Array(segment)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\\" {
                i += 1
                guard i < chars.count else { return false }
                if chars[i].isLetter {
                    var cmd = ""
                    while i < chars.count && chars[i].isLetter {
                        cmd.append(chars[i])
                        i += 1
                    }
                    guard safeMathCommands.contains(cmd) else {
                        return false
                    }
                    continue
                } else if chars[i] == "," || chars[i] == ";" || chars[i] == " " || chars[i] == "|" {
                    i += 1
                    continue
                } else {
                    // Disallow arbitrary non-letter escapes such as \\, \{, \}, \@ inside sanitized inline math
                    return false
                }
            } else if ch == "{" {
                braceDepth += 1
            } else if ch == "}" {
                braceDepth -= 1
                if braceDepth < 0 {
                    return false
                }
            }
            i += 1
        }
        return braceDepth == 0
    }

    private static func escapeMixedMathAndProse(_ text: String) -> String {
        let parts = text.split(separator: "$", omittingEmptySubsequences: false).map(String.init)
        var out = ""
        for (idx, part) in parts.enumerated() {
            if idx % 2 == 0 {
                out.append(escapePlainFragment(part))
            } else {
                // Segment already validated by isSafeMathSegment (balanced braces, allowlisted commands only)
                let safeMath = part
                    .replacingOccurrences(of: "&", with: "\\&")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "#", with: "\\#")
                out.append("$\(safeMath)$")
            }
        }
        return out
    }
}
