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
}
