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
}
