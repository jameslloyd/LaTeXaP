import AppKit
import Foundation

public enum LaTeXSpellCheckService {
    private static let excludedEnvironments: [String] = [
        "equation", "equation\\*",
        "align", "align\\*",
        "gather", "gather\\*",
        "multline", "multline\\*",
        "flalign", "flalign\\*",
        "alignat", "alignat\\*",
        "eqnarray", "eqnarray\\*",
        "displaymath", "math",
        "lstlisting", "minted",
        "verbatim", "verbatim\\*",
        "tikzpicture", "pgfpicture", "axis",
        "pycode", "python",
        "thebibliography",
        "filecontents", "filecontents\\*",
        "cases", "pmatrix", "bmatrix", "vmatrix"
    ]

    private static let structuralCommands: [String] = [
        "cite", "parencite", "textcite", "autocite", "footcite",
        "citep", "citet", "citealp", "citealt", "nocite",
        "ref", "eqref", "cref", "Cref", "autoref", "pageref", "vref",
        "label", "usepackage", "RequirePackage", "documentclass",
        "includegraphics", "input", "include", "addbibresource",
        "bibliography", "bibliographystyle",
        "setmainfont", "setsansfont", "setmonofont", "newfontfamily",
        "begin", "end", "url", "href",
        "definecolor", "colorlet", "usetikzlibrary", "usepgfplotslibrary",
        "pgfplotsset", "hypersetup", "lstdefinestyle", "lstset",
        "newtheorem", "bibitem", "pyth", "lstinline",
        "NewDocumentCommand", "ProvideDocumentCommand", "DeclareDocumentCommand",
        "NewExpandableDocumentCommand", "NewDocumentEnvironment", "DeclareDocumentEnvironment"
    ]

    public static func scan(
        source: String,
        ignoredWords: Set<String> = [],
        maxIssues: Int = 250
    ) -> [SpellingIssue] {
        guard !source.isEmpty else { return [] }

        let masked = maskedProseString(from: source)
        let nsSource = source as NSString
        let totalLength = nsSource.length
        guard totalLength > 0 else { return [] }

        let lineStarts = computeLineStartOffsets(nsSource)
        let normalizedIgnored = Set(ignoredWords.map { $0.lowercased() })

        let checker = NSSpellChecker.shared
        var issues: [SpellingIssue] = []
        var searchStart = 0

        while searchStart < totalLength && issues.count < maxIssues {
            let misspelledRange = checker.checkSpelling(
                of: masked,
                startingAt: searchStart,
                language: nil,
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: nil
            )
            guard misspelledRange.location != NSNotFound, misspelledRange.length > 0 else {
                break
            }
            let nextStart = misspelledRange.location + misspelledRange.length
            guard nextStart > searchStart else { break }
            searchStart = nextStart

            guard misspelledRange.location + misspelledRange.length <= totalLength else {
                break
            }

            let word = nsSource.substring(with: misspelledRange)
            // Skip single characters, pure numbers, or words containing digits/underscores
            if word.count <= 1 ||
               normalizedIgnored.contains(word.lowercased()) ||
               checker.hasLearnedWord(word) ||
               word.rangeOfCharacter(from: .decimalDigits) != nil {
                continue
            }

            let guesses = checker.guesses(
                forWordRange: misspelledRange,
                in: masked,
                language: nil,
                inSpellDocumentWithTag: 0
            ) ?? []

            let lineNumber = lineNumberForUTF16Offset(misspelledRange.location, lineStarts: lineStarts)
            issues.append(
                SpellingIssue(
                    id: "\(misspelledRange.location)-\(misspelledRange.length)-\(word)",
                    word: word,
                    line: lineNumber,
                    nsRange: misspelledRange,
                    suggestions: Array(guesses.prefix(4))
                )
            )
        }

        return issues
    }

