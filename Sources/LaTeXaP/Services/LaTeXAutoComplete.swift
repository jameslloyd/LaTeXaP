import Foundation

public struct LaTeXCompletionItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let trigger: String       // e.g. "\\NewDocumentCommand", "\\begin{align}", "\\int_eval:n"
    public let displayTitle: String  // Shown on left of popup
    public let signature: String     // Shown next to title, e.g. "{\\cmd}{args}{code}"
    public let category: String      // Badge, e.g. "xparse", "expl3", "env", "math", "pkg", "user"
    public let detail: String        // Short description
    public let insertText: String    // Text with "|" marking the cursor placement after insertion

    public init(
        trigger: String,
        displayTitle: String? = nil,
        signature: String = "",
        category: String,
        detail: String,
        insertText: String
    ) {
        self.id = "\(category):\(trigger):\(signature)"
        self.trigger = trigger
        self.displayTitle = displayTitle ?? trigger
        self.signature = signature
        self.category = category
        self.detail = detail
        self.insertText = insertText
    }

    public var plainInsertion: (text: String, cursorOffset: Int) {
        if let pipeIndex = insertText.firstIndex(of: "|") {
            let offset = insertText.distance(from: insertText.startIndex, to: pipeIndex)
            var cleaned = insertText
            cleaned.remove(at: pipeIndex)
            return (cleaned, offset)
        }
        return (insertText, (insertText as NSString).length)
    }
}

public struct CompletionQueryContext: Equatable, Sendable {
    public let replacementRange: NSRange
    public let prefix: String
    public let enclosingCommand: String? // e.g. "begin", "end", "usepackage"
}

