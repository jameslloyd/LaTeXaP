import Foundation

public struct ContextAdviceItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let category: String
    public let explanation: String
    public let actionLabel: String?
    public let snippetToInsert: String?
    public let packageToInsert: String?

    public init(
        id: String,
        title: String,
        category: String,
        explanation: String,
        actionLabel: String? = nil,
        snippetToInsert: String? = nil,
        packageToInsert: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.explanation = explanation
        self.actionLabel = actionLabel
        self.snippetToInsert = snippetToInsert
        self.packageToInsert = packageToInsert
    }
}

public enum ContextSuggestionsEngine {
    public static func analyze(
        source: String,
        cursorLine: Int,
        diagnostics: [LaTeXDiagnostic]
    ) -> (contextBadge: String, items: [ContextAdviceItem]) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Empty or nearly-empty document: Getting Started Guide
        if trimmed.isEmpty {
            return (
                contextBadge: "Empty Document — Getting Started",
                items: [
                    ContextAdviceItem(
                        id: "start-skeleton",
                        title: "1. Start a Minimal LaTeX3 Document",
                        category: "Quick Start",
                        explanation: "Every LaTeX document requires a \\documentclass declaration, optional packages in the preamble, and a \\begin{document} ... \\end{document} body.",
                        actionLabel: "Insert Starter Document",
                        snippetToInsert: """
\\documentclass[11pt,a4paper]{article}
\\usepackage[margin=1in]{geometry}
\\usepackage{amsmath,amssymb}
\\usepackage{expl3}
\\usepackage{xparse}

\\title{Untitled \\LaTeX3 Document}
\\author{Author}
\\date{\\today}

\\begin{document}
\\maketitle

\\section{Introduction}
Write your content here.

\\end{document}
"""
                    ),
                    ContextAdviceItem(
                        id: "start-expl3",
                        title: "2. Add a LaTeX3 (expl3 + xparse) Macro Module",
                        category: "LaTeX3 Core",
                        explanation: "Use \\ExplSyntaxOn ... \\ExplSyntaxOff in your preamble to write structured LaTeX3 functions, variables (\\tl_new:N, \\int_eval:n, \\fp_eval:n), and \\NewDocumentCommand definitions.",
                        actionLabel: "Insert expl3 Preamble Block",
                        snippetToInsert: """
\\ExplSyntaxOn
\\NewDocumentCommand{\\HighlightTerm}{ O{blue} m }
  {
    \\textcolor{#1}{\\textbf{#2}}
  }
\\ExplSyntaxOff
"""
                    ),
                    ContextAdviceItem(
                        id: "start-python",
                        title: "3. Embed Python Code in Your Document",
                        category: "Python & Code",
                        explanation: "Include syntax-highlighted Python code using the listings or pythonhighlight packages — Tectonic downloads them automatically.",
                        actionLabel: "Insert Python Starter Document",
                        snippetToInsert: LaTeXCatalog.templates.first(where: { $0.id == "python-scientific" })?.content
                    )
                ]
            )
        }

        var items: [ContextAdviceItem] = []

        // 2. Check missing core structure (\documentclass or \begin{document})
        if !source.contains("\\documentclass") {
            items.append(
                ContextAdviceItem(
                    id: "missing-docclass",
                    title: "Missing \\documentclass Declaration",
                    category: "Structure",
                    explanation: "A valid LaTeX document starts with \\documentclass{article} (or report, book, beamer) at the very top of the file.",
                    actionLabel: "Insert \\documentclass",
                    snippetToInsert: "\\documentclass[11pt,a4paper]{article}\n\\usepackage[margin=1in]{geometry}"
                )
            )
        }

        if !source.contains("\\begin{document}") {
            items.append(
                ContextAdviceItem(
                    id: "missing-begindoc",
                    title: "Missing \\begin{document} ... \\end{document} Body",
                    category: "Structure",
                    explanation: "All printable text must appear between \\begin{document} and \\end{document}.",
                    actionLabel: "Append Document Body",
                    snippetToInsert: "\n\\begin{document}\n\n\\section{Introduction}\n\n\\end{document}"
                )
            )
        }

        // 3. Inspect lines up to cursorLine to determine active region
        let lines = source.components(separatedBy: .newlines)
        let clampedLine = max(1, min(cursorLine, max(1, lines.count)))
        let currentLineText = lines.isEmpty ? "" : lines[clampedLine - 1]
        let prefixLines = Array(lines.prefix(clampedLine))
        let prefixText = prefixLines.joined(separator: "\n")