    /// Produces a string of identical UTF-16 length where non-prose regions (preamble, comments,
    /// math, expl3 blocks, verbatim/code environments, and LaTeX commands/keys) are replaced with spaces.
    public static func maskedProseString(from source: String) -> String {
        let nsSource = source as NSString
        let length = nsSource.length
        guard length > 0 else { return source }

        var codeUnits = [UInt16](repeating: 0, count: length)
        nsSource.getCharacters(&codeUnits, range: NSRange(location: 0, length: length))

        let newline: UInt16 = 0x000A
        let space: UInt16 = 0x0020

        func maskRange(_ range: NSRange) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            let start = max(0, range.location)
            let end = min(length, range.location + range.length)
            guard start < end else { return }
            for idx in start..<end where codeUnits[idx] != newline {
                codeUnits[idx] = space
            }
        }

        func maskPattern(_ pattern: String, options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for match in regex.matches(in: source, range: NSRange(location: 0, length: length)) {
                maskRange(match.range)
            }
        }

        // 1. Mask preamble before \begin{document}
        let beginDocRange = nsSource.range(of: "\\begin{document}")
        if beginDocRange.location != NSNotFound {
            maskRange(NSRange(location: 0, length: beginDocRange.location + beginDocRange.length))
        }

        // 2. Mask % comments
        maskPattern(#"(?<!\\)%.*$"#, options: [.anchorsMatchLines])

        // 3. Mask \ExplSyntaxOn ... \ExplSyntaxOff blocks
        maskPattern(#"\\ExplSyntaxOn[\s\S]*?\\ExplSyntaxOff"#, options: [])

        // 4. Mask math, code, verbatim, and TikZ environments
        let envGroup = excludedEnvironments.joined(separator: "|")
        maskPattern(#"\\begin\{("# + envGroup + #")\}[\s\S]*?\\end\{\1\}"#, options: [])

        // 5. Mask display & inline math + \verb
        maskPattern(#"\$\$[\s\S]*?\$\$"#)
        maskPattern(#"\\\[[\s\S]*?\\\]"#)
        maskPattern(#"\\\([\s\S]*?\\\)"#)
        maskPattern(#"(?<!\\)\$[^$\n]+(?<!\\)\$"#)
        maskPattern(#"\\verb\*?([^a-zA-Z\s])[\s\S]*?\1"#)

        // 6. Mask URLs
        maskPattern(#"https?://[^\s}\]]+"#)

        // 7. Mask environment placement arguments like \begin{figure}[htbp] and structural commands
        // with optional [...] and {...} arguments (without consuming trailing bracketed prose)
        maskPattern(#"\\(?:begin|end)\{[^{}]+\}(?:\s*\[[^\]]*\])?"#)
        let cmdGroup = structuralCommands.joined(separator: "|")
        maskPattern(#"\\(?:"# + cmdGroup + #")\*?(?:\s*\[[^\]]*\])*\s*\{[^{}]*\}"#)

        // 8. Mask remaining LaTeX commands with immediately attached [...] parameters (before bare \cmd)
        // so bracketed prose in running text like `[see Appndix A]` still gets spellchecked.
        maskPattern(#"\\[a-zA-Z@_*]+(?::[a-zA-Z]*)?\*?(?:\s*\[[^\]]*\])+"#)

        // 9. Mask remaining bare LaTeX command tokens (e.g. \textbf, \section, \alpha, \l_var_tl)
        // leaving prose arguments inside {...} unmasked for spellchecking.
        maskPattern(#"\\[a-zA-Z@_*]+(?::[a-zA-Z]*)?\*?"#)

        return String(utf16CodeUnits: codeUnits, count: length)
    }

    private static func computeLineStartOffsets(_ nsSource: NSString) -> [Int] {
        var starts = [0]
        let len = nsSource.length
        for idx in 0..<len where nsSource.character(at: idx) == 0x000A {
            starts.append(idx + 1)
        }
        return starts
    }

    private static func lineNumberForUTF16Offset(_ offset: Int, lineStarts: [Int]) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= offset {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return max(1, high + 1)
    }
}