public enum LaTeXAutoCompleteEngine {
    public static let builtInItems: [LaTeXCompletionItem] = [
        // --- LaTeX3 / xparse ---
        LaTeXCompletionItem(
            trigger: "\\ExplSyntaxOn",
            signature: "... \\ExplSyntaxOff",
            category: "expl3",
            detail: "Enter LaTeX3 programming syntax regime",
            insertText: "\\ExplSyntaxOn\n|\n\\ExplSyntaxOff"
        ),
        LaTeXCompletionItem(
            trigger: "\\ExplSyntaxOff",
            category: "expl3",
            detail: "Exit LaTeX3 programming syntax regime",
            insertText: "\\ExplSyntaxOff|"
        ),
        LaTeXCompletionItem(
            trigger: "\\NewDocumentCommand",
            signature: "{\\cmd}{args}{body}",
            category: "xparse",
            detail: "Define a new LaTeX3 document command",
            insertText: "\\NewDocumentCommand{\\|}{ m }\n  {\n    #1\n  }"
        ),
        LaTeXCompletionItem(
            trigger: "\\ProvideDocumentCommand",
            signature: "{\\cmd}{args}{body}",
            category: "xparse",
            detail: "Define a document command if not already defined",
            insertText: "\\ProvideDocumentCommand{\\|}{ m }\n  {\n    #1\n  }"
        ),
        LaTeXCompletionItem(
            trigger: "\\DeclareDocumentCommand",
            signature: "{\\cmd}{args}{body}",
            category: "xparse",
            detail: "Define or overwrite a document command",
            insertText: "\\DeclareDocumentCommand{\\|}{ m }\n  {\n    #1\n  }"
        ),
        LaTeXCompletionItem(
            trigger: "\\NewExpandableDocumentCommand",
            signature: "{\\cmd}{args}{body}",
            category: "xparse",
            detail: "Define a fully expandable LaTeX3 document command",
            insertText: "\\NewExpandableDocumentCommand{\\|}{ m }\n  {\n    #1\n  }"
        ),
        LaTeXCompletionItem(
            trigger: "\\NewDocumentEnvironment",
            signature: "{env}{args}{beg}{end}",
            category: "xparse",
            detail: "Define a new LaTeX3 document environment",
            insertText: "\\NewDocumentEnvironment{|}{ m }\n  {\n    \n  }\n  {\n    \n  }"
        ),
        LaTeXCompletionItem(
            trigger: "\\IfBooleanTF",
            signature: "{#1}{true}{false}",
            category: "xparse",
            detail: "Branch on starred (s) boolean argument",
            insertText: "\\IfBooleanTF{#1}{ | }{ }"
        ),
        LaTeXCompletionItem(
            trigger: "\\IfNoValueTF",
            signature: "{#1}{true}{false}",
            category: "xparse",
            detail: "Branch on omitted optional (o) argument",
            insertText: "\\IfNoValueTF{#1}{ | }{ }"
        ),
        LaTeXCompletionItem(
            trigger: "\\IfValueTF",
            signature: "{#1}{true}{false}",
            category: "xparse",
            detail: "Branch when optional (o) argument is present",
            insertText: "\\IfValueTF{#1}{ | }{ }"
        ),

        // --- LaTeX3 / expl3 kernel functions ---
        LaTeXCompletionItem(
            trigger: "\\cs_new:Npn",
            signature: "\\module_func:n #1 { ... }",
            category: "expl3",
            detail: "Define an expandable expl3 function",
            insertText: "\\cs_new:Npn \\| #1\n  {\n    #1\n  }"
        ),
        LaTeXCompletionItem(
            trigger: "\\cs_new_protected:Npn",
            signature: "\\module_func:n #1 { ... }",
            category: "expl3",
            detail: "Define a protected (non-expandable) expl3 function",
            insertText: "\\cs_new_protected:Npn \\| #1\n  {\n    #1\n  }"
        ),
        LaTeXCompletionItem(
            trigger: "\\cs_generate_variant:Nn",
            signature: "\\func:n { V, x, f }",
            category: "expl3",
            detail: "Generate argument expansion variants for an expl3 function",
            insertText: "\\cs_generate_variant:Nn \\| { V }"
        ),
        LaTeXCompletionItem(
            trigger: "\\tl_new:N",
            signature: "\\l_module_var_tl",
            category: "expl3",
            detail: "Declare a new token list variable",
            insertText: "\\tl_new:N \\l_|_tl"
        ),
        LaTeXCompletionItem(
            trigger: "\\tl_set:Nn",
            signature: "\\l_var_tl { tokens }",
            category: "expl3",
            detail: "Set a token list variable locally",
            insertText: "\\tl_set:Nn \\l_|_tl { }"
        ),
        LaTeXCompletionItem(
            trigger: "\\tl_use:N",
            signature: "\\l_var_tl",
            category: "expl3",
            detail: "Output the contents of a token list variable",
            insertText: "\\tl_use:N \\l_|_tl"
        ),
        LaTeXCompletionItem(
            trigger: "\\int_new:N",
            signature: "\\l_module_var_int",
            category: "expl3",
            detail: "Declare a new integer variable",
            insertText: "\\int_new:N \\l_|_int"
        ),
        LaTeXCompletionItem(
            trigger: "\\int_set:Nn",
            signature: "\\l_var_int { expr }",
            category: "expl3",
            detail: "Set an integer variable from an integer expression",
            insertText: "\\int_set:Nn \\l_|_int { 0 }"
        ),
        LaTeXCompletionItem(
            trigger: "\\int_eval:n",
            signature: "{ integer-expr }",
            category: "expl3",
            detail: "Evaluate an integer expression expandably",
            insertText: "\\int_eval:n { | }"
        ),
        LaTeXCompletionItem(
            trigger: "\\int_step_inline:nnnn",
            signature: "{init}{step}{final}{code}",
            category: "expl3",
            detail: "Loop over an integer range with inline body",
            insertText: "\\int_step_inline:nnnn { 1 } { 1 } { | }\n  {\n    ##1\n  }"
        ),
        LaTeXCompletionItem(
            trigger: "\\int_compare:nNnTF",
            signature: "{expr1} < {expr2} {T} {F}",
            category: "expl3",
            detail: "Compare two integer expressions",
            insertText: "\\int_compare:nNnTF { | } = { 0 } { } { }"
        ),
        LaTeXCompletionItem(
            trigger: "\\fp_new:N",
            signature: "\\l_module_var_fp",
            category: "expl3",
            detail: "Declare a new IEEE 754 floating-point variable",
            insertText: "\\fp_new:N \\l_|_fp"
        ),
        LaTeXCompletionItem(
            trigger: "\\fp_eval:n",
            signature: "{ fp-expr }",
            category: "expl3",
            detail: "Evaluate floating-point math expression (sin, cos, ln, round)",
            insertText: "\\fp_eval:n { | }"
        ),
        LaTeXCompletionItem(
            trigger: "\\seq_new:N",
            signature: "\\l_module_var_seq",
            category: "expl3",
            detail: "Declare a new sequence variable",
            insertText: "\\seq_new:N \\l_|_seq"
        ),
        LaTeXCompletionItem(
            trigger: "\\seq_set_from_clist:Nn",
            signature: "\\l_var_seq { a, b, c }",
            category: "expl3",
            detail: "Populate a sequence from a comma-separated list",
            insertText: "\\seq_set_from_clist:Nn \\l_|_seq { }"
        ),
        LaTeXCompletionItem(
            trigger: "\\seq_map_inline:Nn",
            signature: "\\l_var_seq { code }",
            category: "expl3",
            detail: "Iterate over each item in a sequence",
            insertText: "\\seq_map_inline:Nn \\l_|_seq\n  {\n    ##1\n  }"
        ),
        LaTeXCompletionItem(
            trigger: "\\clist_map_inline:nn",
            signature: "{ a, b, c } { code }",
            category: "expl3",
            detail: "Iterate directly over an inline comma-separated list",
            insertText: "\\clist_map_inline:nn { | }\n  {\n    ##1\n  }"
        ),
        LaTeXCompletionItem(
            trigger: "\\bool_new:N",
            signature: "\\l_module_var_bool",
            category: "expl3",
            detail: "Declare a new boolean variable",
            insertText: "\\bool_new:N \\l_|_bool"
        ),
        LaTeXCompletionItem(
            trigger: "\\bool_if:NTF",
            signature: "\\l_var_bool {true} {false}",
            category: "expl3",
            detail: "Branch on an expl3 boolean variable",
            insertText: "\\bool_if:NTF \\l_|_bool { } { }"
        ),
        LaTeXCompletionItem(
            trigger: "\\keys_define:nn",
            signature: "{ module } { key-specs }",
            category: "expl3",
            detail: "Define key-value options using l3keys",
            insertText: "\\keys_define:nn { | }\n  {\n    key .tl_set:N = \\l_my_tl,\n  }"
        ),
        LaTeXCompletionItem(
            trigger: "\\keys_set:nn",
            signature: "{ module } { key=val }",
            category: "expl3",
            detail: "Apply key-value options for a module",
            insertText: "\\keys_set:nn { | } { }"
        ),
        LaTeXCompletionItem(
            trigger: "\\prop_new:N",
            signature: "\\l_module_var_prop",
            category: "expl3",
            detail: "Declare a key-value property list variable",
            insertText: "\\prop_new:N \\l_|_prop"
        ),
        LaTeXCompletionItem(
            trigger: "\\msg_new:nnn",
            signature: "{module}{msg}{text}",
            category: "expl3",
            detail: "Define a structured LaTeX3 diagnostic message",
            insertText: "\\msg_new:nnn { | } { message-name } { Message~text~#1 }"
        ),
        LaTeXCompletionItem(
            trigger: "\\group_begin:",
            signature: "... \\group_end:",
            category: "expl3",
            detail: "Open a local TeX scoping group in expl3",
            insertText: "\\group_begin:\n|\n\\group_end:"
        ),

        // --- Document Structure & Sectioning ---
        LaTeXCompletionItem(
            trigger: "\\documentclass",
            signature: "[options]{class}",
            category: "doc",
            detail: "Declare the document class (article, report, book, beamer)",
            insertText: "\\documentclass[11pt,a4paper]{|article}"
        ),
        LaTeXCompletionItem(
            trigger: "\\usepackage",
            signature: "[options]{package}",
            category: "pkg",
            detail: "Load a CTAN LaTeX package",
            insertText: "\\usepackage{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\section",
            signature: "{title}",
            category: "doc",
            detail: "Top-level document section",
            insertText: "\\section{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\subsection",
            signature: "{title}",
            category: "doc",
            detail: "Second-level document subsection",
            insertText: "\\subsection{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\subsubsection",
            signature: "{title}",
            category: "doc",
            detail: "Third-level document subsubsection",
            insertText: "\\subsubsection{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\paragraph",
            signature: "{title}",
            category: "doc",
            detail: "Inline titled paragraph block",
            insertText: "\\paragraph{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\title",
            signature: "{text}",
            category: "doc",
            detail: "Set document title",
            insertText: "\\title{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\author",
            signature: "{names}",
            category: "doc",
            detail: "Set document author(s)",
            insertText: "\\author{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\date",
            signature: "{\\today}",
            category: "doc",
            detail: "Set document date",
            insertText: "\\date{\\today}|"
        ),
        LaTeXCompletionItem(
            trigger: "\\maketitle",
            category: "doc",
            detail: "Render document title block",
            insertText: "\\maketitle|"
        ),
        LaTeXCompletionItem(
            trigger: "\\tableofcontents",
            category: "doc",
            detail: "Render table of contents",
            insertText: "\\tableofcontents|"
        ),
        LaTeXCompletionItem(
            trigger: "\\label",
            signature: "{key}",
            category: "doc",
            detail: "Assign cross-reference label",
            insertText: "\\label{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\ref",
            signature: "{key}",
            category: "doc",
            detail: "Reference a numbered element",
            insertText: "\\ref{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\eqref",
            signature: "{eq:key}",
            category: "doc",
            detail: "Reference a numbered equation in parentheses",
            insertText: "\\eqref{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\cite",
            signature: "{bibkey}",
            category: "doc",
            detail: "Insert bibliographic citation",
            insertText: "\\cite{|}"
        ),

        // --- Environments (Full Line Auto-Expand) ---
        LaTeXCompletionItem(
            trigger: "\\begin{equation}",
            signature: "... \\end{equation}",
            category: "env",
            detail: "Numbered display math equation environment",
            insertText: "\\begin{equation}\n  |\n\\end{equation}"
        ),
        LaTeXCompletionItem(
            trigger: "\\begin{align}",
            signature: "... \\end{align}",
            category: "env",
            detail: "Multi-line aligned equations environment (amsmath)",
            insertText: "\\begin{align}\n  | &= \n\\end{align}"
        ),
        LaTeXCompletionItem(
            trigger: "\\begin{itemize}",
            signature: "... \\end{itemize}",
            category: "env",
            detail: "Bulleted list environment",
            insertText: "\\begin{itemize}\n  \\item |\n\\end{itemize}"
        ),
        LaTeXCompletionItem(
            trigger: "\\begin{enumerate}",
            signature: "... \\end{enumerate}",
            category: "env",
            detail: "Numbered list environment",
            insertText: "\\begin{enumerate}\n  \\item |\n\\end{enumerate}"
        ),
        LaTeXCompletionItem(
            trigger: "\\begin{figure}",
            signature: "[htbp] ... \\end{figure}",
            category: "env",
            detail: "Floating figure environment with caption and label",
            insertText: "\\begin{figure}[htbp]\n  \\centering\n  |\n  \\caption{Caption}\n  \\label{fig:label}\n\\end{figure}"
        ),
        LaTeXCompletionItem(
            trigger: "\\begin{table}",
            signature: "[htbp] ... \\end{table}",
            category: "env",
            detail: "Publication table with booktabs (\\toprule, \\midrule, \\bottomrule)",
            insertText: "\\begin{table}[htbp]\n  \\centering\n  \\begin{tabular}{@{}lcc@{}}\n    \\toprule\n    | & Column 2 & Column 3 \\\\\n    \\midrule\n    Item & 1 & 2 \\\\\n    \\bottomrule\n  \\end{tabular}\n  \\caption{Table caption}\n  \\label{tab:label}\n\\end{table}"
        ),
        LaTeXCompletionItem(
            trigger: "\\begin{tikzpicture}",
            signature: "... \\end{tikzpicture}",
            category: "env",
            detail: "TikZ vector drawing canvas",
            insertText: "\\begin{tikzpicture}\n  |\n\\end{tikzpicture}"
        ),
        LaTeXCompletionItem(
            trigger: "\\begin{abstract}",
            signature: "... \\end{abstract}",
            category: "env",
            detail: "Document abstract block",
            insertText: "\\begin{abstract}\n|\n\\end{abstract}"
        ),
        LaTeXCompletionItem(
            trigger: "\\begin{theorem}",
            signature: "[Name] ... \\end{theorem}",
            category: "env",
            detail: "Theorem environment (amsthm)",
            insertText: "\\begin{theorem}[|]\n  \n\\end{theorem}"
        ),
        LaTeXCompletionItem(
            trigger: "\\begin{proof}",
            signature: "... \\end{proof}",
            category: "env",
            detail: "Mathematical proof environment (amsthm)",
            insertText: "\\begin{proof}\n  |\n\\end{proof}"
        ),
        LaTeXCompletionItem(
            trigger: "\\begin",
            signature: "{env} ... \\end{env}",
            category: "env",
            detail: "Begin a generic LaTeX environment",
            insertText: "\\begin{|} \n  \n\\end{}"
        ),

        // --- Text Formatting ---
        LaTeXCompletionItem(
            trigger: "\\textbf",
            signature: "{bold text}",
            category: "text",
            detail: "Boldface text",
            insertText: "\\textbf{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\emph",
            signature: "{emphasized}",
            category: "text",
            detail: "Emphasized (italic) text",
            insertText: "\\emph{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\texttt",
            signature: "{monospaced}",
            category: "text",
            detail: "Typewriter / monospaced text",
            insertText: "\\texttt{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\textsc",
            signature: "{small caps}",
            category: "text",
            detail: "Small capitals text",
            insertText: "\\textsc{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\textcolor",
            signature: "{color}{text}",
            category: "text",
            detail: "Colored text (xcolor)",
            insertText: "\\textcolor{|}{}"
        ),
        LaTeXCompletionItem(
            trigger: "\\colorbox",
            signature: "{color}{text}",
            category: "text",
            detail: "Background-colored box (xcolor)",
            insertText: "\\colorbox{|}{}"
        ),
        LaTeXCompletionItem(
            trigger: "\\href",
            signature: "{url}{text}",
            category: "text",
            detail: "Hyperlink with display text (hyperref)",
            insertText: "\\href{https://|}{}"
        ),
        LaTeXCompletionItem(
            trigger: "\\url",
            signature: "{url}",
            category: "text",
            detail: "Formatted web URL (hyperref)",
            insertText: "\\url{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\footnote",
            signature: "{text}",
            category: "text",
            detail: "Insert numbered page footnote",
            insertText: "\\footnote{|}"
        ),

        // --- Mathematics & Symbols ---
        LaTeXCompletionItem(
            trigger: "\\frac",
            signature: "{num}{den}",
            category: "math",
            detail: "Fraction",
            insertText: "\\frac{|}{}"
        ),
        LaTeXCompletionItem(
            trigger: "\\dfrac",
            signature: "{num}{den}",
            category: "math",
            detail: "Display-style fraction (amsmath)",
            insertText: "\\dfrac{|}{}"
        ),
        LaTeXCompletionItem(
            trigger: "\\sqrt",
            signature: "{expr}",
            category: "math",
            detail: "Square root",
            insertText: "\\sqrt{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\sum",
            signature: "_{i=1}^{n}",
            category: "math",
            detail: "Summation with lower and upper limits",
            insertText: "\\sum_{|=1}^{\\infty}"
        ),
        LaTeXCompletionItem(
            trigger: "\\prod",
            signature: "_{i=1}^{n}",
            category: "math",
            detail: "Product with lower and upper limits",
            insertText: "\\prod_{|=1}^{n}"
        ),
        LaTeXCompletionItem(
            trigger: "\\int",
            signature: "_{a}^{b}",
            category: "math",
            detail: "Definite integral",
            insertText: "\\int_{|}^{\\infty}"
        ),
        LaTeXCompletionItem(
            trigger: "\\lim",
            signature: "_{x \\to \\infty}",
            category: "math",
            detail: "Limit operator",
            insertText: "\\lim_{| \\to \\infty}"
        ),
        LaTeXCompletionItem(
            trigger: "\\mathbb",
            signature: "{R}",
            category: "math",
            detail: "Blackboard bold font (amssymb)",
            insertText: "\\mathbb{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\mathcal",
            signature: "{L}",
            category: "math",
            detail: "Calligraphic math font",
            insertText: "\\mathcal{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\mathrm",
            signature: "{d}",
            category: "math",
            detail: "Upright roman math font",
            insertText: "\\mathrm{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\left",
            signature: "( ... \\right)",
            category: "math",
            detail: "Auto-sized paired delimiters",
            insertText: "\\left( | \\right)"
        ),
        LaTeXCompletionItem(
            trigger: "\\alpha",
            category: "math",
            detail: "Greek letter alpha (α)",
            insertText: "\\alpha|"
        ),
        LaTeXCompletionItem(
            trigger: "\\beta",
            category: "math",
            detail: "Greek letter beta (β)",
            insertText: "\\beta|"
        ),
        LaTeXCompletionItem(
            trigger: "\\gamma",
            category: "math",
            detail: "Greek letter gamma (γ)",
            insertText: "\\gamma|"
        ),
        LaTeXCompletionItem(
            trigger: "\\delta",
            category: "math",
            detail: "Greek letter delta (δ)",
            insertText: "\\delta|"
        ),
        LaTeXCompletionItem(
            trigger: "\\epsilon",
            category: "math",
            detail: "Greek letter epsilon (ϵ)",
            insertText: "\\epsilon|"
        ),
        LaTeXCompletionItem(
            trigger: "\\theta",
            category: "math",
            detail: "Greek letter theta (θ)",
            insertText: "\\theta|"
        ),
        LaTeXCompletionItem(
            trigger: "\\lambda",
            category: "math",
            detail: "Greek letter lambda (λ)",
            insertText: "\\lambda|"
        ),
        LaTeXCompletionItem(
            trigger: "\\mu",
            category: "math",
            detail: "Greek letter mu (μ)",
            insertText: "\\mu|"
        ),
        LaTeXCompletionItem(
            trigger: "\\pi",
            category: "math",
            detail: "Greek letter pi (π)",
            insertText: "\\pi|"
        ),
        LaTeXCompletionItem(
            trigger: "\\sigma",
            category: "math",
            detail: "Greek letter sigma (σ)",
            insertText: "\\sigma|"
        ),
        LaTeXCompletionItem(
            trigger: "\\omega",
            category: "math",
            detail: "Greek letter omega (ω)",
            insertText: "\\omega|"
        ),
        LaTeXCompletionItem(
            trigger: "\\infty",
            category: "math",
            detail: "Infinity symbol (∞)",
            insertText: "\\infty|"
        ),
        LaTeXCompletionItem(
            trigger: "\\partial",
            category: "math",
            detail: "Partial derivative symbol (∂)",
            insertText: "\\partial|"
        ),
        LaTeXCompletionItem(
            trigger: "\\nabla",
            category: "math",
            detail: "Gradient / nabla operator (∇)",
            insertText: "\\nabla|"
        ),
        LaTeXCompletionItem(
            trigger: "\\toprule",
            category: "table",
            detail: "Top rule for booktabs table",
            insertText: "\\toprule|"
        ),
        LaTeXCompletionItem(
            trigger: "\\midrule",
            category: "table",
            detail: "Middle rule for booktabs table",
            insertText: "\\midrule|"
        ),
        LaTeXCompletionItem(
            trigger: "\\bottomrule",
            category: "table",
            detail: "Bottom rule for booktabs table",
            insertText: "\\bottomrule|"
        ),
        LaTeXCompletionItem(
            trigger: "\\begin{lstlisting}",
            signature: "[language=Python] ... \\end{lstlisting}",
            category: "python",
            detail: "Syntax-highlighted Python code block (listings)",
            insertText: "\\begin{lstlisting}[language=Python, frame=single, numbers=left, basicstyle=\\ttfamily\\small]\n|\n\\end{lstlisting}"
        ),
        LaTeXCompletionItem(
            trigger: "\\begin{python}",
            signature: "... \\end{python}",
            category: "python",
            detail: "Python syntax-highlighted environment (pythonhighlight)",
            insertText: "\\begin{python}\n|\n\\end{python}"
        ),
        LaTeXCompletionItem(
            trigger: "\\begin{pycode}",
            signature: "... \\end{pycode}",
            category: "python",
            detail: "Executable Python code block (pythontex)",
            insertText: "\\begin{pycode}\n|\n\\end{pycode}"
        ),
        LaTeXCompletionItem(
            trigger: "\\pyth",
            signature: "{python_expr}",
            category: "python",
            detail: "Inline syntax-highlighted Python snippet (pythonhighlight)",
            insertText: "\\pyth{|}"
        ),
        LaTeXCompletionItem(
            trigger: "\\lstinline",
            signature: "[language=Python]{code}",
            category: "python",
            detail: "Inline source code snippet (listings)",
            insertText: "\\lstinline[language=Python]{|}"
        )
    ]

