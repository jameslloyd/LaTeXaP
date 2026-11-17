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

    @Test func updateCheckerVersionComparisonAndJSONParsing() {
        #expect(UpdateCheckerService.isVersion("0.1.2", newerThan: "0.1.1"))
        #expect(UpdateCheckerService.isVersion("v0.2", newerThan: "0.1.1"))
        #expect(!UpdateCheckerService.isVersion("0.1.1", newerThan: "0.1.1"))
        #expect(!UpdateCheckerService.isVersion("0.1.0", newerThan: "0.1.1"))

        let sampleReleaseJSON = """
        {
          "tag_name": "v0.2.0",
          "html_url": "https://github.com/jameslloyd/LaTeXaP/releases/tag/v0.2.0",
          "draft": false
        }
        """.data(using: .utf8)!

        let update = UpdateCheckerService.parseReleaseJSON(data: sampleReleaseJSON, currentVersion: "0.1.1")
        #expect(update != nil)
        #expect(update?.latestVersion == "0.2.0")
        #expect(update?.tagName == "v0.2.0")

        let noUpdate = UpdateCheckerService.parseReleaseJSON(data: sampleReleaseJSON, currentVersion: "0.2.0")
        #expect(noUpdate == nil)

        let upToDateStatus = UpdateCheckerService.evaluateReleaseJSON(data: sampleReleaseJSON, currentVersion: "0.2.0")
        #expect(upToDateStatus == .upToDate(currentVersion: "0.2.0", latestTag: "v0.2.0"))

        let availableStatus = UpdateCheckerService.evaluateReleaseJSON(data: sampleReleaseJSON, currentVersion: "0.1.1")
        if case .updateAvailable(let found) = availableStatus {
            #expect(found.latestVersion == "0.2.0")
            #expect(found.tagName == "v0.2.0")
        } else {
            Issue.record("Expected updateAvailable status")
        }

        let draftJSON = """
        {
          "tag_name": "v0.3.0",
          "html_url": "https://github.com/jameslloyd/LaTeXaP/releases/tag/v0.3.0",
          "draft": true
        }
        """.data(using: .utf8)!
        #expect(UpdateCheckerService.evaluateReleaseJSON(data: draftJSON, currentVersion: "0.1.2") == .upToDate(currentVersion: "0.1.2", latestTag: nil))
    }

    // MARK: - Custom Fonts Tests

    private func sampleSystemFontURL() -> URL? {
        let candidates = [
            "/System/Library/Fonts/Geneva.ttf",
            "/System/Library/Fonts/Supplemental/Courier New.ttf",
            "/System/Library/Fonts/Courier.ttc",
            "/System/Library/Fonts/Helvetica.ttc"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    @Test func fontModelsAndCTANPresets() {
        #expect(FontFileFormat.from(url: URL(fileURLWithPath: "/tmp/MyFont.ttf")) == .ttf)
        #expect(FontFileFormat.from(url: URL(fileURLWithPath: "/tmp/MyFont.OTF")) == .otf)
        #expect(FontFileFormat.from(url: URL(fileURLWithPath: "/tmp/MyFont.ttc")) == .ttc)
        #expect(FontFileFormat.from(url: URL(fileURLWithPath: "/tmp/MyFont.woff2")) == nil)
        #expect(FontFileFormat.from(url: URL(fileURLWithPath: "/tmp/MyFont.svg")) == nil)

        #expect(LaTeXFontRole.main.latexCommand == "\\setmainfont")
        #expect(LaTeXFontRole.sans.latexCommand == "\\setsansfont")
        #expect(LaTeXFontRole.mono.latexCommand == "\\setmonofont")
        #expect(LaTeXFontRole.customFamily.latexCommand == "\\newfontfamily")

        let presetWithOpts = CTANFontPreset(
            id: "fira",
            name: "Fira",
            packageName: "fira",
            options: "sfdefault",
            classification: "Sans-Serif",
            description: "Fira"
        )
        #expect(presetWithOpts.usepackageStatement == "\\usepackage[sfdefault]{fira}")

        let pkgNames = Set(LaTeXCatalog.commonPackages.map(\.package))
        for expected in ["fontspec", "libertinus", "ebgaramond", "fira", "plex", "lmodern", "tgpagella"] {
            #expect(pkgNames.contains(expected), "Expected \(expected) in LaTeXCatalog.commonPackages")
        }
        #expect(LaTeXCatalog.ctanFontPresets.count >= 6)
    }

    @Test func fontLibraryValidationSanitizationAndManifestCRUD() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaTeXaPFontTests-\(UUID().uuidString)", isDirectory: true)
        let storageDir = tempRoot.appendingPathComponent("Fonts", isDirectory: true)
        let stagingDir = tempRoot.appendingPathComponent("Staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let service = FontLibraryService(storageDirectory: storageDir)

        // 1. Missing file
        #expect(throws: FontImportError.self) {
            _ = try service.importFont(from: stagingDir.appendingPathComponent("Missing.ttf"))
        }

        // 2. Unsupported extension (.woff2)
        let woffURL = stagingDir.appendingPathComponent("WebFont.woff2")
        try Data([0x77, 0x4F, 0x46, 0x32]).write(to: woffURL)
        do {
            _ = try service.importFont(from: woffURL)
            Issue.record("Expected unsupportedFormat error")
        } catch let error as FontImportError {
            if case .unsupportedFormat(let ext) = error {
                #expect(ext == ".woff2")
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }

        // 3. Corrupt font bytes with .ttf extension
        let corruptURL = stagingDir.appendingPathComponent("Corrupt.ttf")
        try Data("not a real font file".utf8).write(to: corruptURL)
        do {
            _ = try service.importFont(from: corruptURL)
            Issue.record("Expected invalidOrCorruptFont error")
        } catch let error as FontImportError {
            if case .invalidOrCorruptFont = error {
                // expected
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }

        // 4. Valid font import with unsafe filename characters (path traversal / TeX chars)
        guard let systemFont = sampleSystemFontURL() else {
            Issue.record("No sample macOS system font found for testing")
            return
        }
        let unsafeSubdir = stagingDir.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: unsafeSubdir, withIntermediateDirectories: true)
        let unsafeFontURL = unsafeSubdir.appendingPathComponent("..evil {font}%$#.\(systemFont.pathExtension)")
        try Data(contentsOf: systemFont).write(to: unsafeFontURL)

        let record = try service.importFont(from: unsafeFontURL)
        #expect(!record.fileName.contains("/"))
        #expect(!record.fileName.contains(".."))
        #expect(!record.fileName.contains("{"))
        #expect(!record.fileName.contains("}"))
        #expect(!record.fileName.contains("%"))
        #expect(service.fontFileURL(for: record).deletingLastPathComponent().standardizedFileURL == service.fontsDirectory)
        #expect(FileManager.default.fileExists(atPath: service.fontFileURL(for: record).path))
        #expect(FileManager.default.fileExists(atPath: service.manifestURL.path))

        // 5. Duplicate detection
        do {
            _ = try service.importFont(from: unsafeFontURL)
            Issue.record("Expected duplicateFont error")
        } catch let error as FontImportError {
            if case .duplicateFont = error {
                // expected
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }

        // 6. Manifest reload & rename
        let loaded = try service.loadManifest()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == record.id)

        let renamed = try service.renameFont(id: record.id, newDisplayName: "Custom Studio Font")
        #expect(renamed.displayName == "Custom Studio Font")
        #expect(try service.loadManifest().first?.displayName == "Custom Studio Font")

        #expect(throws: FontImportError.self) {
            _ = try service.renameFont(id: record.id, newDisplayName: "   ")
        }

        // 7. Register all & delete
        let registered = service.registerAllStoredFonts()
        #expect(registered.count == 1)

        try service.deleteFont(id: record.id)
        #expect(try service.loadManifest().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: service.fontFileURL(for: record).path))

        // 8. System font discovery
        let allFamilies = service.systemFontFamilies(monospaceOnly: false)
        let monoFamilies = service.systemFontFamilies(monospaceOnly: true)
        #expect(!allFamilies.isEmpty)
        #expect(!monoFamilies.isEmpty)
        #expect(monoFamilies.count <= allFamilies.count)
    }

    @Test @MainActor func documentViewModelFontActionsAndUserDefaultsPersistence() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaTeXaPVMFontTests-\(UUID().uuidString)", isDirectory: true)
        let storageDir = tempRoot.appendingPathComponent("Fonts", isDirectory: true)
        let stagingDir = tempRoot.appendingPathComponent("Staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let suiteName = "LaTeXaPTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let service = FontLibraryService(storageDirectory: storageDir)
        let vm = DocumentViewModel(
            initialTemplate: LaTeXCatalog.defaultTemplate,
            fontLibraryService: service,
            userDefaults: defaults,
            compileOnInit: false
        )
        vm.autoCompileEnabled = false

        // Editor font & size persistence + clamping
        vm.selectEditorFont("Menlo")
        vm.editorFontSize = 30.0
        #expect(vm.editorFontSize == 24.0)
        vm.editorFontSize = 6.0
        #expect(vm.editorFontSize == 10.0)
        vm.editorFontSize = 16.5

        let vmReloaded = DocumentViewModel(
            initialTemplate: LaTeXCatalog.defaultTemplate,
            fontLibraryService: service,
            userDefaults: defaults,
            compileOnInit: false
        )
        #expect(vmReloaded.editorFontName == "Menlo")
        #expect(vmReloaded.editorFontSize == 16.5)

        vmReloaded.resetEditorFontToDefault()
        #expect(vmReloaded.editorFontName == "")
        #expect(vmReloaded.editorFontSize == 13.5)

        // Custom font import, preamble injection, replacement, rename, delete
        guard let systemFont = sampleSystemFontURL() else {
            Issue.record("No sample macOS system font found for testing")
            return
        }
        let stagedFont = stagingDir.appendingPathComponent("TestDisplayFont.\(systemFont.pathExtension)")
        try Data(contentsOf: systemFont).write(to: stagedFont)

        await vm.importCustomFontsAsync(urls: [stagedFont])
        #expect(vm.customFonts.count == 1)
        #expect(!vm.isImportingFont)
        #expect(vm.fontErrorMessage == nil)
        #expect(vm.fontSuccessMessage != nil)

        if let imported = vm.customFonts.first {
            vm.renameCustomFont(imported, to: "Studio Sans")
            #expect(vm.customFonts.first?.displayName == "Studio Sans")

            vm.applyCustomFontToDocument(vm.customFonts[0], role: .main)
            #expect(vm.sourceText.contains("\\usepackage{fontspec}"))
            #expect(vm.sourceText.contains("\\setmainfont{\(imported.fileName)}"))

            // Applying another main font replaces existing \setmainfont rather than duplicating
            vm.applySystemFontToDocument(familyName: "Georgia", role: .main)
            #expect(vm.sourceText.contains("\\setmainfont{Georgia}"))
            #expect(!vm.sourceText.contains("\\setmainfont{\(imported.fileName)}"))

            // Custom family command sanitization
            vm.applyCustomFontToDocument(vm.customFonts[0], role: .customFamily, customCommand: "\\my_font-1!")
            #expect(vm.sourceText.contains("\\newfontfamily\\myfont{\(imported.fileName)}"))

            // Deleting font currently selected in editor resets editorFontName
            vm.selectEditorFont(imported.postScriptName)
            vm.deleteCustomFont(vm.customFonts[0])
            #expect(vm.customFonts.isEmpty)
            #expect(vm.editorFontName == "")
        }

        // CTAN preset
        if let preset = LaTeXCatalog.ctanFontPresets.first {
            vm.applyCTANFontPreset(preset)
            #expect(vm.sourceText.contains(preset.usepackageStatement))
        }

        vm.clearFontFeedback()
        #expect(vm.fontErrorMessage == nil)
        #expect(vm.fontSuccessMessage == nil)
    }

    @Test func tectonicFontEnvironmentAndAutoCompleteAndContextSuggestions() throws {
        // 1. Tectonic env injection (drops TEXINPUTS, avoids //, rejects ':' in path)
        var env: [String: String] = ["OPENTYPEFONTS": "/existing/fonts"]
        let fontDir = URL(fileURLWithPath: "/tmp/LaTeXaPFontsTest")
        let colonDir = URL(fileURLWithPath: "/tmp/Bad:ColonDir")
        TectonicService.injectFontEnvironment(fontDirectories: [fontDir, colonDir], into: &env)
        #expect(env["OPENTYPEFONTS"] == "/tmp/LaTeXaPFontsTest:/existing/fonts")
        #expect(env["TTFONTS"] == "/tmp/LaTeXaPFontsTest:")
        #expect(env["OSFONTDIR"] == "/tmp/LaTeXaPFontsTest:")
        #expect(env["TEXINPUTS"] == nil)

        // 2. Autocomplete for fontspec commands and brace font arguments
        let customRecord = CustomFontRecord(
            displayName: "Fira Code",
            familyName: "Fira Code",
            postScriptName: "FiraCode-Regular",
            styleName: "Regular",
            fileName: "FiraCode-Regular.ttf",
            format: .ttf,
            isMonospace: true,
            fileSizeBytes: 12345
        )

        let cmdDoc = "\\setma"
        let cmdQuery = LaTeXAutoCompleteEngine.extractQuery(in: cmdDoc, cursorLocation: (cmdDoc as NSString).length)
        #expect(cmdQuery != nil)
        if let cmdQuery {
            let cmdSuggestions = LaTeXAutoCompleteEngine.suggestions(for: cmdQuery, in: cmdDoc)
            #expect(cmdSuggestions.contains(where: { $0.trigger == "\\setmainfont" }))
        }

        let fontArgDoc = "\\setmainfont{Fira"
        let fontQuery = LaTeXAutoCompleteEngine.extractQuery(in: fontArgDoc, cursorLocation: (fontArgDoc as NSString).length)
        #expect(fontQuery?.enclosingCommand == "font")
        #expect(fontQuery?.prefix == "Fira")
        if let fontQuery {
            let fontSuggestions = LaTeXAutoCompleteEngine.suggestions(
                for: fontQuery,
                in: fontArgDoc,
                customFonts: [customRecord]
            )
            #expect(fontSuggestions.first?.trigger == "FiraCode-Regular.ttf")
            #expect(fontSuggestions.first?.category == "font")
        }

        let newFamilyDoc = "\\newfontfamily{\\heading}{Fira"
        let newFamilyQuery = LaTeXAutoCompleteEngine.extractQuery(in: newFamilyDoc, cursorLocation: (newFamilyDoc as NSString).length)
        #expect(newFamilyQuery?.enclosingCommand == "font")
        #expect(newFamilyQuery?.prefix == "Fira")

        // 3. ContextSuggestionsEngine detects fontspec font-not-found diagnostics
        let docMissingFontspec = """
        \\documentclass{article}
        \\begin{document}
        Hello
        \\end{document}
        """
        let fontDiag = LaTeXDiagnostic(
            line: 2,
            severity: .error,
            message: "Package fontspec Error: The font \"NonExistent\" cannot be found."
        )
        let advice = ContextSuggestionsEngine.analyze(source: docMissingFontspec, cursorLine: 2, diagnostics: [fontDiag])
        #expect(advice.items.contains(where: { $0.category == "Fonts" && $0.packageToInsert == "fontspec" }))
    }

    @Test func fontSecurityHardeningRegressionTests() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaTeXaPFontSecTests-\(UUID().uuidString)", isDirectory: true)
        let storageDir = tempRoot.appendingPathComponent("Fonts", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let service = FontLibraryService(storageDirectory: storageDir)

        // 1. Reject non-file URLs
        let remoteURL = URL(string: "https://example.com/EvilFont.ttf")!
        #expect(throws: FontImportError.self) {
            _ = try service.importFont(from: remoteURL)
        }

        // 2. Reject symlinks as import source
        if let systemFont = sampleSystemFontURL() {
            let linkURL = tempRoot.appendingPathComponent("SymlinkFont.\(systemFont.pathExtension)")
            try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: systemFont)
            #expect(throws: FontImportError.self) {
                _ = try service.importFont(from: linkURL)
            }
        }

        // 3. TeX metacharacter sanitization & empty-target guard
        let sanitized = FontLibraryService.sanitizeTeXArgument("MyFont{}\\input%$#&~^_[]\t\n")
        #expect(sanitized == "MyFontinput")
        #expect(service.generateSystemFontspecBlock(familyName: "{}\\#$%", role: .main) == "")

        // 4. Autocomplete sanitizes malicious font.fileName
        let maliciousRecord = CustomFontRecord(
            displayName: "Bad",
            familyName: "Bad",
            postScriptName: "Bad",
            styleName: "Regular",
            fileName: "Bad}\\write18{id}.ttf",
            format: .ttf,
            isMonospace: false,
            fileSizeBytes: 100
        )
        let q = LaTeXAutoCompleteEngine.extractQuery(in: "\\setmainfont{Bad", cursorLocation: 16)!
        let items = LaTeXAutoCompleteEngine.suggestions(for: q, in: "\\setmainfont{Bad", customFonts: [maliciousRecord])
        #expect(items.first?.trigger == "Badwrite18id.ttf")

        // 5. Tampered manifest entries (e.g. fileName == "fonts.json" or "../escape.ttf") are filtered out
        let tamperedManifest = FontLibraryManifest(
            schemaVersion: 1,
            fonts: [
                CustomFontRecord(
                    id: UUID(),
                    displayName: "Tampered",
                    familyName: "Tampered",
                    postScriptName: "Tampered",
                    styleName: "Regular",
                    fileName: "fonts.json",
                    format: .ttf,
                    isMonospace: false,
                    fileSizeBytes: 10
                ),
                CustomFontRecord(
                    id: UUID(),
                    displayName: "Traversal",
                    familyName: "Traversal",
                    postScriptName: "Traversal",
                    styleName: "Regular",
                    fileName: "../outside.ttf",
                    format: .ttf,
                    isMonospace: false,
                    fileSizeBytes: 10
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(tamperedManifest).write(to: service.manifestURL)
        #expect(try service.loadManifest().isEmpty)
        #expect(FileManager.default.fileExists(atPath: service.manifestURL.path))
    }

    // MARK: - v0.2.0 Academic Paper Authoring Suite Tests

    @Test func academicModelsCitationFormattingAndSanitization() {
        #expect(CitationCommandStyle.cite.format(key: "vaswani2017") == "\\cite{vaswani2017}")
        #expect(CitationCommandStyle.parencite.format(key: "vaswani2017", pageLocator: "p. 12") == "\\parencite[p. 12]{vaswani2017}")
        #expect(CitationCommandStyle.textcite.format(key: "knuth1984", pageLocator: "ch. 3") == "\\textcite[ch. 3]{knuth1984}")
        #expect(CitationCommandStyle.autocite.format(key: "doe2025") == "\\autocite{doe2025}")
        #expect(CitationCommandStyle.footcite.format(key: "doe2025") == "\\footcite{doe2025}")

        // Injection resistance in cite keys and page locators
        let maliciousCite = CitationCommandStyle.parencite.format(key: "bad}\\write18{id", pageLocator: "p. 5]{evil\\input{x}")
        #expect(!maliciousCite.contains("\\write18"))
        #expect(!maliciousCite.contains("p. 5]{evil"))
        #expect(!maliciousCite.contains("\\input"))

        // TeX text escaping and external metadata sanitization
        let escaped = AcademicSanitizer.escapeLaTeXText("R&D Results: 95% Accuracy_v2 \\write18{bad}")
        #expect(escaped.contains("R\\&D"))
        #expect(escaped.contains("95\\%"))
        #expect(escaped.contains("Accuracy\\_v2"))
        #expect(!escaped.contains("\\write18"))

        let extClean = AcademicSanitizer.sanitizeExternalMetadata("Deep Learning \\write18{id} & {Vision} % 100%")
        #expect(!extClean.contains("\\write18"))
        #expect(!extClean.contains("{"))
        #expect(!extClean.contains("}"))
        #expect(extClean.contains("\\&"))
        #expect(extClean.contains("\\%"))

        // Relative path validation blocks traversal, absolute paths, and backslashes
        #expect(AcademicSanitizer.validatedRelativeAssetPath("figures/plot-1.png") == "figures/plot-1.png")
        #expect(AcademicSanitizer.validatedRelativeAssetPath("../secret.png") == nil)
        #expect(AcademicSanitizer.validatedRelativeAssetPath("/etc/passwd") == nil)
        #expect(AcademicSanitizer.validatedRelativeAssetPath("figures\\plot.png") == nil)
        #expect(AcademicSanitizer.validatedRelativeAssetPath("C:figures/plot.png") == nil)
        #expect(AcademicSanitizer.sanitizeFigureFileName("../../evil {img}%.png") == "evil-img.png")
    }

    @Test func crossRefJSONParsingBibTeXParsingAndMerging() throws {
        let crossRefJSON = #"""
        {
          "status": "ok",
          "message": {
            "items": [
              {
                "DOI": "10.5555/3295222.3295349",
                "type": "proceedings-article",
                "title": ["Attention Is {All} You Need \\write18{id} & More"],
                "author": [
                  {"given": "Ashish", "family": "Vaswani"},
                  {"given": "Noam", "family": "Shazeer"}
                ],
                "container-title": ["Advances in Neural Information Processing Systems"],
                "published-print": {"date-parts": [[2017]]}
              }
            ]
          }
        }
        """#.data(using: .utf8)!

        let crossRefEntries = try BibliographyService.parseCrossRefWorksJSON(crossRefJSON)
        #expect(crossRefEntries.count == 1)
        if let first = crossRefEntries.first {
            #expect(first.entryType == "inproceedings")
            #expect(first.year == "2017")
            #expect(first.author.contains("Ashish Vaswani"))
            #expect(!first.title.contains("\\write18"))
            #expect(first.title.contains("\\&"))
            #expect(first.rawBibTeX.contains("@inproceedings{"))
        }

        // Balanced-brace BibTeX parsing & collision merging
        let bibSample = """
        @article{knuth1984,
          author = {Donald E. Knuth},
          title = {Literate {Programming} in {TeX}},
          journal = {The Computer Journal},
          year = {1984}
        }
        """
        let parsed = try BibliographyService.parseBibContent(bibSample)
        #expect(parsed.count == 1)
        #expect(parsed.first?.key == "knuth1984")
        #expect(parsed.first?.title == "Literate {Programming} in {TeX}")

        let duplicate = BibEntry(
            key: "knuth1984",
            entryType: "book",
            title: "The TeXbook",
            author: "Donald E. Knuth",
            year: "1984"
        )
        let merged = BibliographyService.mergeEntries([duplicate], intoExistingBibContent: bibSample, replaceDuplicates: false)
        #expect(merged.duplicateKeys == ["knuth1984"])
        #expect(merged.addedKeys == ["knuth19842"])
        let reparsed = try BibliographyService.parseBibContent(merged.mergedContent)
        #expect(reparsed.count == 2)

        // Malformed BibTeX throws line-numbered error
        let badBib = "\n\n@article{unclosed,\n  title = {Missing brace}"
        do {
            _ = try BibliographyService.parseBibContent(badBib, strict: true)
            Issue.record("Expected BibTeXError.syntaxError")
        } catch let err as BibTeXError {
            if case .syntaxError(let line, _) = err {
                #expect(line == 3)
            } else {
                Issue.record("Unexpected error variant: \(err)")
            }
        }

        // Multi-command citation & ref extraction
        let texSource = """
        See \\parencite[p. 4]{knuth1984, vaswani2017} and \\textcite{doe2024}.
        Compare \\cref{fig:results} with \\eqref{eq:loss}.
        """
        let citeUses = BibliographyService.extractCitations(from: texSource)
        #expect(citeUses.map(\.key) == ["knuth1984", "vaswani2017", "doe2024"])
        let refUses = BibliographyService.extractReferences(from: texSource)
        #expect(refUses.map(\.label) == ["fig:results", "eq:loss"])

        // Symlinked .bib file rejected
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("LaTeXaPBibSec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let realBib = tempDir.appendingPathComponent("real.bib")
        let linkBib = tempDir.appendingPathComponent("link.bib")
        try bibSample.write(to: realBib, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: linkBib, withDestinationURL: realBib)
        #expect(throws: BibTeXError.self) {
            _ = try BibliographyService.parseBibFile(at: linkBib)
        }
    }

    @Test func academicPreflightChecksAndErrorDemystifier() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("LaTeXaPPreflight-\(UUID().uuidString)", isDirectory: true)
        let figsDir = tempDir.appendingPathComponent("figures", isDirectory: true)
        try FileManager.default.createDirectory(at: figsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: figsDir.appendingPathComponent("valid.png"))

        let entries = [
            BibEntry(key: "smith2024", entryType: "article", title: "Paper", author: "Smith", year: "2024"),
            BibEntry(key: "unused2020", entryType: "article", title: "Unused", author: "Old", year: "2020")
        ]
        let sourceWithIssues = #"""
        \documentclass{article}
        \usepackage{graphicx}
        \begin{document}
        \section{Intro}\label{sec:intro}
        We cite \parencite{smith2024} and \cite{missing2025}.
        See Section~\ref{sec:missing}.
        \includegraphics{figures/valid.png}
        \includegraphics{figures/nope.png}
        \includegraphics{/Users/someone/Desktop/abs.png}
        \end{document}
        """#

        let report = AcademicPreflightService.analyze(
            source: sourceWithIssues,
            bibEntries: entries,
            diagnostics: [LaTeXDiagnostic(line: 5, severity: .info, message: "Overfull \\hbox (8.2pt too wide) in paragraph at lines 5--5")],
            documentDirectory: tempDir,
            stats: AcademicDocumentStats(proseWordCount: 1200, abstractWordCount: 300, pageCount: 10),
            rubricTargets: RubricTargetConfig(targetProseWords: 1000, maxPageCount: 8, maxAbstractWords: 250)
        )
        #expect(!report.isSubmissionReady)
        #expect(report.unresolvedCitations == ["missing2025"])
        #expect(report.unresolvedReferences == ["sec:missing"])
        #expect(report.uncitedBibKeys == ["unused2020"])
        #expect(report.missingFigurePaths.contains("figures/nope.png"))
        #expect(report.missingFigurePaths.contains("/Users/someone/Desktop/abs.png"))
        #expect(report.items.contains(where: { $0.category == "Budget" }))
        #expect(report.items.contains(where: { $0.id == "missing-pkg-biblatex" && $0.fixOperation != nil }))

        // Clean source passes preflight
        let cleanSource = #"""
        \documentclass{article}
        \usepackage{graphicx}
        \usepackage[style=apa,backend=biber]{biblatex}
        \begin{document}
        \section{Intro}\label{sec:intro}
        See Section~\ref{sec:intro} and \parencite{smith2024}.
        \includegraphics{figures/valid.png}
        \end{document}
        """#
        let cleanReport = AcademicPreflightService.analyze(
            source: cleanSource,
            bibEntries: [entries[0]],
            diagnostics: [],
            documentDirectory: tempDir
        )
        #expect(cleanReport.isSubmissionReady)
        #expect(cleanReport.items.isEmpty)

        // Error Demystifier mapping
        let rawDoc = #"""
        \documentclass{article}
        \begin{document}
        Research & Development is fun.
        score_value = 42
        \qty{9.81}{m/s^2}
        \textbf{unclosed
        \end{document}
        """#
        let diags = [
            LaTeXDiagnostic(line: 3, severity: .error, message: "Misplaced alignment tab character &."),
            LaTeXDiagnostic(line: 4, severity: .error, message: "Missing $ inserted."),
            LaTeXDiagnostic(line: 5, severity: .error, message: "Undefined control sequence."),
            LaTeXDiagnostic(line: 6, severity: .error, message: "Runaway argument?")
        ]
        let demystified = ContextSuggestionsEngine.demystify(diagnostics: diags, source: rawDoc)
        #expect(demystified.count == 4)
        #expect(demystified[0].shortTitle.contains("'&'"))
        if case .replaceLine(let line, _, let replacement) = demystified[0].fixOperation {
            #expect(line == 3)
            #expect(replacement.contains("\\&"))
        } else {
            Issue.record("Expected replaceLine fix for unescaped &")
        }
        if case .replaceLine(let line, _, let replacement) = demystified[1].fixOperation {
            #expect(line == 4)
            #expect(replacement.contains("\\_"))
        } else {
            Issue.record("Expected replaceLine fix for underscore")
        }
        #expect(demystified[2].fixOperation == .insertPackage(packageName: "siunitx", options: ""))
        #expect(demystified[3].fixOperation == .appendMissingBrace(lineNumber: 6))
    }

    @Test func academicToolsGridCSVPGFPlotsAndSubfigures() {
        let csv = "Model, \"Accuracy, (%)\", Notes\nBaseline, 81.2, A & B\nOurs, 93.4, $x^2$ fast"
        let grid = AcademicToolsGenerator.csvToTableGrid(csv)
        #expect(grid.headers == ["Model", "Accuracy, (%)", "Notes"])
        #expect(grid.rows.count == 2)
        #expect(grid.rows[0][2] == "A & B")

        let roundtripCSV = AcademicToolsGenerator.tableGridToCSV(grid)
        #expect(roundtripCSV.contains("\"Accuracy, (%)\""))

        let booktabs = AcademicToolsGenerator.generateBooktabsTable(from: grid)
        #expect(booktabs.contains("\\toprule"))
        #expect(booktabs.contains("A \\& B"))
        #expect(booktabs.contains("Accuracy, (\\%)"))
        #expect(booktabs.contains("$x^2$"))

        // Numeric Line Chart
        let lineCfg = PGFPlotChartConfig(
            chartType: .line,
            title: "Training & Validation Loss",
            xLabel: "Epoch",
            yLabel: "Loss (%)",
            csvText: "Epoch, Train Loss\n1, 1.2\n2, 0.7\n3, 0.35"
        )
        let lineTeX = AcademicToolsGenerator.generatePGFPlotChart(from: lineCfg)
        #expect(lineTeX.contains("\\begin{axis}["))
        #expect(lineTeX.contains("Training \\& Validation Loss"))
        #expect(lineTeX.contains("(1, 1.2) (2, 0.7) (3, 0.35)"))

        // Categorical Bar Chart uses symbolic x coords
        let barCfg = PGFPlotChartConfig(
            chartType: .bar,
            title: "Benchmark",
            xLabel: "System",
            yLabel: "Score",
            csvText: "System, Score\nAlpha, 84\nBeta, 92"
        )
        let barTeX = AcademicToolsGenerator.generatePGFPlotChart(from: barCfg)
        #expect(barTeX.contains("ybar"))
        #expect(barTeX.contains("symbolic x coords={Alpha,Beta}"))

        // Side-by-side Subfigures + traversal guard
        let figCfg = FigureInsertConfig(
            primaryRelativePath: "../outside/a.png",
            secondaryRelativePath: "figures/b.png",
            widthFraction: 0.9,
            placement: "htbp",
            caption: "A & B Comparison",
            label: "comp-fig",
            primarySubcaption: "First",
            secondarySubcaption: "Second"
        )
        let figTeX = AcademicToolsGenerator.generateFigureSnippet(from: figCfg)
        #expect(figTeX.contains("\\begin{subfigure}"))
        #expect(!figTeX.contains("../outside"))
        #expect(figTeX.contains("figures/a.png"))
        #expect(figTeX.contains("figures/b.png"))
        #expect(figTeX.contains("\\label{fig:comp-fig}"))
    }

    @Test func latexAwareProseSpellCheckMaskingAndSuggestions() {
        let doc = #"""
        \documentclass{article}
        \title{TypppoInPreambleShouldBeIgnored}
        \ExplSyntaxOn
        \tl_new:N \l_typppo_ignored_tl
        \ExplSyntaxOff
        \begin{document}
        % Commetn typo should be ignored
        See \parencite{nonexistentkey} and \ref{fig:badkeyname}.
        Equation $x_{typppo} + y = z$ and command \textbf{recieve}.
        \begin{equation}
          \alpha_{typppo} = 1
        \end{equation}
        Thiss sentnce has clear mispellings.
        \end{document}
        """#

        let masked = LaTeXSpellCheckService.maskedProseString(from: doc)
        #expect((masked as NSString).length == (doc as NSString).length)
        #expect(!masked.contains("TypppoInPreambleShouldBeIgnored"))
        #expect(!masked.contains("l_typppo_ignored_tl"))
        #expect(!masked.contains("Commetn"))
        #expect(!masked.contains("nonexistentkey"))
        #expect(!masked.contains("badkeyname"))
        #expect(!masked.contains("typppo"))
        #expect(masked.contains("recieve"))
        #expect(masked.contains("Thiss"))

        let issues = LaTeXSpellCheckService.scan(source: doc)
        let issueWords = Set(issues.map(\.word))
        #expect(!issueWords.contains("TypppoInPreambleShouldBeIgnored"))
        #expect(!issueWords.contains("nonexistentkey"))
        #expect(!issueWords.contains("typppo"))
        #expect(!issueWords.isDisjoint(with: ["recieve", "Thiss", "sentnce", "mispellings"]))
        if let hit = issues.first(where: { $0.word == "recieve" }) {
            #expect(hit.line == 9)
            #expect(hit.suggestions.contains("receive"))
        }
    }

    @Test func academicStatisticsAndPaperSetupWizardTemplates() {
        let tex = #"""
        \documentclass{article}
        \begin{document}
        \begin{abstract}
        This concise abstract contains eight simple prose words.
        \end{abstract}
        \section{Introduction}
        Only body prose words belong here \parencite{ref1}.
        \begin{equation}
        E = m c^2
        \end{equation}
        \begin{table}
        \begin{tabular}{cc}
        ColA & ColB \\
        \end{tabular}
        \end{table}
        \includegraphics{figures/fig1.png}
        \end{document}
        """#
        let stats = Expl3Linter.computeAcademicStatistics(
            source: tex,
            bibEntries: [BibEntry(key: "ref1", entryType: "article", title: "T", author: "A", year: "2024")],
            pageCount: 4
        )
        #expect(stats.abstractWordCount == 8)
        #expect(stats.figureCount == 1)
        #expect(stats.tableCount == 1)
        #expect(stats.referenceCount == 1)
        #expect(stats.pageCount == 4)
        #expect(stats.proseWordCount >= 12 && stats.proseWordCount <= 18)

        // All 7 academic templates and 10 packages present
        let templateIDs = Set(LaTeXCatalog.templates.map(\.id))
        for expectedID in ["apa7-student", "ieee-conference", "acm-article", "mla-essay", "stem-lab-report", "university-thesis", "beamer-slides"] {
            #expect(templateIDs.contains(expectedID))
        }
        let pkgNames = Set(LaTeXCatalog.commonPackages.map(\.package))
        for expectedPkg in ["biblatex", "natbib", "pgfplots", "subcaption", "setspace", "lineno", "apa7", "IEEEtran", "acmart", "mhchem"] {
            #expect(pkgNames.contains(expectedPkg))
        }

        // Paper Wizard generation applies blind review, double spacing, and sanitizes metadata
        let wizardCfg = PaperSetupConfig(
            templateId: "apa7-student",
            title: "AI & Society: 100% Ready",
            author: "Jane Doe",
            institution: "State University",
            courseOrVenue: "CS 401",
            paperSize: .a4paper,
            baseFontSizePt: 11,
            doubleSpacing: true,
            anonymizedBlindReview: true,
            bibliographyStyle: .ieee
        )
        let generated = LaTeXCatalog.generateWizardDocument(from: wizardCfg)
        #expect(generated.contains("\\documentclass[11pt,a4paper]{article}"))
        #expect(generated.contains("AI \\& Society: 100\\% Ready"))
        #expect(generated.contains("Anonymous Author(s)"))
        #expect(!generated.contains("Jane Doe"))
        #expect(generated.contains("\\usepackage{lineno}"))
        #expect(generated.contains("\\linenumbers"))
        #expect(generated.contains("\\doublespacing"))
        #expect(generated.contains("style=ieee"))
    }

    @Test func tectonicStagingAndSubmissionBundleExportAndSecurity() async throws {
        // 1x1 transparent PNG
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        let pngData = Data(base64Encoded: pngBase64)!

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaTeXaPExportTests-\(UUID().uuidString)", isDirectory: true)
        let projDir = tempRoot.appendingPathComponent("Project", isDirectory: true)
        let figsDir = projDir.appendingPathComponent("figures", isDirectory: true)
        try FileManager.default.createDirectory(at: figsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let figURL = figsDir.appendingPathComponent("chart.png")
        try pngData.write(to: figURL)

        // Create an outside secret file & symlinked figure to verify security guards
        let secretURL = tempRoot.appendingPathComponent("secret.png")
        try pngData.write(to: secretURL)
        let symlinkFigURL = figsDir.appendingPathComponent("symlinked.png")
        try FileManager.default.createSymbolicLink(at: symlinkFigURL, withDestinationURL: secretURL)

        let source = #"""
        \documentclass{article}
        \usepackage{graphicx}
        \author{Real Author Name}
        \begin{document}
        % Secret internal comment
        Hello World.
        \begin{figure}[htbp]
          \centering
          \includegraphics[width=0.5\textwidth]{figures/chart.png}
        \end{figure}
        \includegraphics{figures/symlinked.png}
        \input{../secret}
        \end{document}
        """#

        let bibContent = """
        @article{demo2026,
          author = {Author, A.},
          title = {Demo Paper},
          year = {2026}
        }
        """

        // 1. Verify TectonicService stages figures/ and references.bib into buildDir and ignores traversal keys
        let tectonic = TectonicService()
        let compileRes = await tectonic.compile(
            source: #"""
            \documentclass{article}
            \usepackage{graphicx}
            \begin{document}
            \includegraphics[width=0.4\textwidth]{figures/chart.png}
            \end{document}
            """#,
            documentDirectory: nil,
            fontDirectories: [],
            additionalTextFiles: ["references.bib": bibContent, "../escape.bib": "bad"],
            assetSearchDirectories: [figsDir]
        )
        #expect(compileRes.success, "Expected staged figure compilation to pass. Log: \(compileRes.logOutput)")

        // 2. Verify SubmissionExportService produces clean .zip with anonymization + comment stripping + security guards
        let zipURL = tempRoot.appendingPathComponent("my-submission.zip")
        let exportResult = try await SubmissionExportService.exportBundle(
            source: source,
            mainFileName: "paper.tex",
            destinationZipURL: zipURL,
            managedBibContent: bibContent,
            documentDirectory: projDir,
            stripComments: true,
            anonymize: true,
            verifyCompileWithTectonic: false
        )
        #expect(FileManager.default.fileExists(atPath: exportResult.zipURL.path))
        #expect(exportResult.includedFiles.contains("paper.tex"))
        #expect(exportResult.includedFiles.contains("references.bib"))
        #expect(exportResult.includedFiles.contains("figures/chart.png"))
        #expect(!exportResult.includedFiles.contains("figures/symlinked.png"))
        #expect(exportResult.preflightWarnings.contains(where: { $0.contains("../secret") }))

        // Inspect extracted contents via ditto
        let unpackDir = tempRoot.appendingPathComponent("Unpacked", isDirectory: true)
        try FileManager.default.createDirectory(at: unpackDir, withIntermediateDirectories: true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-x", "-k", zipURL.path, unpackDir.path]
        try proc.run()
        proc.waitUntilExit()
        #expect(proc.terminationStatus == 0)

        let bundledTeX = try String(
            contentsOf: unpackDir.appendingPathComponent("my-submission/paper.tex"),
            encoding: .utf8
        )
        #expect(!bundledTeX.contains("Real Author Name"))
        #expect(bundledTeX.contains("Anonymous Author(s)"))
        #expect(bundledTeX.contains("\\linenumbers"))
        #expect(!bundledTeX.contains("Secret internal comment"))
    }

    @Test @MainActor func documentViewModelAcademicWorkflows() async throws {
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        let pngData = Data(base64Encoded: pngBase64)!

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaTeXaPVMAcademic-\(UUID().uuidString)", isDirectory: true)
        let storageDir = tempRoot.appendingPathComponent("Fonts", isDirectory: true)
        let tempFigs = tempRoot.appendingPathComponent("TempFigures", isDirectory: true)
        let sourceStaging = tempRoot.appendingPathComponent("SourceImages", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceStaging, withIntermediateDirectories: true)

        let suiteName = "LaTeXaPAcademicTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let vm = DocumentViewModel(
            initialTemplate: LaTeXCatalog.defaultTemplate,
            fontLibraryService: FontLibraryService(storageDirectory: storageDir),
            userDefaults: defaults,
            tempFiguresDirectory: tempFigs,
            compileOnInit: false
        )
        vm.autoCompileEnabled = false

        // 1. Rubric Targets + Spellcheck persistence
        vm.updateRubricTargets(RubricTargetConfig(targetProseWords: 2000, maxPageCount: 6, maxAbstractWords: 200, studentModeHideExpl3: true))
        vm.proseSpellCheckEnabled = true

        let vm2 = DocumentViewModel(
            initialTemplate: LaTeXCatalog.defaultTemplate,
            fontLibraryService: FontLibraryService(storageDirectory: storageDir),
            userDefaults: defaults,
            tempFiguresDirectory: tempFigs,
            compileOnInit: false
        )
        #expect(vm2.rubricTargets.targetProseWords == 2000)
        #expect(vm2.rubricTargets.studentModeHideExpl3 == true)
        #expect(vm2.proseSpellCheckEnabled == true)

        // 2. Bib import, style switch, and caret citation insertion
        let sampleEntry = BibEntry(
            key: "vaswani2017attention",
            entryType: "inproceedings",
            title: "Attention Is All You Need",
            author: "Ashish Vaswani",
            year: "2017"
        )
        vm.importBibEntry(sampleEntry)
        #expect(vm.managedBibContent.contains("vaswani2017attention"))
        #expect(vm.bibEntries.contains(where: { $0.key == "vaswani2017attention" }))

        vm.applyBibliographyStyle(.ieee)
        #expect(vm.sourceText.contains("style=ieee"))
        #expect(vm.sourceText.contains("\\addbibresource{references.bib}"))

        vm.insertFormattedCitation(sampleEntry, style: .parencite, pageLocator: "p. 7")
        #expect(vm.pendingEditorInsertion?.text == "\\parencite[p. 7]{vaswani2017attention}")

        // 3. Blind review & double spacing toggles
        vm.toggleBlindReview(true)
        #expect(vm.isBlindReviewEnabled)
        #expect(vm.sourceText.contains("\\linenumbers"))
        vm.toggleBlindReview(false)
        #expect(!vm.sourceText.contains("\\linenumbers"))

        vm.toggleDoubleSpacing(true)
        #expect(vm.isDoubleSpacedEnabled)
        #expect(vm.sourceText.contains("\\doublespacing"))
        vm.toggleDoubleSpacing(false)
        #expect(!vm.sourceText.contains("\\doublespacing"))

        // 4. 1-Click Academic Fix Operations
        vm.sourceText = "\\documentclass{article}\n\\begin{document}\nA & B\n\\end{document}"
        vm.applyAcademicFix(.replaceLine(lineNumber: 3, originalSubstring: "A & B", replacement: "A \\& B"))
        #expect(vm.sourceText.contains("A \\& B"))
        vm.applyAcademicFix(.insertPackage(packageName: "booktabs", options: ""))
        #expect(vm.sourceText.contains("\\usepackage{booktabs}"))

        // 5. Spreadsheet Table, PGFPlot Chart & Relative Figure insertion
        vm.insertSpreadsheetTable()
        #expect(vm.pendingEditorInsertion?.text.contains("\\begin{table}") == true)

        vm.insertPGFPlotChart()
        #expect(vm.sourceText.contains("\\usepackage{pgfplots}"))
        #expect(vm.pendingEditorInsertion?.text.contains("\\begin{axis}") == true)

        let rawImg = sourceStaging.appendingPathComponent("My Plot.png")
        try pngData.write(to: rawImg)
        vm.insertFigureWithConfig(
            sourceURL: rawImg,
            secondaryURL: nil,
            config: FigureInsertConfig(caption: "Loss curve", label: "fig:loss")
        )
        #expect(vm.sourceText.contains("\\usepackage{graphicx}"))
        #expect(vm.pendingEditorInsertion?.text.contains("figures/My-Plot.png") == true)
        #expect(FileManager.default.fileExists(atPath: tempFigs.appendingPathComponent("My-Plot.png").path))

        // 6. Autocomplete supports \parencite and \textcite from managed bibEntries
        let citeDoc = "\\textcite{vas"
        let q = LaTeXAutoCompleteEngine.extractQuery(in: citeDoc, cursorLocation: (citeDoc as NSString).length)
        #expect(q?.enclosingCommand == "cite")
        if let q {
            let suggestions = LaTeXAutoCompleteEngine.suggestions(for: q, in: citeDoc, bibEntries: vm.bibEntries)
            #expect(suggestions.first?.trigger == "vaswani2017attention")
        }
    }

    @Test @MainActor func phase3SecurityAndEdgeCaseRegressions() async throws {
        // 1. Inline math brace-breakout & command allowlist (#44 Finding 1)
        let braceBreakout = AcademicSanitizer.escapeLaTeXText(#"Title $}$ \def\x{evil}$"#, allowSafeInlineMath: true)
        #expect(!braceBreakout.contains(#"\def"#))
        #expect(!braceBreakout.contains("}$"))
        #expect(braceBreakout.contains(#"\$"#))
        #expect(braceBreakout.contains(#"\}"#))

        let csnameAttack = AcademicSanitizer.escapeLaTeXText(#"$\csname openin\endcsname$"#, allowSafeInlineMath: true)
        #expect(!csnameAttack.contains(#"\csname"#))
        #expect(csnameAttack.contains(#"\textbackslash{}"#))

        let safeMath = AcademicSanitizer.escapeLaTeXText(#"Accuracy $10^{-3}$ with $\alpha$"#, allowSafeInlineMath: true)
        #expect(safeMath == #"Accuracy $10^{-3}$ with $\alpha$"#)

        // 2. Unsanitized network BibEntry & \bibitem passthrough (#44 Finding 2)
        let dirtyEntry = BibEntry(
            key: "evil}{\\write18{id}",
            entryType: "article",
            title: #"Paper Title}\input{/etc/passwd}"#,
            author: #"Alice \immediate\write18{ls}"#,
            year: "2026}{bad",
            venue: "Conf % secret",
            rawBibTeX: "@preamble{\"\\write18{pwn}\"}\n@article{evil, title={raw}}"
        )
        let sanitizedNet = BibliographyService.sanitizeNetworkEntry(dirtyEntry)
        #expect(!sanitizedNet.rawBibTeX.contains("@preamble"))
        #expect(!sanitizedNet.rawBibTeX.contains(#"\write18"#))
        #expect(!sanitizedNet.rawBibTeX.contains(#"\input"#))
        #expect(sanitizedNet.rawBibTeX.contains(#"\%"#))

        // 3. SSRF validation for RFC1918, CGNAT, IPv6 ULA/link-local/mapped, localhost, single-label (#44 Finding 3)
        let blockedURLs = [
            "http://172.16.0.1/meta",
            "http://172.31.255.254/",
            "http://100.64.0.1/cgnat",
            "http://10.0.0.1/internal",
            "http://192.168.1.1/",
            "http://169.254.169.254/latest/meta-data/",
            "http://127.0.0.1:8080/",
            "http://0.0.0.0/",
            "http://[::1]/",
            "http://[fe80::1]/",
            "http://[fc00::1]/",
            "http://[fd12:3456:789a::1]/",
            "http://[::ffff:127.0.0.1]/",
            "http://[::ffff:172.16.0.5]/",
            "http://localhost/admin",
            "http://api.internal/secret",
            "http://printer.local/",
            "http://intranet/path",
            "ftp://example.org/file"
        ]
        for bad in blockedURLs {
            #expect(BibliographyService.validatedExternalWebURL(bad) == nil, "Expected SSRF guard to block \(bad)")
        }
        #expect(BibliographyService.validatedExternalWebURL("https://example.org/paper") != nil)
        #expect(BibliographyService.validatedExternalWebURL("https://arxiv.org/abs/2305.12345") != nil)

        // 4. PGFPlots finite decimal coordinate enforcement (#44 Finding 5)
        let badPlotCfg = PGFPlotChartConfig(
            chartType: .line,
            title: "Finite Check",
            xLabel: "X",
            yLabel: "Y",
            csvText: "x, y\nnan, 1.0\ninf, 2.0\n0x10, 3.0\n1.5, 4.0"
        )
        let plotTeX = AcademicToolsGenerator.generatePGFPlotChart(from: badPlotCfg)
        #expect(plotTeX.contains("symbolic x coords={nan,inf,0x10,1.5}"))

        let numPlotCfg = PGFPlotChartConfig(
            chartType: .line,
            title: "Numeric Check",
            xLabel: "X",
            yLabel: "Y",
            csvText: "x, y\n1e0, 2.0\n3.00, 4.0"
        )
        let numPlotTeX = AcademicToolsGenerator.generatePGFPlotChart(from: numPlotCfg)
        #expect(!numPlotTeX.contains("symbolic x coords"))
        #expect(numPlotTeX.contains("(1, 2) (3, 4)"))

        // 5. Spellcheck preserves prose inside brackets while masking attached command options (#45 Item 5)
        let bracketDoc = #"""
        \documentclass{article}
        \begin{document}
        Results hold \parencite[p. 12]{smith2024} [see Appndix A] for details.
        \begin{figure}[htbp]
        \centering
        \caption{Figure caption}
        \end{figure}
        \end{document}
        """#
        let maskedBrackets = LaTeXSpellCheckService.maskedProseString(from: bracketDoc)
        #expect(!maskedBrackets.contains("htbp"))
        #expect(!maskedBrackets.contains("smith2024"))
        #expect(maskedBrackets.contains("Appndix"))
        let bracketIssues = LaTeXSpellCheckService.scan(source: bracketDoc)
        #expect(bracketIssues.contains(where: { $0.word == "Appndix" }))

        // 6. Symlinked figures/ directory, dropped-image validation, stale bib reset, & dotted parent dir (#44.4, #44.5, #45.5)
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        let pngData = Data(base64Encoded: pngBase64)!

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaTeXaPPhase3Tests-\(UUID().uuidString)", isDirectory: true)
        let outsideDir = tempRoot.appendingPathComponent("OutsideTarget", isDirectory: true)
        let projWithSymlinkFigs = tempRoot.appendingPathComponent("ProjSymlink", isDirectory: true)
        let cleanProj = tempRoot.appendingPathComponent("CleanProj", isDirectory: true)
        let dottedFigsDir = cleanProj.appendingPathComponent("figures/v1.0", isDirectory: true)
        let isolatedTectonicDir = tempRoot.appendingPathComponent("IsolatedBuild", isDirectory: true)
        let tempFigs = tempRoot.appendingPathComponent("TempFigs", isDirectory: true)
        let storageDir = tempRoot.appendingPathComponent("Fonts", isDirectory: true)

        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projWithSymlinkFigs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dottedFigsDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: projWithSymlinkFigs.appendingPathComponent("figures"),
            withDestinationURL: outsideDir
        )

        let suiteName = "LaTeXaPPhase3VM.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let validImg = tempRoot.appendingPathComponent("valid.png")
        try pngData.write(to: validImg)
        let symlinkImg = tempRoot.appendingPathComponent("evil-link.png")
        try FileManager.default.createSymbolicLink(at: symlinkImg, withDestinationURL: validImg)
        let txtFile = tempRoot.appendingPathComponent("not-image.txt")
        try "hello".write(to: txtFile, atomically: true, encoding: .utf8)

        let vm = DocumentViewModel(
            initialTemplate: LaTeXCatalog.defaultTemplate,
            fontLibraryService: FontLibraryService(storageDirectory: storageDir),
            userDefaults: defaults,
            tempFiguresDirectory: tempFigs,
            compileOnInit: false
        )
        vm.autoCompileEnabled = false

        // Append sanitized \bibitem
        vm.appendBibItemToSource(dirtyEntry)
        #expect(!vm.sourceText.contains(#"\write18"#))
        #expect(!vm.sourceText.contains(#"\input{/etc/passwd}"#))

        // Drop validation rejects symlinks and non-image extensions before opening sheet
        vm.handleDroppedImageURL(symlinkImg)
        #expect(vm.pendingDroppedFigureURL == nil)
        #expect(!vm.showFigureAssistantSheet)

        vm.handleDroppedImageURL(txtFile)
        #expect(vm.pendingDroppedFigureURL == nil)
        #expect(!vm.showFigureAssistantSheet)

        vm.handleDroppedImageURL(validImg)
        #expect(vm.pendingDroppedFigureURL != nil)
        #expect(vm.showFigureAssistantSheet)
        vm.showFigureAssistantSheet = false
        vm.pendingDroppedFigureURL = nil

        // Reject writing into symlinked <docDir>/figures
        let symlinkDocURL = projWithSymlinkFigs.appendingPathComponent("main.tex")
        try "\\documentclass{article}\n\\begin{document}\nHi\n\\end{document}".write(to: symlinkDocURL, atomically: true, encoding: .utf8)
        vm.currentFileURL = symlinkDocURL
        #expect(vm.copyImageAssetToProjectFigures(from: validImg) == nil)
        #expect(!FileManager.default.fileExists(atPath: outsideDir.appendingPathComponent("valid.png").path))

        // Open document without sibling references.bib clears previous managedBibContent
        vm.managedBibContent = "@article{stale, title={Stale}, author={X}, year={2020}}"
        vm.bibLookupError = "Old error"
        vm.bibSearchResults = [dirtyEntry]
        let plotPng = dottedFigsDir.appendingPathComponent("plot.png")
        try pngData.write(to: plotPng)
        let cleanDocURL = cleanProj.appendingPathComponent("paper.tex")
        try "\\documentclass{article}\n\\usepackage{graphicx}\n\\begin{document}\n\\includegraphics{figures/v1.0/plot}\n\\end{document}"
            .write(to: cleanDocURL, atomically: true, encoding: .utf8)

        #expect(vm.loadDocumentFromDisk(at: cleanDocURL))
        #expect(vm.managedBibContent.isEmpty)
        #expect(vm.bibSearchResults.isEmpty)
        #expect(vm.bibLookupError == nil)

        // Preflight pathExtension check probes extension on dotted parent folder `figures/v1.0/plot`
        let report = AcademicPreflightService.analyze(
            source: vm.sourceText,
            bibEntries: [],
            diagnostics: [],
            documentDirectory: cleanProj
        )
        #expect(report.missingFigurePaths.isEmpty)

        // Bundle export also resolves dotted parent folder extensionless figure `figures/v1.0/plot` -> `figures/v1.0/plot.png`
        let dottedZip = tempRoot.appendingPathComponent("dotted-submission.zip")
        let dottedExport = try await SubmissionExportService.exportBundle(
            source: vm.sourceText,
            mainFileName: "paper.tex",
            destinationZipURL: dottedZip,
            documentDirectory: cleanProj,
            verifyCompileWithTectonic: false
        )
        #expect(dottedExport.includedFiles.contains("figures/v1.0/plot.png"))

        // Isolated TectonicService build workspace compiles without touching global workspace
        let isolatedTectonic = TectonicService(workspaceDirectory: isolatedTectonicDir)
        let isoRes = await isolatedTectonic.compile(source: "\\documentclass{article}\\begin{document}Isolated\\end{document}")
        #expect(isoRes.success)
        #expect(isoRes.pdfURL?.path.hasPrefix(isolatedTectonicDir.standardizedFileURL.path) == true)

        // Clean submission bundle export with isolated Tectonic verification compile enabled
        let verifiedZip = tempRoot.appendingPathComponent("verified-submission.zip")
        let verifiedSource = "\\documentclass{article}\n\\usepackage{graphicx}\n\\begin{document}\n\\includegraphics{figures/v1.0/plot.png}\n\\end{document}"
        let verifiedExport = try await SubmissionExportService.exportBundle(
            source: verifiedSource,
            mainFileName: "paper.tex",
            destinationZipURL: verifiedZip,
            documentDirectory: cleanProj,
            verifyCompileWithTectonic: true
        )
        #expect(verifiedExport.compiledCleanly)
        #expect(verifiedExport.includedFiles.contains("figures/v1.0/plot.png"))
    }

    // MARK: - v0.3.0 GitHub Repository Multi-Project Storage Tests

    @Test func gitHubWorkspaceModelsValidationAndAPIParsing() throws {
        // 1. Default human-readable commit message & newline sanitization
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 11
        comps.day = 17
        comps.hour = 14
        comps.minute = 25
        let fixedDate = Calendar(identifier: .gregorian).date(from: comps)!
        let commitMsg = GitHubWorkspaceValidator.defaultCommitMessage(projectName: "CS229\nFinal Paper", at: fixedDate)
        #expect(commitMsg == "Update CS229 Final Paper — 2026-11-17 14:25")

        // 2. Slug validation & slugification
        #expect(GitHubWorkspaceValidator.slugifyProjectName("CS229 Final Paper!") == "cs229-final-paper")
        #expect(GitHubWorkspaceValidator.slugifyProjectName("   ---   ") == "untitled-project")
        #expect(GitHubWorkspaceValidator.isValidProjectSlug("cs229-final-paper"))
        #expect(!GitHubWorkspaceValidator.isValidProjectSlug("../evil"))
        #expect(!GitHubWorkspaceValidator.isValidProjectSlug("-leading"))
        #expect(!GitHubWorkspaceValidator.isValidProjectSlug("UpperCase"))
        #expect(!GitHubWorkspaceValidator.isValidProjectSlug(""))
        #expect(!GitHubWorkspaceValidator.isValidProjectSlug(String(repeating: "a", count: 65)))

        // 3. Branch & commit SHA allowlists
        #expect(GitHubWorkspaceValidator.validatedBranchName("main") == "main")
        #expect(GitHubWorkspaceValidator.validatedBranchName("paper/draft-2") == "paper/draft-2")
        #expect(GitHubWorkspaceValidator.validatedBranchName("-evil") == nil)
        #expect(GitHubWorkspaceValidator.validatedBranchName("main..evil") == nil)
        #expect(GitHubWorkspaceValidator.validatedBranchName("main@{1}") == nil)
        #expect(GitHubWorkspaceValidator.validatedCommitSHA("a1b2c3d") == "a1b2c3d")
        #expect(GitHubWorkspaceValidator.validatedCommitSHA("abc") == nil)
        #expect(GitHubWorkspaceValidator.validatedCommitSHA("zzzzzzz") == nil)

        // 4. Remote URL allowlist in production mode
        let httpsParsed = GitHubWorkspaceValidator.parseAndValidateRemoteURL("https://github.com/octocat/research-papers")
        #expect(httpsParsed?.owner == "octocat")
        #expect(httpsParsed?.repo == "research-papers")
        #expect(httpsParsed?.normalizedURL == "https://github.com/octocat/research-papers.git")
        #expect(httpsParsed?.suggestedAuth == .personalAccessToken)

        let sshParsed = GitHubWorkspaceValidator.parseAndValidateRemoteURL("git@github.com:octocat/research-papers.git")
        #expect(sshParsed?.normalizedURL == "git@github.com:octocat/research-papers.git")
        #expect(sshParsed?.suggestedAuth == .sshKey)

        let shortParsed = GitHubWorkspaceValidator.parseAndValidateRemoteURL("octocat/research-papers")
        #expect(shortParsed?.normalizedURL == "https://github.com/octocat/research-papers.git")

        let dangerousRemotes = [
            "file:///etc/passwd",
            "/tmp/local.git",
            "ext::sh -c id",
            "fd::0",
            "http://github.com/octocat/papers.git",
            "https://user:secret@github.com/octocat/papers.git",
            "https://evil.com/octocat/papers.git",
            "octocat/../etc"
        ]
        for bad in dangerousRemotes {
            #expect(GitHubWorkspaceValidator.parseAndValidateRemoteURL(bad) == nil, "Expected remote URL to be rejected: \(bad)")
        }

        // 5. Token redaction & .gitignore generation
        let redacted = GitHubWorkspaceValidator.redactSensitiveToken(
            "fatal: could not read from https://ghp_supersecret123@github.com/a/b.git token ghp_supersecret123",
            token: "ghp_supersecret123"
        )
        #expect(!redacted.contains("ghp_supersecret123"))
        #expect(redacted.contains("[REDACTED]"))

        let ignoreNoPDF = GitHubWorkspaceValidator.laTeXGitIgnore(includePDFs: false)
        #expect(ignoreNoPDF.contains("*.aux"))
        #expect(ignoreNoPDF.contains("*.pdf"))
        let ignoreWithPDF = GitHubWorkspaceValidator.laTeXGitIgnore(includePDFs: true)
        #expect(ignoreWithPDF.contains("*.aux"))
        #expect(!ignoreWithPDF.contains("*.pdf"))

        // 6. GitHubAPIService JSON parsing
        let userJSON = Data(#"{"login":"academic-dev","name":"Jane Scholar"}"#.utf8)
        let parsedUser = try GitHubAPIService.parseAuthenticatedUserJSON(userJSON)
        #expect(parsedUser.login == "academic-dev")
        #expect(parsedUser.name == "Jane Scholar")

        let reposJSON = Data(#"""
        [
          {
            "id": 42,
            "name": "latex-papers",
            "full_name": "academic-dev/latex-papers",
            "clone_url": "https://github.com/academic-dev/latex-papers.git",
            "ssh_url": "git@github.com:academic-dev/latex-papers.git",
            "default_branch": "main",
            "private": true,
            "updated_at": "2026-11-17T12:00:00Z",
            "owner": {"login": "academic-dev"}
          }
        ]
        """#.utf8)
        let parsedRepos = try GitHubAPIService.parseRepositoriesJSON(reposJSON)
        #expect(parsedRepos.count == 1)
        #expect(parsedRepos.first?.isPrivate == true)
        #expect(parsedRepos.first?.fullName == "academic-dev/latex-papers")

        // 7. InMemoryGitCredentialStore CRUD
        let memCreds = InMemoryGitCredentialStore(cliToken: "gho_cli_test")
        try memCreds.saveToken("ghp_abc", forAccount: "academic-dev/latex-papers")
        #expect(memCreds.loadToken(forAccount: "academic-dev/latex-papers") == "ghp_abc")
        #expect(memCreds.detectGitHubCLIToken() == "gho_cli_test")
        try memCreds.deleteToken(forAccount: "academic-dev/latex-papers")
        #expect(memCreds.loadToken(forAccount: "academic-dev/latex-papers") == nil)

        // 8. Git output parsers
        let porcelain = """
         M projects/paper-1/main.tex
        ?? projects/paper-1/figures/fig1.png
        UU projects/paper-1/references.bib
        """
        let changes = GitRepositoryService.parsePorcelainStatus(porcelain)
        #expect(changes.count == 3)
        #expect(changes[0].status == "M")
        #expect(changes[1].status == "A")
        #expect(changes[2].status == "U")

        let logSample = "\u{1e}0123456789abcdef0123456789abcdef01234567\u{1f}0123456\u{1f}Jane\u{1f}1763389500\u{1f}Update Paper — 2026-11-17\nprojects/paper-1/main.tex\n"
        let parsedLog = GitRepositoryService.parseGitLogOutput(logSample, unpushedSHAs: ["0123456789abcdef0123456789abcdef01234567"])
        #expect(parsedLog.count == 1)
        #expect(parsedLog[0].shortHash == "0123456")
        #expect(parsedLog[0].isPushed == false)
        #expect(parsedLog[0].changedFiles == ["projects/paper-1/main.tex"])
    }

    @Test func gitRepositoryServiceSecurityAndGuards() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaTeXaPGitSec-\(UUID().uuidString)", isDirectory: true)
        let reposRoot = tempRoot.appendingPathComponent("Repos", isDirectory: true)
        let repoDir = reposRoot.appendingPathComponent("local-test", isDirectory: true)
        let projectDir = repoDir.appendingPathComponent("projects/demo-paper", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let outsideSecret = tempRoot.appendingPathComponent("secret.txt")
        try "SECRET".write(to: outsideSecret, atomically: true, encoding: .utf8)

        let prodService = GitRepositoryService(
            repositoriesRootDirectory: reposRoot,
            credentialStore: InMemoryGitCredentialStore()
        )
        // Production service refuses local/file remotes
        #expect(await prodService.parseRemoteURL("file:///tmp/repo.git") == nil)
        #expect(await prodService.parseRemoteURL("/tmp/repo.git") == nil)

        let connection = GitHubRepoConnection(
            owner: "local",
            repoName: "test",
            remoteURLString: tempRoot.appendingPathComponent("bare.git").path,
            branch: "main",
            authMethod: .sshKey,
            localFolderName: "local-test"
        )
        let proj = AcademicProjectDescriptor(slug: "demo-paper", displayName: "Demo Paper")

        // 1. Symlink inside project blocks commitProjectChanges before staging
        let symInProject = projectDir.appendingPathComponent("escape.tex")
        try FileManager.default.createSymbolicLink(at: symInProject, withDestinationURL: outsideSecret)
        do {
            _ = try await prodService.commitProjectChanges(
                in: repoDir,
                connection: connection,
                project: proj,
                message: "Attempt symlink",
                pushAfterCommit: false,
                token: nil
            )
            Issue.record("Expected securityViolation for symlink inside project")
        } catch let err as GitStorageError {
            if case .securityViolation = err {
                // Expected
            } else {
                Issue.record("Unexpected error: \(err)")
            }
        }
        try? FileManager.default.removeItem(at: symInProject)

        // 2. Oversized file (> 50 MB) is blocked before git add
        let hugeFile = projectDir.appendingPathComponent("huge-dataset.bin")
        FileManager.default.createFile(atPath: hugeFile.path, contents: nil)
        let fh = try FileHandle(forWritingTo: hugeFile)
        try fh.truncate(atOffset: 51 * 1024 * 1024)
        try fh.close()
        do {
            _ = try await prodService.commitProjectChanges(
                in: repoDir,
                connection: connection,
                project: proj,
                message: "Attempt oversized file",
                pushAfterCommit: false,
                token: nil
            )
            Issue.record("Expected fileSizeExceedsGitHubLimit error")
        } catch let err as GitStorageError {
            if case .fileSizeExceedsGitHubLimit = err {
                // Expected
            } else {
                Issue.record("Unexpected error: \(err)")
            }
        }
        try? FileManager.default.removeItem(at: hugeFile)

        // 3. Import loose .tex file rejects path traversal and symlinks
        let linkTeX = repoDir.appendingPathComponent("link-paper.tex")
        try FileManager.default.createSymbolicLink(at: linkTeX, withDestinationURL: outsideSecret)
        await #expect(throws: GitStorageError.self) {
            _ = try await prodService.importLooseTeXFileIntoProject(
                in: repoDir,
                connection: connection,
                relativeTeXPath: "../secret.txt",
                displayName: "Bad",
                token: nil
            )
        }
        await #expect(throws: GitStorageError.self) {
            _ = try await prodService.importLooseTeXFileIntoProject(
                in: repoDir,
                connection: connection,
                relativeTeXPath: "link-paper.tex",
                displayName: "Bad Link",
                token: nil
            )
        }
    }

    @Test @MainActor func gitHubMultiProjectEndToEndWorkflowWithOfflineBareRepo() async throws {
        guard let gitBin = GitRepositoryService.locateGitBinary() else {
            Issue.record("git binary not found on macOS runner")
            return
        }

        func runRawGit(_ args: [String], in dir: URL) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: gitBin)
            p.currentDirectoryURL = dir
            p.arguments = args
            var env = ProcessInfo.processInfo.environment
            env["GIT_TERMINAL_PROMPT"] = "0"
            env["GIT_AUTHOR_NAME"] = "Test Collaborator"
            env["GIT_AUTHOR_EMAIL"] = "collab@example.com"
            env["GIT_COMMITTER_NAME"] = "Test Collaborator"
            env["GIT_COMMITTER_EMAIL"] = "collab@example.com"
            p.environment = env
            let errPipe = Pipe()
            p.standardOutput = Pipe()
            p.standardError = errPipe
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw GitStorageError.commandFailed("git \(args.joined(separator: " ")) failed: \(err)")
            }
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaTeXaPGitE2E-\(UUID().uuidString)", isDirectory: true)
        let bareRepoURL = tempRoot.appendingPathComponent("academic-remote.git", isDirectory: true)
        let seedCloneURL = tempRoot.appendingPathComponent("seed-clone", isDirectory: true)
        let collabCloneURL = tempRoot.appendingPathComponent("collab-clone", isDirectory: true)
        let appReposRoot = tempRoot.appendingPathComponent("AppRepositories", isDirectory: true)
        let fontsDir = tempRoot.appendingPathComponent("Fonts", isDirectory: true)
        let tempFigs = tempRoot.appendingPathComponent("TempFigs", isDirectory: true)

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let suiteName = "LaTeXaPGitE2E.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        // Seed bare remote with an initial commit & loose legacy .tex file on `main`
        try runRawGit(["init", "--bare", "-b", "main", bareRepoURL.path], in: tempRoot)
        try runRawGit(["clone", bareRepoURL.path, seedCloneURL.path], in: tempRoot)
        try runRawGit(["checkout", "-B", "main"], in: seedCloneURL)
        try "# Academic Repo\n".write(to: seedCloneURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "\\documentclass{article}\n\\begin{document}\nLegacy existing paper.\n\\end{document}\n"
            .write(to: seedCloneURL.appendingPathComponent("legacy-notes.tex"), atomically: true, encoding: .utf8)
        try runRawGit(["add", "README.md", "legacy-notes.tex"], in: seedCloneURL)
        try runRawGit(["commit", "-m", "Initial remote setup"], in: seedCloneURL)
        try runRawGit(["push", "-u", "origin", "main"], in: seedCloneURL)

        let gitService = GitRepositoryService(
            repositoriesRootDirectory: appReposRoot,
            credentialStore: InMemoryGitCredentialStore(),
            allowLocalTestBareRemotes: true
        )
        let vm = DocumentViewModel(
            initialTemplate: LaTeXCatalog.defaultTemplate,
            fontLibraryService: FontLibraryService(storageDirectory: fontsDir),
            userDefaults: defaults,
            tempFiguresDirectory: tempFigs,
            compileOnInit: false,
            gitRepositoryService: gitService,
            gitCredentialStore: InMemoryGitCredentialStore()
        )
        vm.autoCompileEnabled = false

        // 1. Connect bare remote repository & verify loose .tex discovery
        await vm.connectGitHubRepository(
            remoteURL: bareRepoURL.path,
            branch: "main",
            authMethod: .sshKey,
            autoPushOnSave: true,
            includePDFsInCommits: false
        )
        #expect(vm.activeRepo != nil)
        #expect(vm.looseRepoTeXFiles == ["legacy-notes.tex"])
        if let activeRepo = vm.activeRepo {
            let localRepoURL = try await gitService.localRepositoryURL(for: activeRepo)
            #expect(FileManager.default.fileExists(atPath: localRepoURL.appendingPathComponent(".gitignore").path))
            #expect(FileManager.default.fileExists(atPath: localRepoURL.appendingPathComponent(".latexap-workspace.json").path))
        }

        // 2. Import loose .tex file into structured multi-project layout
        await vm.importExistingTeXFileAsProject(relativeTeXPath: "legacy-notes.tex", displayName: "Legacy Notes")
        #expect(vm.repoProjects.contains(where: { $0.slug == "legacy-notes" }))
        #expect(vm.sourceText.contains("Legacy existing paper."))

        // 3. Create two distinct academic projects inside the single repository
        await vm.createProjectInActiveRepo(displayName: "CS229 Final Paper")
        let projectA = vm.activeProject
        #expect(projectA?.slug == "cs229-final-paper")

        await vm.createProjectInActiveRepo(displayName: "Phys 101 Lab")
        let projectB = vm.activeProject
        #expect(projectB?.slug == "phys-101-lab")
        #expect(vm.repoProjects.count == 3)

        // 4. Switch back to Project A, edit TeX + BibTeX, verify dirty flag & default commit message
        await vm.openProjectFromActiveRepo(projectA!)
        #expect(!vm.hasUnsavedBufferEdits)
        vm.sourceText = "\\documentclass{article}\n\\begin{document}\nTheorem 1 initial draft.\n\\end{document}\n"
        vm.managedBibContent = "@article{lecun2015, author={LeCun, Y.}, title={Deep Learning}, year={2015}}"
        #expect(vm.hasUnsavedBufferEdits)

        await vm.saveAndCommitCurrentProject()
        #expect(!vm.hasUnsavedBufferEdits)
        #expect(vm.lastCommitSummary?.hasPrefix("Update CS229 Final Paper — ") == true)
        #expect(!vm.isInGitConflictState)

        // Repeated save with no edits must NOT create spurious metadata-only commits (#69 Item 1)
        let countAfterFirstSave = vm.projectCommitHistory.count
        await vm.saveAndCommitCurrentProject()
        #expect(vm.projectCommitHistory.count == countAfterFirstSave)
        #expect(vm.repoStatusMessage == "No changes to commit in CS229 Final Paper.")

        // Project B history must remain isolated from Project A's update commit
        if let projB = projectB, let repo = vm.activeRepo {
            let repoURL = try await gitService.localRepositoryURL(for: repo)
            let bHistory = try await gitService.projectHistory(in: repoURL, projectRelativePath: projB.relativePath)
            #expect(bHistory.count == 1)
            #expect(bHistory.first?.message == "Initialize Phys 101 Lab")
        }

        // 5. Save with custom commit message, inspect history/diff, and non-destructively restore
        vm.sourceText = "\\documentclass{article}\n\\begin{document}\nTheorem 2 revised proof.\n\\end{document}\n"
        await vm.saveAndCommitCurrentProject(customMessage: "Draft: Added Theorem 2 proof", pushImmediately: true)
        #expect(vm.projectCommitHistory.first?.message == "Draft: Added Theorem 2 proof")
        #expect(vm.projectCommitHistory.first?.isPushed == true)

        if let latest = vm.projectCommitHistory.first,
           vm.projectCommitHistory.count >= 2 {
            let previous = vm.projectCommitHistory[1]
            let diff = await vm.previewDiffAtCommit(latest)
            #expect(diff.contains("Theorem 2 revised proof."))
            let oldText = await vm.previewFileAtCommit(previous, relativeFilePath: "\(projectA!.relativePath)/main.tex")
            #expect(oldText?.contains("Theorem 1 initial draft.") == true)

            // Non-destructive restore creates a forward commit restoring Theorem 1
            await vm.restoreProjectToCommit(previous)
            #expect(vm.sourceText.contains("Theorem 1 initial draft."))
            #expect(vm.projectCommitHistory.first?.message.hasPrefix("Restore CS229 Final Paper") == true)
        }

        // 6. Simulate real remote conflict from collaborator clone & resolve cleanly keeping both versions
        try runRawGit(["clone", bareRepoURL.path, collabCloneURL.path], in: tempRoot)
        try runRawGit(["checkout", "main"], in: collabCloneURL)
        let collabMainTeX = collabCloneURL.appendingPathComponent("projects/cs229-final-paper/main.tex")
        try "\\documentclass{article}\n\\begin{document}\nRemote collaborator proof version.\n\\end{document}\n"
            .write(to: collabMainTeX, atomically: true, encoding: .utf8)
        try runRawGit(["add", "projects/cs229-final-paper/main.tex"], in: collabCloneURL)
        try runRawGit(["commit", "-m", "Collaborator edit on CS229"], in: collabCloneURL)
        try runRawGit(["push", "origin", "main"], in: collabCloneURL)

        vm.sourceText = "\\documentclass{article}\n\\begin{document}\nLocal unpushed proof version.\n\\end{document}\n"
        await vm.saveAndCommitCurrentProject(customMessage: "Local conflicting draft", pushImmediately: true)
        #expect(vm.isInGitConflictState)
        if case .conflict(let files, _) = vm.gitSyncState {
            #expect(files.contains("projects/cs229-final-paper/main.tex"))
        } else {
            Issue.record("Expected conflict state after divergent collaborator push")
        }
        // Working copy stays free of conflict markers while conflict banner awaits user choice
        #expect(!vm.sourceText.contains("<<<<<<<"))

        await vm.resolveConflictKeepBoth()
        #expect(!vm.isInGitConflictState)
        #expect(vm.sourceText.contains("Local unpushed proof version."))
        if let activeRepo = vm.activeRepo {
            let localRepoURL = try await gitService.localRepositoryURL(for: activeRepo)
            let remoteBackupURL = localRepoURL.appendingPathComponent("projects/cs229-final-paper/main-remote.tex")
            #expect(FileManager.default.fileExists(atPath: remoteBackupURL.path))
            let backupText = try String(contentsOf: remoteBackupURL, encoding: .utf8)
            #expect(backupText.contains("Remote collaborator proof version."))
        }

        // 7. Update repo settings & delete one project cleanly
        await vm.updateActiveRepoSettings(autoPushOnSave: false, includePDFsInCommits: true)
        #expect(vm.activeRepo?.autoPushOnSave == false)
        #expect(vm.commitPushImmediately == false)

        if let physLab = projectB {
            await vm.deleteProjectFromActiveRepo(physLab)
            #expect(!vm.repoProjects.contains(where: { $0.slug == "phys-101-lab" }))
        }

        // 8. Large (>64 KB) commit diff does not deadlock pipe reader (#68 Item 2)
        let bigLine = String(repeating: "A", count: 85_000)
        vm.sourceText = "\\documentclass{article}\n\\begin{document}\n%\(bigLine)\n\\end{document}\n"
        await vm.saveAndCommitCurrentProject(customMessage: "Large diff pipe test", pushImmediately: true)
        if let bigCommit = vm.projectCommitHistory.first {
            let bigDiff = await vm.previewDiffAtCommit(bigCommit)
            #expect(bigDiff.count > 70_000)
        }

        // 9. Paper Setup Wizard & disconnectRepo clear activeProject and currentFileURL (#69 Item 2)
        vm.applyPaperSetupWizard(PaperSetupConfig(templateId: "apa7-student", title: "Fresh Wizard Paper"))
        #expect(vm.activeProject == nil)
        #expect(vm.currentFileURL == nil)
        #expect(!vm.hasUnsavedBufferEdits)

        if let repo = vm.activeRepo {
            vm.disconnectRepo(repo, deleteLocalClone: false)
            #expect(vm.activeRepo == nil)
            #expect(vm.activeProject == nil)
            #expect(vm.currentFileURL == nil)
        }
    }

    @Test @MainActor func gitHubPhase3SecurityAndCodeReviewRegressions() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaTeXaPGitP3Sec-\(UUID().uuidString)", isDirectory: true)
        let reposRoot = tempRoot.appendingPathComponent("Repos", isDirectory: true)
        let repoDir = reposRoot.appendingPathComponent("attacker-malicious", isDirectory: true)
        let projectsDir = repoDir.appendingPathComponent("projects", isDirectory: true)
        let projDir = projectsDir.appendingPathComponent("evil-paper", isDirectory: true)
        let outsideDir = tempRoot.appendingPathComponent("Outside", isDirectory: true)
        let tempFigs = tempRoot.appendingPathComponent("TempFigs", isDirectory: true)
        let tempFigsSubdir = tempFigs.appendingPathComponent("nested", isDirectory: true)
        let fontsDir = tempRoot.appendingPathComponent("Fonts", isDirectory: true)

        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempFigs, withIntermediateDirectories: true)
        let suiteName = "LaTeXaPGitP3Sec.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        // 1. Port guard rejects non-443 ports on HTTPS GitHub URLs
        #expect(GitHubWorkspaceValidator.parseAndValidateRemoteURL("https://github.com:8443/octocat/repo.git") == nil)
        #expect(GitHubWorkspaceValidator.parseAndValidateRemoteURL("https://github.com:443/octocat/repo.git") != nil)
        #expect(GitHubWorkspaceValidator.validatedProjectRelativeFile("../../.ssh/authorized_keys", allowedExtensions: ["tex"]) == nil)
        #expect(GitHubWorkspaceValidator.validatedProjectRelativeFile(".git/config", allowedExtensions: nil) == nil)
        #expect(GitHubWorkspaceValidator.validatedProjectRelativeFile("chapters/sec1.tex", allowedExtensions: ["tex"]) == "chapters/sec1.tex")

        let outsideFile = outsideDir.appendingPathComponent("secret.tex")
        try "TOP_SECRET_DATA".write(to: outsideFile, atomically: true, encoding: .utf8)

        let service = GitRepositoryService(
            repositoriesRootDirectory: reposRoot,
            credentialStore: InMemoryGitCredentialStore(),
            allowLocalTestBareRemotes: true
        )

        // 2. Crafted .latexap-workspace.json with mainTexFile/bibFile traversal is filtered out by discoverProjects
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let craftedProj = AcademicProjectDescriptor(
            slug: "evil-paper",
            displayName: "Evil Paper",
            relativePath: "projects/evil-paper",
            mainTexFile: "../../../Outside/secret.tex",
            bibFile: "../../.git/hooks/post-checkout"
        )
        let craftedManifest = GitHubWorkspaceManifest(
            schemaVersion: 1,
            repoFullName: "attacker/malicious",
            defaultBranch: "main",
            projects: [craftedProj]
        )
        try encoder.encode(craftedManifest).write(to: repoDir.appendingPathComponent(".latexap-workspace.json"))
        try encoder.encode(craftedProj).write(to: projDir.appendingPathComponent("project.json"))

        let discovery = try await service.discoverProjects(in: repoDir, defaultBranch: "main", repoFullName: "attacker/malicious")
        #expect(discovery.manifest.projects.isEmpty)

        // 3. ViewModel refuses to open OR overwrite via crafted AcademicProjectDescriptor
        let conn = GitHubRepoConnection(
            owner: "attacker",
            repoName: "malicious",
            remoteURLString: tempRoot.appendingPathComponent("bare.git").path,
            branch: "main",
            authMethod: .sshKey,
            localFolderName: "attacker-malicious"
        )
        let vm = DocumentViewModel(
            initialTemplate: LaTeXCatalog.defaultTemplate,
            fontLibraryService: FontLibraryService(storageDirectory: fontsDir),
            userDefaults: defaults,
            tempFiguresDirectory: tempFigs,
            compileOnInit: false,
            gitRepositoryService: service,
            gitCredentialStore: InMemoryGitCredentialStore()
        )
        vm.autoCompileEnabled = false
        vm.activeRepo = conn

        await vm.openProjectFromActiveRepo(craftedProj)
        #expect(vm.activeProject == nil)
        #expect(!vm.sourceText.contains("TOP_SECRET_DATA"))

        vm.activeProject = craftedProj
        vm.sourceText = "OVERWRITTEN"
        await vm.saveAndCommitCurrentProject()
        #expect(try String(contentsOf: outsideFile, encoding: .utf8) == "TOP_SECRET_DATA")

        // 4. Symlinked figures/nested directory inside tempFiguresDir is blocked during createProject(copyFiguresFrom:)
        try FileManager.default.createSymbolicLink(at: tempFigsSubdir, withDestinationURL: outsideDir)
        let outsideImg = outsideDir.appendingPathComponent("secret.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: outsideImg)

        let cleanRepoDir = reposRoot.appendingPathComponent("clean-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: cleanRepoDir, withIntermediateDirectories: true)
        let initGit = { (args: [String]) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: GitRepositoryService.locateGitBinary()!)
            p.currentDirectoryURL = cleanRepoDir
            p.arguments = args
            try p.run()
            p.waitUntilExit()
        }
        try initGit(["init", "-b", "main"])

        let cleanConn = GitHubRepoConnection(
            owner: "local",
            repoName: "clean",
            remoteURLString: tempRoot.appendingPathComponent("clean-bare.git").path,
            branch: "main",
            authMethod: .sshKey,
            localFolderName: "clean-repo",
            autoPushOnSave: false
        )
        let created = try await service.createProject(
            in: cleanRepoDir,
            connection: cleanConn,
            displayName: "Safe Paper",
            mainContent: "\\documentclass{article}\n\\begin{document}\n\\includegraphics{figures/nested/secret.png}\n\\end{document}\n",
            copyFiguresFrom: tempFigs,
            token: nil
        )
        let copiedPath = cleanRepoDir.appendingPathComponent("\(created.project.relativePath)/figures/nested/secret.png")
        #expect(!FileManager.default.fileExists(atPath: copiedPath.path))

        // 5. Symlinked projects/ directory throws securityViolation on discoverProjects
        let symRepoDir = reposRoot.appendingPathComponent("sym-projects-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: symRepoDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symRepoDir.appendingPathComponent("projects"), withDestinationURL: outsideDir)
        await #expect(throws: GitStorageError.self) {
            _ = try await service.discoverProjects(in: symRepoDir)
        }
    }
}
