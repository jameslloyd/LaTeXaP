import Foundation
import Testing
@testable import LaTeXaP

struct LaTeXaPTests {
    @Test func outlineParserDetectsSectionsAndExpl3Macros() {
        let sample = #"""
        \documentclass{article}
        \ExplSyntaxOn
        \NewDocumentCommand{\ExpandFactorial}{ m } { #1 }
        \cs_new:Npn \latexap_factorial:n #1 { #1 }
        \NewDocumentEnvironment{CalloutBox}{ m } { } { }
        \ExplSyntaxOff
        \begin{document}
        \section{Introduction}
        \subsection{Details}
        \end{document}
        """#

        let items = OutlineParser.parse(source: sample)
        #expect(items.count == 5)
        #expect(items[0].badge == "xparse")
        #expect(items[0].title == "\\ExpandFactorial")
        #expect(items[1].badge == "expl3")
        #expect(items[1].title == "\\latexap_factorial:n")
        #expect(items[2].badge == "env")
        #expect(items[3].title == "Introduction")
        #expect(items[4].title == "Details")
    }

    @Test func diagnosticParserExtractsLineAndErrors() {
        let stderr = """
        error: document.tex:14: Undefined control sequence.
        warning: document.tex:22: Overfull \\hbox (12.0pt too wide)
        """
        let logFile = """
        ! LaTeX cmd Error: First argument of '\\NewDocumentCommand' must be a command.
        l.14   }
        LaTeX Warning: Reference `eq:missing' on page 1 undefined on input line 42.
        """

        let diags = TectonicService.parseDiagnostics(stderr: stderr, stdout: "", logFile: logFile)
        #expect(diags.contains(where: { $0.severity == .error && $0.line == 14 }))
        #expect(diags.contains(where: { $0.severity == .warning && $0.line == 42 }))
    }

    @Test func syncTeXParserAndBidirectionalLookup() {
        let sampleSyncTeX = """
        SyncTeX Version:1
        Input:1:/tmp/document.tex
        Output:pdf
        Magnification:1000
        Unit:1
        X Offset:0
        Y Offset:0
        Content:
        {1
        h1,25:4736287,9061663:23592960,785929,244045
        (1,40:7750943,19938693:13592960,785929,244045
        )
        }
        """
        let data = SyncTeXParser.parse(text: sampleSyncTeX)
        #expect(data.inputs[1] == "/tmp/document.tex")
        #expect(data.boxes.count == 2)

        let forward = data.forwardSearch(line: 25)
        #expect(forward != nil)
        #expect(forward?.page == 1)
        #expect(forward?.line == 25)

        if let box40 = data.forwardSearch(line: 40) {
            let backwardLine = data.backwardSearch(page: 1, xPt: box40.xPt + 10, yTopPt: box40.yTopPt)
            #expect(backwardLine == 40)
        } else {
            Issue.record("Expected forward box for line 40")
        }
    }

    @Test func tectonicEndToEndLaTeX3Compilation() async {
        let service = TectonicService()
        for template in LaTeXCatalog.templates {
            let result = await service.compile(source: template.content)
            #expect(result.success, "Expected template '\(template.id)' to compile cleanly. Log: \(result.logOutput)")
            #expect(result.pdfURL != nil)
        }
    }

    @Test func autoCompleteSuggestsExpl3AndUserMacros() {
        let doc = #"""
        \documentclass{article}
        \ExplSyntaxOn
        \NewDocumentCommand{\MyCustomMacro}{ m m } { #1 #2 }
        \tl_new:N \l_custom_token_tl
        \ExplSyntaxOff
        \begin{document}
        \MyCu
        """#

        let cursorAtEnd = (doc as NSString).length
        let query = LaTeXAutoCompleteEngine.extractQuery(in: doc, cursorLocation: cursorAtEnd)
        #expect(query != nil)
        #expect(query?.prefix == "\\MyCu")

        if let query = query {
            let results = LaTeXAutoCompleteEngine.suggestions(for: query, in: doc)
            #expect(results.first?.trigger == "\\MyCustomMacro")
            #expect(results.first?.category == "user")
            #expect(results.first?.plainInsertion.text == "\\MyCustomMacro{}{}")
        }

        // Test \begin{ali environment auto-expansion
        let envSource = "\\begin{ali"
        let envQuery = LaTeXAutoCompleteEngine.extractQuery(in: envSource, cursorLocation: (envSource as NSString).length)
        #expect(envQuery?.enclosingCommand == "begin")
        if let envQuery = envQuery {
            let envSuggestions = LaTeXAutoCompleteEngine.suggestions(for: envQuery, in: envSource)
            #expect(envSuggestions.contains(where: { $0.trigger == "\\begin{align}" && $0.plainInsertion.text.contains("\\end{align}") }))
        }
    }

    @Test func contextSuggestionsAndPythonPackages() {
        // 1. Empty document shows Getting Started suggestions
        let emptyAnalysis = ContextSuggestionsEngine.analyze(source: "   \n ", cursorLine: 1, diagnostics: [])
        #expect(emptyAnalysis.contextBadge.contains("Empty Document"))
        #expect(emptyAnalysis.items.count >= 3)
        #expect(emptyAnalysis.items.first?.snippetToInsert?.contains("\\documentclass") == true)

        // 2. Inside \ExplSyntaxOn shows expl3 guidance
        let expl3Doc = """
        \\documentclass{article}
        \\ExplSyntaxOn
        \\tl_new:N \\l_my_tl
        """
        let expl3Analysis = ContextSuggestionsEngine.analyze(source: expl3Doc, cursorLine: 3, diagnostics: [])
        #expect(expl3Analysis.contextBadge.contains("ExplSyntaxOn"))
        #expect(expl3Analysis.items.contains(where: { $0.category == "expl3 Guide" }))

        // 3. Python packages are available in the catalog
        let pythonPackages = LaTeXCatalog.commonPackages.filter { $0.category == "Python & Code" }
        #expect(pythonPackages.contains(where: { $0.package == "pythonhighlight" }))
        #expect(pythonPackages.contains(where: { $0.package == "pythontex" }))
        #expect(pythonPackages.contains(where: { $0.package == "minted" }))
        #expect(pythonPackages.contains(where: { $0.package == "listings" }))
    }

    @Test func bibliographyAndCrossRefAutoComplete() {
        let doc = #"""
        \documentclass{article}
        \begin{document}
        \section{Intro}\label{sec:intro}
        \begin{equation}\label{eq:euler}
          e^{i\pi} + 1 = 0
        \end{equation}
        See \ref{eq:
        \begin{thebibliography}{9}
        \bibitem{nesterov1983}
        Y. Nesterov, ``Accelerated method,'' 1983.
        \end{thebibliography}
        \end{document}
        """#

        let entries = BibliographyService.extractEntries(fromSource: doc)
        #expect(entries.count == 1)
        #expect(entries.first?.key == "nesterov1983")
        #expect(entries.first?.year == "1983")

        let labels = BibliographyService.extractLabels(from: doc)
        #expect(labels.count == 2)
        #expect(labels.contains(where: { $0.label == "sec:intro" }))
        #expect(labels.contains(where: { $0.label == "eq:euler" }))

        // Test \cite{nes autocomplete
        let citeDoc = doc + "\n\\cite{nes"
        if let citeQuery = LaTeXAutoCompleteEngine.extractQuery(in: citeDoc, cursorLocation: (citeDoc as NSString).length) {
            #expect(citeQuery.enclosingCommand == "cite")
            let suggestions = LaTeXAutoCompleteEngine.suggestions(for: citeQuery, in: citeDoc)
            #expect(suggestions.first?.trigger == "nesterov1983")
            #expect(suggestions.first?.category == "bib")
        } else {
            Issue.record("Expected cite query")
        }

        // Test \eqref{eq: autocomplete
        let refDoc = doc + "\n\\eqref{eq:"
        if let refQuery = LaTeXAutoCompleteEngine.extractQuery(in: refDoc, cursorLocation: (refDoc as NSString).length) {
            #expect(refQuery.enclosingCommand == "ref")
            let suggestions = LaTeXAutoCompleteEngine.suggestions(for: refQuery, in: refDoc)
            #expect(suggestions.first?.trigger == "eq:euler")
            #expect(suggestions.first?.category == "ref")
        } else {
            Issue.record("Expected ref query")
        }
    }

    @Test func expl3LinterAndDocumentStatistics() {
        let badExpl3 = #"""
        \documentclass{article}
        \ExplSyntaxOn
        \tl_new:N \bad_var_name
        \cs_new:Npn \my_module_func:nn #1 { #1 }
        \ExplSyntaxOff
        \begin{document}
        Hello world from modern LaTeX3 document prose $x + y = z$.
        \end{document}
        """#

        let warnings = Expl3Linter.lint(source: badExpl3)
        #expect(warnings.count == 2)
        #expect(warnings.contains(where: { $0.line == 3 && $0.message.contains("\\bad_var_name") }))
        #expect(warnings.contains(where: { $0.line == 4 && $0.message.contains("declares 2 argument(s)") }))

        let stats = Expl3Linter.computeStatistics(source: badExpl3)
        #expect(stats.wordCount >= 7)
        #expect(stats.mathCount == 1)
        #expect(stats.expl3SymbolCount >= 2)
    }

    @Test func visualMatrixAndCSVToBooktabsGenerator() {
        let matrix = VisualToolsGenerator.generateMatrix(env: "bmatrix", rows: 2, cols: 2, fillIdentity: true)
        #expect(matrix.contains("\\begin{bmatrix}"))
        #expect(matrix.contains("1 & 0 \\\\"))
        #expect(matrix.contains("0 & 1"))

        let csv = "Optimizer, Rate\nGD, Linear\nNAG, Accelerated"
        let table = VisualToolsGenerator.convertCSVToBooktabs(csvText: csv, caption: "Results", label: "tab:res")
        #expect(table.contains("\\toprule"))
        #expect(table.contains("\\textbf{Optimizer} & \\textbf{Rate} \\\\"))
        #expect(table.contains("GD & Linear \\\\"))
        #expect(table.contains("\\bottomrule"))
    }
}