    public static let commonEnvironmentNames: [(name: String, detail: String, body: String)] = [
        ("equation", "Numbered display equation", "\n  |\n"),
        ("equation*", "Unnumbered display equation", "\n  |\n"),
        ("align", "Aligned multi-line equations", "\n  | &= \n"),
        ("align*", "Unnumbered aligned equations", "\n  | &= \n"),
        ("gather", "Centered multi-line equations", "\n  |\n"),
        ("itemize", "Bulleted list", "\n  \\item |\n"),
        ("enumerate", "Numbered list", "\n  \\item |\n"),
        ("description", "Labeled description list", "\n  \\item[|] \n"),
        ("figure", "Floating figure", "[htbp]\n  \\centering\n  |\n  \\caption{}\n  \\label{fig:}\n"),
        ("table", "Floating table", "[htbp]\n  \\centering\n  |\n  \\caption{}\n  \\label{tab:}\n"),
        ("tabular", "Table grid", "{@{}lcc@{}}\n  \\toprule\n  | \\\\\n  \\midrule\n  \\bottomrule\n"),
        ("tikzpicture", "TikZ vector diagram", "\n  |\n"),
        ("abstract", "Document abstract", "\n|\n"),
        ("theorem", "Theorem block", "\n  |\n"),
        ("lemma", "Lemma block", "\n  |\n"),
        ("definition", "Definition block", "\n  |\n"),
        ("proof", "Proof block", "\n  |\n"),
        ("center", "Centered block", "\n  |\n"),
        ("minipage", "Fixed-width subpage box", "{0.48\\textwidth}\n  |\n"),
        ("pmatrix", "Parenthesized matrix (amsmath)", "\n  | & \\\\\n"),
        ("bmatrix", "Bracketed matrix (amsmath)", "\n  | & \\\\\n"),
        ("lstlisting", "Python / Source code listing", "[language=Python, frame=single]\n|\n"),
        ("python", "Python syntax-highlighted block (pythonhighlight)", "\n|\n"),
        ("pycode", "PythonTeX executable block", "\n|\n"),
        ("algorithm", "Algorithmic pseudocode block (algorithm2e)", "[H]\n  \\SetAlgoLined\n  |\n  \\caption{Algorithm}\n")
    ]