        let inExpl3Block = countOccurrences(of: "\\ExplSyntaxOn", in: prefixText) > countOccurrences(of: "\\ExplSyntaxOff", in: prefixText)
        let beforeBeginDoc = !prefixText.contains("\\begin{document}") && source.contains("\\begin{document}")
        let activeEnv = detectInnermostEnvironment(in: prefixLines)

        // 4. Actionable quick-fixes for current compilation errors
        for diag in diagnostics where diag.severity == .error {
            if diag.message.contains("Undefined control sequence") {
                items.append(
                    ContextAdviceItem(
                        id: "fix-undef-\(diag.line ?? 0)",
                        title: "Undefined Control Sequence on Line \(diag.line ?? clampedLine)",
                        category: "Error Fix",
                        explanation: "TeX encountered a command it doesn't recognize. Check for typos, ensure required packages (like amsmath, xparse, or pythonhighlight) are loaded, or verify that expl3 commands are inside \\ExplSyntaxOn ... \\ExplSyntaxOff."
                    )
                )
            }
        }

        var contextBadge = "Document Body"

        if inExpl3Block {
            contextBadge = "LaTeX3 Programming Block (\\ExplSyntaxOn)"
            items.append(
                ContextAdviceItem(
                    id: "ctx-expl3-whitespace",
                    title: "LaTeX3 Syntax Rules Active (\\ExplSyntaxOn)",
                    category: "expl3 Guide",
                    explanation: "Inside \\ExplSyntaxOn, all spaces are ignored! Use explicit tilde (~) for a space token. Underscores (_) and colons (:) are part of function names (e.g., \\module_func:Nn). Prefix local variables with \\l_ and global variables with \\g_.",
                    actionLabel: "Insert \\cs_new_protected:Npn",
                    snippetToInsert: """
\\cs_new_protected:Npn \\my_module_helper:n #1
  {
    \\tl_set:Nn \\l_tmpa_tl { #1 }
    \\tl_use:N \\l_tmpa_tl
  }
"""
                )
            )
            items.append(
                ContextAdviceItem(
                    id: "ctx-expl3-xparse",
                    title: "Expose expl3 Logic via \\NewDocumentCommand",
                    category: "xparse",
                    explanation: "Wrap internal \\module_func:n functions in a user-facing document macro with argument specifiers: m (mandatory {}), O{default} (optional []), s (star *), v (verbatim).",
                    actionLabel: "Insert \\NewDocumentCommand",
                    snippetToInsert: """
\\NewDocumentCommand{\\MyMacro}{ O{default} m }
  {
    #1:~#2
  }
"""
                )
            )
        } else if let env = activeEnv {
            contextBadge = "Inside \\begin{\(env)} Environment"
            switch env {
            case "lstlisting", "python", "pycode", "minted":
                items.append(
                    ContextAdviceItem(
                        id: "ctx-python-env",
                        title: "Authoring Python Code in \\begin{\(env)}",
                        category: "Python & Code",
                        explanation: "You are inside a Python code environment. Special LaTeX characters (_, %, #) are treated literally inside verbatim code blocks. Use \\lstinline[language=Python]{expr} or \\pyth{expr} for inline code in text.",
                        actionLabel: "Load pythonhighlight Package",
                        packageToInsert: "pythonhighlight"
                    )
                )
            case "equation", "equation*", "align", "align*", "gather", "math", "pmatrix", "bmatrix":
                items.append(
                    ContextAdviceItem(
                        id: "ctx-math-env",
                        title: "Mathematics Mode (\\begin{\(env)})",
                        category: "Mathematics",
                        explanation: "In align environments, use & to align relation symbols (&=) and \\\\ to break lines. Use \\text{...} for upright words and \\mathrm{d}x for differentials.",
                        actionLabel: "Insert Matrix Block",
                        snippetToInsert: """
\\begin{pmatrix}
  a_{11} & a_{12} \\\\
  a_{21} & a_{22}
\\end{pmatrix}
"""
                    )
                )
            case "tabular", "table":
                items.append(
                    ContextAdviceItem(
                        id: "ctx-table-env",
                        title: "Publication Tables with booktabs",
                        category: "Tables",
                        explanation: "Avoid vertical lines in publication tables. Use \\toprule, \\midrule, and \\bottomrule from the booktabs package for clean horizontal rules.",
                        actionLabel: "Load booktabs Package",
                        packageToInsert: "booktabs"
                    )
                )
            case "tikzpicture":
                items.append(
                    ContextAdviceItem(
                        id: "ctx-tikz-env",
                        title: "TikZ Vector Graphics Canvas",
                        category: "TikZ",
                        explanation: "Every TikZ path statement (\\draw, \\node, \\fill) must end with a semicolon (;). Coordinates use (x,y) Cartesian or (angle:radius) polar notation.",
                        actionLabel: "Insert Connected Nodes",
                        snippetToInsert: """
  \\node[draw, rounded corners, fill=blue!8, inner sep=6pt] (A) at (0,0) {Input};
  \\node[draw, rounded corners, fill=green!8, inner sep=6pt] (B) at (3.5,0) {Output};
  \\draw[->, thick] (A) -- node[above] {$f(x)$} (B);
"""
                    )
                )
            default:
                break
            }
        } else if beforeBeginDoc {
            contextBadge = "Document Preamble (Line \(clampedLine))"
            items.append(
                ContextAdviceItem(
                    id: "ctx-preamble",
                    title: "Configuring Document Preamble & Packages",
                    category: "Preamble",
                    explanation: "The preamble (before \\begin{document}) is where you load CTAN packages with \\usepackage{...} and declare LaTeX3 macros. Tectonic automatically downloads any package you add.",
                    actionLabel: "Add Python & Code Support",
                    packageToInsert: "pythonhighlight"
                )
            )
            items.append(
                ContextAdviceItem(
                    id: "ctx-preamble-l3keys",
                    title: "Add Key-Value Configuration with l3keys",
                    category: "LaTeX3 Core",
                    explanation: "Use \\keys_define:nn in the preamble to build clean [key=value] interfaces for your custom commands.",
                    actionLabel: "Insert l3keys Template Block",
                    snippetToInsert: LaTeXCatalog.snippets.first(where: { $0.id == "l3keys-def" })?.code
                )
            )
        } else {
            // General document body context
            contextBadge = "Document Body (Line \(clampedLine))"
            if currentLineText.contains("$") || currentLineText.contains("\\frac") || currentLineText.contains("\\sum") {
                items.append(
                    ContextAdviceItem(
                        id: "ctx-inline-math",
                        title: "Inline & Display Mathematics",
                        category: "Mathematics",
                        explanation: "Promote complex inline formulas ($...$) to a numbered \\begin{equation} or multi-line \\begin{align} block for better readability.",
                        actionLabel: "Insert \\begin{align}",
                        snippetToInsert: LaTeXCatalog.snippets.first(where: { $0.id == "aligned-math" })?.code
                    )
                )
            }
            items.append(
                ContextAdviceItem(
                    id: "ctx-body-python",
                    title: "Insert Syntax-Highlighted Python Listing",
                    category: "Python & Code",
                    explanation: "Embed Python functions or scripts with automatic syntax coloring and line numbers.",
                    actionLabel: "Insert Python Block",
                    snippetToInsert: LaTeXCatalog.snippets.first(where: { $0.id == "python-listings" })?.code,
                    packageToInsert: "listings"
                )
            )
            items.append(
                ContextAdviceItem(
                    id: "ctx-body-table",
                    title: "Insert Booktabs Publication Table",
                    category: "Tables & Figures",
                    explanation: "Add a centered floating table with \\toprule, \\midrule, and \\bottomrule.",
                    actionLabel: "Insert Table",
                    snippetToInsert: LaTeXCatalog.snippets.first(where: { $0.id == "booktabs-table" })?.code,
                    packageToInsert: "booktabs"
                )
            )
        }

        return (contextBadge: contextBadge, items: items)
    }

    private static func countOccurrences(of target: String, in text: String) -> Int {
        guard !target.isEmpty else { return 0 }
        return text.components(separatedBy: target).count - 1
    }

    private static func detectInnermostEnvironment(in lines: [String]) -> String? {
        var stack: [String] = []
        let regex = try? NSRegularExpression(pattern: #"\\(begin|end)\{([^}]+)\}"#)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("%") { continue }
            let ns = line as NSString
            let matches = regex?.matches(in: line, range: NSRange(location: 0, length: ns.length)) ?? []
            for m in matches where m.numberOfRanges >= 3 {
                let kind = ns.substring(with: m.range(at: 1))
                let env = ns.substring(with: m.range(at: 2))
                if env == "document" { continue }
                if kind == "begin" {
                    stack.append(env)
                } else if kind == "end", let lastIdx = stack.lastIndex(of: env) {
                    stack.removeSubrange(lastIdx..<stack.count)
                }
            }
        }
        return stack.last
    }
}