    /// Inspects the line up to `cursorLocation` to determine if an autocomplete query is active.
    public static func extractQuery(in source: String, cursorLocation: Int) -> CompletionQueryContext? {
        let nsString = source as NSString
        guard cursorLocation > 0, cursorLocation <= nsString.length else { return nil }

        let lineRange = nsString.lineRange(for: NSRange(location: cursorLocation, length: 0))
        let prefixLength = cursorLocation - lineRange.location
        guard prefixLength > 0 else { return nil }

        let linePrefix = nsString.substring(with: NSRange(location: lineRange.location, length: prefixLength))

        // Ignore if cursor is inside a comment on the current line
        if let commentRange = linePrefix.range(of: #"(?<!\\)%"#, options: .regularExpression) {
            if commentRange.lowerBound < linePrefix.endIndex {
                return nil
            }
        }

        // Case 1: Cursor is inside \begin{prefix, \end{prefix, or \usepackage{prefix
        if let braceMatch = linePrefix.range(
            of: #"\\(begin|end|usepackage)(?:\[[^\]]*\])?\{([a-zA-Z0-9_*:]*)$"#,
            options: .regularExpression
        ) {
            let matchedSub = String(linePrefix[braceMatch])
            if let openBraceIdx = matchedSub.lastIndex(of: "{") {
                let argPrefix = String(matchedSub[matchedSub.index(after: openBraceIdx)...])
                let cmdPart = String(matchedSub[..<openBraceIdx])
                let cmdName: String
                if cmdPart.hasPrefix("\\begin") { cmdName = "begin" }
                else if cmdPart.hasPrefix("\\end") { cmdName = "end" }
                else { cmdName = "usepackage" }

                // For \begin{...}, replace from the `\` of `\begin{...` so we can expand the entire `\begin{env}...\end{env}`
                if cmdName == "begin" {
                    let matchOffset = linePrefix.distance(from: linePrefix.startIndex, to: braceMatch.lowerBound)
                    let replaceStart = lineRange.location + matchOffset
                    let replaceLen = cursorLocation - replaceStart
                    return CompletionQueryContext(
                        replacementRange: NSRange(location: replaceStart, length: replaceLen),
                        prefix: matchedSub,
                        enclosingCommand: "begin"
                    )
                } else {
                    let argOffset = matchedSub.distance(from: matchedSub.startIndex, to: matchedSub.index(after: openBraceIdx))
                    let matchOffset = linePrefix.distance(from: linePrefix.startIndex, to: braceMatch.lowerBound)
                    let replaceStart = lineRange.location + matchOffset + argOffset
                    let replaceLen = cursorLocation - replaceStart
                    return CompletionQueryContext(
                        replacementRange: NSRange(location: replaceStart, length: replaceLen),
                        prefix: argPrefix,
                        enclosingCommand: cmdName
                    )
                }
            }
        }

        // Case 2: Standard or expl3 command token starting with `\`
        // Matches e.g. `\`, `\sec`, `\NewDoc`, `\int_eval:n`, `\l_my_tl`
        if let cmdMatch = linePrefix.range(
            of: #"\\[a-zA-Z@_][a-zA-Z0-9_@:]*$"#,
            options: .regularExpression
        ) {
            let token = String(linePrefix[cmdMatch])
            let matchOffset = linePrefix.distance(from: linePrefix.startIndex, to: cmdMatch.lowerBound)
            let replaceStart = lineRange.location + matchOffset
            let replaceLen = cursorLocation - replaceStart
            return CompletionQueryContext(
                replacementRange: NSRange(location: replaceStart, length: replaceLen),
                prefix: token,
                enclosingCommand: nil
            )
        }

        return nil
    }

    /// Computes ranked autocomplete suggestions for the current query context and document source.
    public static func suggestions(for query: CompletionQueryContext, in source: String) -> [LaTeXCompletionItem] {
        // 1. Inside \usepackage{...}
        if query.enclosingCommand == "usepackage" {
            let filter = query.prefix.lowercased()
            return LaTeXCatalog.commonPackages
                .filter { filter.isEmpty || $0.package.lowercased().hasPrefix(filter) || $0.package.lowercased().contains(filter) }
                .map { pkg in
                    LaTeXCompletionItem(
                        trigger: pkg.package,
                        displayTitle: pkg.package,
                        signature: pkg.options.isEmpty ? "" : "[\(pkg.options)]",
                        category: "pkg",
                        detail: pkg.description,
                        insertText: "\(pkg.package)|"
                    )
                }
        }

        // 2. Inside \end{...}
        if query.enclosingCommand == "end" {
            let filter = query.prefix.lowercased()
            let docEnvs = extractUserEnvironments(from: source)
            let allEnvNames = Array(Set(commonEnvironmentNames.map { $0.name } + docEnvs)).sorted()
            return allEnvNames
                .filter { filter.isEmpty || $0.lowercased().hasPrefix(filter) }
                .map { env in
                    LaTeXCompletionItem(
                        trigger: env,
                        displayTitle: env,
                        signature: "",
                        category: "env",
                        detail: "Close \\begin{\(env)} environment",
                        insertText: "\(env)|"
                    )
                }
        }

        // 3. Inside \begin{...
        if query.enclosingCommand == "begin" {
            let openBraceIdx = query.prefix.lastIndex(of: "{")
            let envFilter = openBraceIdx.map { String(query.prefix[query.prefix.index(after: $0)...]).lowercased() } ?? ""
            var items: [LaTeXCompletionItem] = []

            for env in commonEnvironmentNames where envFilter.isEmpty || env.name.lowercased().hasPrefix(envFilter) {
                items.append(
                    LaTeXCompletionItem(
                        trigger: "\\begin{\(env.name)}",
                        displayTitle: "\\begin{\(env.name)}",
                        signature: "... \\end{\(env.name)}",
                        category: "env",
                        detail: env.detail,
                        insertText: "\\begin{\(env.name)}\(env.body)\\end{\(env.name)}"
                    )
                )
            }

            for userEnv in extractUserEnvironments(from: source) where envFilter.isEmpty || userEnv.lowercased().hasPrefix(envFilter) {
                if !items.contains(where: { $0.trigger == "\\begin{\(userEnv)}" }) {
                    items.append(
                        LaTeXCompletionItem(
                            trigger: "\\begin{\(userEnv)}",
                            displayTitle: "\\begin{\(userEnv)}",
                            signature: "... \\end{\(userEnv)}",
                            category: "user",
                            detail: "Document-defined environment",
                            insertText: "\\begin{\(userEnv)}\n  |\n\\end{\(userEnv)}"
                        )
                    )
                }
            }
            return items
        }

        // 4. General `\command` or `\expl3_func:n` completion
        let dynamicItems = extractDocumentDefinedCommands(from: source)
        var combined = dynamicItems + builtInItems

        // Deduplicate by trigger while preserving dynamic user macros first
        var seenTriggers = Set<String>()
        combined = combined.filter { item in
            seenTriggers.insert(item.trigger).inserted
        }

        let lowerPrefix = query.prefix.lowercased()
        let prefixMatches = combined.filter { item in
            let lowerTrigger = item.trigger.lowercased()
            // Don't suggest the exact token if it has no arguments/expansion and is already completely typed
            if lowerTrigger == lowerPrefix && item.signature.isEmpty && !item.insertText.contains("{") && !item.insertText.contains("\n") {
                return false
            }
            return lowerTrigger.hasPrefix(lowerPrefix) || lowerTrigger.contains(lowerPrefix.dropFirst())
        }

        return prefixMatches.sorted { a, b in
            let aStarts = a.trigger.lowercased().hasPrefix(lowerPrefix)
            let bStarts = b.trigger.lowercased().hasPrefix(lowerPrefix)
            if aStarts != bStarts { return aStarts }

            let aExactCase = a.trigger.hasPrefix(query.prefix)
            let bExactCase = b.trigger.hasPrefix(query.prefix)
            if aExactCase != bExactCase { return aExactCase }

            if a.category == "user" && b.category != "user" { return true }
            if b.category == "user" && a.category != "user" { return false }

            return a.trigger.count < b.trigger.count
        }
        .prefix(14)
        .map { $0 }
    }

    /// Scans the active document for user-defined `\NewDocumentCommand`, `\cs_new`, `\tl_new:N`, etc.
    public static func extractDocumentDefinedCommands(from source: String) -> [LaTeXCompletionItem] {
        var results: [LaTeXCompletionItem] = []

        // 1. xparse commands: \NewDocumentCommand{\foo}{ m O{default} }
        if let xparseRegex = try? NSRegularExpression(
            pattern: #"\\(?:New|Provide|Declare|NewExpandable)DocumentCommand\s*\{?(\\[a-zA-Z0-9_@]+)\}?\s*\{([^}]*)\}"#
        ) {
            let ns = source as NSString
            let matches = xparseRegex.matches(in: source, range: NSRange(location: 0, length: ns.length))
            for m in matches where m.numberOfRanges >= 3 {
                let cmd = ns.substring(with: m.range(at: 1))
                let argSpec = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                let mandatoryCount = argSpec.filter { $0 == "m" }.count
                let braces: String
                if mandatoryCount == 0 {
                    braces = "|"
                } else if mandatoryCount == 1 {
                    braces = "{|}"
                } else {
                    braces = "{|}" + String(repeating: "{}", count: mandatoryCount - 1)
                }
                results.append(
                    LaTeXCompletionItem(
                        trigger: cmd,
                        displayTitle: cmd,
                        signature: "{\(argSpec)}",
                        category: "user",
                        detail: "Document xparse command (\(argSpec))",
                        insertText: "\(cmd)\(braces)"
                    )
                )
            }
        }

        // 2. expl3 functions & variables: \cs_new:Npn \my_func:n, \tl_new:N \l_my_tl, \seq_new:N \l_my_seq, etc.
        if let expl3DefRegex = try? NSRegularExpression(
            pattern: #"\\(?:cs_new(?:_protected)?:\w+|tl_new:N|int_new:N|fp_new:N|seq_new:N|clist_new:N|bool_new:N|prop_new:N)\s*\{?(\\[a-zA-Z0-9_@:]+)\}?"#
        ) {
            let ns = source as NSString
            let matches = expl3DefRegex.matches(in: source, range: NSRange(location: 0, length: ns.length))
            for m in matches where m.numberOfRanges >= 2 {
                let symbol = ns.substring(with: m.range(at: 1))
                let hasBraceArg = symbol.hasSuffix(":n") || symbol.hasSuffix(":nn") || symbol.hasSuffix(":Nn")
                let insert = hasBraceArg ? "\(symbol) { | }" : "\(symbol)|"
                results.append(
                    LaTeXCompletionItem(
                        trigger: symbol,
                        displayTitle: symbol,
                        signature: hasBraceArg ? "{...}" : "",
                        category: "user",
                        detail: "Document expl3 symbol",
                        insertText: insert
                    )
                )
            }
        }

        return results
    }

    public static func extractUserEnvironments(from source: String) -> [String] {
        var envs: [String] = []
        if let regex = try? NSRegularExpression(
            pattern: #"\\(?:NewDocumentEnvironment|DeclareDocumentEnvironment|newtheorem)\s*\{([^}]+)\}"#
        ) {
            let ns = source as NSString
            for m in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges >= 2 {
                envs.append(ns.substring(with: m.range(at: 1)))
            }
        }
        return envs
    }
}
