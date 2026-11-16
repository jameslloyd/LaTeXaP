import AppKit
import Combine
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class DocumentViewModel: ObservableObject {
    @Published public var sourceText: String {
        didSet {
            if sourceText != oldValue {
                refreshDerivedMetadata()
                if autoCompileEnabled {
                    scheduleDebouncedCompilation()
                }
            }
        }
    }

    @Published public var currentFileURL: URL?
    @Published public var cursorLine: Int = 1
    @Published public var jumpToLineRequest: Int?
    @Published public var forwardSyncBox: SyncTeXBox?
    @Published public var pdfZoomScale: CGFloat = 1.0

    @Published public var compilationState: CompilationState = .idle
    @Published public var diagnostics: [LaTeXDiagnostic] = []
    @Published public var staticLintWarnings: [LaTeXDiagnostic] = []
    @Published public var consoleLog: String = ""
    @Published public var pdfURL: URL?
    @Published public var pdfRevision: Int = 0
    @Published public var synctexData: SyncTeXData?
    @Published public var outlineItems: [DocumentOutlineItem] = []
    @Published public var bibEntries: [BibEntry] = []
    @Published public var documentLabels: [DocumentLabelItem] = []
    @Published public var documentStats: DocumentStats = DocumentStats()

    @Published public var autoCompileEnabled: Bool = true
    @Published public var showConsoleDrawer: Bool = true
    @Published public var showSidebar: Bool = true
    @Published public var editorFontSize: CGFloat = 13.5 {
        didSet {
            let clamped = min(max(editorFontSize, 10.0), 24.0)
            if clamped != editorFontSize {
                editorFontSize = clamped
                return
            }
            userDefaults.set(Double(clamped), forKey: Self.editorFontSizeDefaultsKey)
        }
    }
    @Published public var useLightEditorBackground: Bool = true
    @Published public var selectedSidebarTab: String = "Outline"
    @Published public var packageSearchText: String = ""
    @Published public var selectedDiagnosticTab: Int = 2

    // Custom & Editor Font State
    @Published public var customFonts: [CustomFontRecord] = []
    @Published public var fontSearchText: String = ""
    @Published public var isImportingFont: Bool = false
    @Published public var fontErrorMessage: String?
    @Published public var fontSuccessMessage: String?
    @Published public var showFontManagerSheet: Bool = false
    @Published public var editorFontName: String = "" {
        didSet {
            userDefaults.set(editorFontName, forKey: Self.editorFontNameDefaultsKey)
        }
    }

    // BibTeX DOI / arXiv lookup state
    @Published public var bibLookupQuery: String = ""
    @Published public var isFetchingBib: Bool = false
    @Published public var bibLookupError: String?

    // Visual Math / Matrix / Table Builder sheet state
    @Published public var showVisualToolsSheet: Bool = false
    @Published public var visualToolTab: Int = 0
    @Published public var matrixEnvType: String = "pmatrix"
    @Published public var matrixRows: Int = 3
    @Published public var matrixCols: Int = 3
    @Published public var matrixIdentityFill: Bool = false
    @Published public var csvInputText: String = "Method, Complexity, Rate\nGradient Descent, O(k log(1/e)), Linear\nNesterov AGD, O(sqrt(k) log(1/e)), Accelerated"
    @Published public var tableCaptionText: String = "Empirical performance comparison."
    @Published public var tableLabelText: String = "tab:comparison"

    // Non-intrusive GitHub release update notification state
    @Published public var availableUpdate: AppReleaseUpdate?

    private static let editorFontNameDefaultsKey = "LaTeXaP.editorFontName"
    private static let editorFontSizeDefaultsKey = "LaTeXaP.editorFontSize"

    private let tectonicService = TectonicService()
    private let fontLibraryService: FontLibraryService
    private let userDefaults: UserDefaults
    private var debounceTask: Task<Void, Never>?
    private var lastCompilerDiagnostics: [LaTeXDiagnostic] = []

    public init(
        initialTemplate: LaTeXTemplate = LaTeXCatalog.defaultTemplate,
        fontLibraryService: FontLibraryService = FontLibraryService(),
        userDefaults: UserDefaults = .standard,
        compileOnInit: Bool = true
    ) {
        self.fontLibraryService = fontLibraryService
        self.userDefaults = userDefaults
        self.sourceText = initialTemplate.content
        self.editorFontName = userDefaults.string(forKey: Self.editorFontNameDefaultsKey) ?? ""
        if userDefaults.object(forKey: Self.editorFontSizeDefaultsKey) != nil {
            let storedSize = userDefaults.double(forKey: Self.editorFontSizeDefaultsKey)
            self.editorFontSize = CGFloat(min(max(storedSize, 10.0), 24.0))
        }
        self.customFonts = fontLibraryService.registerAllStoredFonts()
        refreshDerivedMetadata()
        if compileOnInit {
            Task {
                await compileNow()
            }
            checkForUpdatesSilently()
        }
    }

    public func checkForUpdatesSilently() {
        Task { [weak self] in
            if let update = await UpdateCheckerService.checkForUpdate(currentVersion: AppMetadata.version) {
                self?.availableUpdate = update
            }
        }
    }

    public func checkForUpdatesInteractively() {
        Task { [weak self] in
            guard let self else { return }
            let status = await UpdateCheckerService.checkForUpdateInteractive(currentVersion: AppMetadata.version)
            let alert = NSAlert()
            switch status {
            case .updateAvailable(let update):
                self.availableUpdate = update
                alert.alertStyle = .informational
                alert.messageText = "LaTeXaP v\(update.latestVersion) is Available"
                alert.informativeText = "You are currently running LaTeXaP v\(AppMetadata.version). Release \(update.tagName) is available on GitHub."
                alert.addButton(withTitle: "Download Update")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(update.htmlURL)
                }
            case .upToDate(let current, let latestTag):
                alert.alertStyle = .informational
                alert.messageText = "You're Up to Date"
                if let latestTag {
                    alert.informativeText = "LaTeXaP v\(current) is the latest available version (\(latestTag))."
                } else {
                    alert.informativeText = "LaTeXaP v\(current) is the latest available version."
                }
                alert.addButton(withTitle: "OK")
                alert.runModal()
            case .failed(let message):
                alert.alertStyle = .warning
                alert.messageText = "Unable to Check for Updates"
                alert.informativeText = message
                alert.addButton(withTitle: "Open GitHub Releases")
                alert.addButton(withTitle: "OK")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(UpdateCheckerService.releasesPageURL)
                }
            }
        }
    }

    private func refreshDerivedMetadata() {
        outlineItems = OutlineParser.parse(source: sourceText)
        bibEntries = BibliographyService.extractEntries(fromSource: sourceText)
        documentLabels = BibliographyService.extractLabels(from: sourceText)
        documentStats = Expl3Linter.computeStatistics(source: sourceText)
        staticLintWarnings = Expl3Linter.lint(source: sourceText)
        diagnostics = lastCompilerDiagnostics + staticLintWarnings
    }

    public func scheduleDebouncedCompilation() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 550_000_000) // 550ms debounce for smooth realtime typing
            guard !Task.isCancelled else { return }
            await self?.compileNow()
        }
    }

    public func compileNow() async {
        debounceTask?.cancel()
        compilationState = .compiling(status: "Running Tectonic (LaTeX3 + SyncTeX)...")

        let codeSnapshot = sourceText
        let docDir = currentFileURL?.deletingLastPathComponent()

        let result = await tectonicService.compile(
            source: codeSnapshot,
            documentDirectory: docDir,
            fontDirectories: [fontLibraryService.fontsDirectory]
        )

        lastCompilerDiagnostics = result.diagnostics
        diagnostics = lastCompilerDiagnostics + staticLintWarnings
        consoleLog = result.logOutput

        if result.success, let url = result.pdfURL {
            pdfURL = url
            pdfRevision += 1
            synctexData = result.synctexData
            let pageCount = PDFDocument(url: url)?.pageCount ?? 1
            compilationState = .success(durationMs: result.durationMs, pageCount: pageCount)
        } else {
            let errCount = max(1, result.diagnostics.filter { $0.severity == .error }.count)
            compilationState = .failed(errorCount: errCount)
            showConsoleDrawer = true
        }
    }

    public func triggerForwardSync() {
        guard let sync = synctexData else { return }
        if let box = sync.forwardSearch(line: cursorLine) {
            forwardSyncBox = box
        }
    }

    public func handleBackwardSync(page: Int, xPt: Double, yTopPt: Double) {
        guard let sync = synctexData else { return }
        if let line = sync.backwardSearch(page: page, xPt: xPt, yTopPt: yTopPt) {
            jumpToLineRequest = line
        }
    }

    public func loadTemplate(_ template: LaTeXTemplate) {
        currentFileURL = nil
        sourceText = template.content
        Task {
            await compileNow()
        }
    }

    public func insertSnippet(_ snippet: LaTeXSnippet) {
        insertRawBlock(snippet.code)
    }

    public func insertRawBlock(_ block: String) {
        let lines = sourceText.components(separatedBy: .newlines)
        let targetIndex = max(0, min(lines.count, cursorLine))
        var updated = lines
        updated.insert(block, at: targetIndex)
        sourceText = updated.joined(separator: "\n")
    }

    public func insertInlineText(_ token: String) {
        var lines = sourceText.components(separatedBy: .newlines)
        guard !lines.isEmpty else {
            sourceText = token
            return
        }
        let idx = max(0, min(lines.count - 1, cursorLine - 1))
        lines[idx] += " \(token)"
        sourceText = lines.joined(separator: "\n")
    }

    public func insertPackage(_ pkg: LaTeXPackagePreset) {
        let statement = pkg.usepackageStatement
        if sourceText.contains("\\usepackage{\(pkg.package)}") || sourceText.contains("{\(pkg.package)}") {
            return
        }
        var lines = sourceText.components(separatedBy: .newlines)
        if let docClassIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("\\documentclass") }) {
            lines.insert(statement, at: docClassIndex + 1)
            sourceText = lines.joined(separator: "\n")
        } else {
            sourceText = statement + "\n" + sourceText
        }
    }

    public func applyContextAdvice(_ advice: ContextAdviceItem) {
        if let pkgName = advice.packageToInsert,
           let preset = LaTeXCatalog.commonPackages.first(where: { $0.package == pkgName }) {
            insertPackage(preset)
        }
        if let snippet = advice.snippetToInsert {
            if sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sourceText = snippet
            } else {
                insertRawBlock(snippet)
            }
        }
    }

    // MARK: - BibTeX DOI / arXiv Fetch & Citation Insertion

    public func fetchAndAppendBibEntry() {
        let query = bibLookupQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isFetchingBib = true
        bibLookupError = nil

        Task {
            do {
                let entry = try await BibliographyService.fetchBibTeX(identifier: query)
                appendBibItemToSource(entry)
                bibLookupQuery = ""
            } catch {
                bibLookupError = "Could not fetch DOI/arXiv entry: \(error.localizedDescription)"
            }
            isFetchingBib = false
        }
    }

    public func appendBibItemToSource(_ entry: BibEntry) {
        let formattedItem = """
\\bibitem{\(entry.key)}
\(entry.author), ``\(entry.title),'' \(entry.year).
"""
        if let range = sourceText.range(of: "\\end{thebibliography}") {
            sourceText.replaceSubrange(range, with: "\(formattedItem)\n\\end{thebibliography}")
        } else if let endDocRange = sourceText.range(of: "\\end{document}") {
            let bibSection = """

\\begin{thebibliography}{9}
\(formattedItem)
\\end{thebibliography}

\\end{document}
"""
            sourceText.replaceSubrange(endDocRange, with: bibSection)
        } else {
            sourceText += "\n\(formattedItem)\n"
        }
    }

    // MARK: - Figure / Image Import Assistant

    public func importFigureViaPanel() {
        let panel = NSOpenPanel()
        panel.title = "Insert Image or PDF Figure"
        panel.allowedContentTypes = [.png, .jpeg, .pdf, .tiff]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            handleDroppedImageURL(url)
        }
    }

    public func handleDroppedImageURL(_ url: URL) {
        if let graphicxPreset = LaTeXCatalog.commonPackages.first(where: { $0.package == "graphicx" }) {
            insertPackage(graphicxPreset)
        }
        let fileName = url.deletingPathExtension().lastPathComponent
        let figureBlock = """
\\begin{figure}[htbp]
  \\centering
  \\includegraphics[width=0.75\\textwidth]{\(url.path)}
  \\caption{Caption for \(fileName.replacingOccurrences(of: "_", with: " ")).}
  \\label{fig:\(fileName.lowercased())}
\\end{figure}
"""
        insertRawBlock(figureBlock)
    }

    // MARK: - File Operations (Open / Save / Export PDF)

    public func openTexFile() {
        let panel = NSOpenPanel()
        panel.title = "Open LaTeX Document"
        panel.allowedContentTypes = [UTType(filenameExtension: "tex") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if let loaded = try? String(contentsOf: url, encoding: .utf8) {
                currentFileURL = url
                sourceText = loaded
                Task { await compileNow() }
            }
        }
    }

    public func saveTexFile(saveAs: Bool = false) {
        if !saveAs, let existingURL = currentFileURL {
            try? sourceText.write(to: existingURL, atomically: true, encoding: .utf8)
            return
        }
        let panel = NSSavePanel()
        panel.title = "Save LaTeX3 Document"
        panel.nameFieldStringValue = currentFileURL?.lastPathComponent ?? "document.tex"
        panel.allowedContentTypes = [UTType(filenameExtension: "tex") ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            currentFileURL = url
            try? sourceText.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public func exportPDF() {
        Task {
            if pdfURL == nil {
                await compileNow()
            }
            guard let builtPDF = pdfURL, FileManager.default.fileExists(atPath: builtPDF.path) else {
                return
            }
            let panel = NSSavePanel()
            panel.title = "Export Rendered PDF"
            let baseName = currentFileURL?.deletingPathExtension().lastPathComponent ?? "document"
            panel.nameFieldStringValue = "\(baseName).pdf"
            panel.allowedContentTypes = [.pdf]
            if panel.runModal() == .OK, let destURL = panel.url {
                try? FileManager.default.removeItem(at: destURL)
                try? FileManager.default.copyItem(at: builtPDF, to: destURL)
            }
        }
    }

    // MARK: - Custom Fonts & Editor Typography

    public var availableEditorFontNames: [String] {
        var result: [String] = []
        var seen = Set<String>()
        for font in customFonts where font.isMonospace {
            if seen.insert(font.postScriptName).inserted {
                result.append(font.postScriptName)
            }
        }
        for family in fontLibraryService.systemFontFamilies(monospaceOnly: true) {
            if seen.insert(family).inserted {
                result.append(family)
            }
        }
        return result
    }

    public var availableSystemFontFamilies: [String] {
        fontLibraryService.systemFontFamilies(monospaceOnly: false)
    }

    public func openImportFontPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Custom Fonts (.ttf, .otf, .ttc)"
        panel.message = "Select TrueType or OpenType font files to import into LaTeXaP."
        let fontTypes: [UTType] = ["ttf", "otf", "ttc"].compactMap { UTType(filenameExtension: $0) }
        panel.allowedContentTypes = fontTypes.isEmpty ? [.font] : fontTypes
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            importCustomFonts(urls: panel.urls)
        }
    }

    public func importCustomFonts(urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImportingFont = true
        fontErrorMessage = nil
        fontSuccessMessage = nil
        Task { [weak self] in
            await self?.importCustomFontsAsync(urls: urls)
        }
    }

    public func importCustomFontsAsync(urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isImportingFont = true
        fontErrorMessage = nil
        fontSuccessMessage = nil
        defer { isImportingFont = false }

        let service = fontLibraryService
        let outcome: (imported: [CustomFontRecord], errors: [String], refreshed: [CustomFontRecord]?) = await Task.detached(priority: .userInitiated) {
            var imported: [CustomFontRecord] = []
            var errors: [String] = []

            for url in urls {
                do {
                    let record = try service.importFont(from: url)
                    imported.append(record)
                } catch {
                    errors.append(error.localizedDescription)
                }
            }

            let refreshed = try? service.loadManifest()
            return (imported, errors, refreshed)
        }.value

        if let refreshed = outcome.refreshed {
            customFonts = refreshed
        }

        if !outcome.imported.isEmpty {
            if outcome.imported.count == 1 {
                fontSuccessMessage = "Added '\(outcome.imported[0].displayName)' — ready to preview and insert."
            } else {
                fontSuccessMessage = "Added \(outcome.imported.count) custom fonts — ready to preview and insert."
            }
        }

        if !outcome.errors.isEmpty {
            fontErrorMessage = outcome.errors.joined(separator: " ")
        }
    }

    public func deleteCustomFont(_ font: CustomFontRecord) {
        fontErrorMessage = nil
        fontSuccessMessage = nil
        do {
            try fontLibraryService.deleteFont(id: font.id)
            customFonts.removeAll { $0.id == font.id }
            if editorFontName == font.postScriptName || editorFontName == font.familyName {
                editorFontName = ""
            }
            fontSuccessMessage = "Removed '\(font.displayName)' from library."
        } catch {
            fontErrorMessage = error.localizedDescription
        }
    }

    public func renameCustomFont(_ font: CustomFontRecord, to newName: String) {
        fontErrorMessage = nil
        fontSuccessMessage = nil
        do {
            let updated = try fontLibraryService.renameFont(id: font.id, newDisplayName: newName)
            if let idx = customFonts.firstIndex(where: { $0.id == updated.id }) {
                customFonts[idx] = updated
            }
            fontSuccessMessage = "Renamed font to '\(updated.displayName)'."
        } catch {
            fontErrorMessage = error.localizedDescription
        }
    }

    public func applyCustomFontToDocument(
        _ font: CustomFontRecord,
        role: LaTeXFontRole,
        customCommand: String = "\\customfont"
    ) {
        let statement = fontLibraryService.generateFontspecBlock(
            for: font,
            role: role,
            customCommandName: customCommand
        )
        guard !statement.isEmpty else {
            fontErrorMessage = "Font filename contains no valid LaTeX characters."
            return
        }
        applyFontspecDeclaration(statement, role: role, customCommand: customCommand)
        fontErrorMessage = nil
        fontSuccessMessage = "Inserted \(statement) into preamble."
    }

    public func applySystemFontToDocument(
        familyName: String,
        role: LaTeXFontRole,
        customCommand: String = "\\customfont"
    ) {
        let statement = fontLibraryService.generateSystemFontspecBlock(
            familyName: familyName,
            role: role,
            customCommandName: customCommand
        )
        guard !statement.isEmpty else {
            fontErrorMessage = "Font family name contains no valid LaTeX characters."
            return
        }
        applyFontspecDeclaration(statement, role: role, customCommand: customCommand)
        fontErrorMessage = nil
        fontSuccessMessage = "Inserted \(statement) into preamble."
    }

    public func applyCTANFontPreset(_ preset: CTANFontPreset) {
        let statement = preset.usepackageStatement
        if !sourceText.contains("\\usepackage{\(preset.packageName)}") && !sourceText.contains(statement) {
            var lines = sourceText.components(separatedBy: .newlines)
            if let docClassIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("\\documentclass") }) {
                lines.insert(statement, at: docClassIndex + 1)
                sourceText = lines.joined(separator: "\n")
            } else {
                sourceText = statement + "\n" + sourceText
            }
        }
        fontErrorMessage = nil
        fontSuccessMessage = "Loaded CTAN font package '\(preset.name)'."
    }

    public func selectEditorFont(_ fontName: String) {
        editorFontName = fontName
        fontErrorMessage = nil
        if fontName.isEmpty {
            fontSuccessMessage = "Editor font set to System Monospaced."
        } else {
            fontSuccessMessage = "Editor font set to '\(fontName)'."
        }
    }

    public func resetEditorFontToDefault() {
        editorFontName = ""
        editorFontSize = 13.5
        fontErrorMessage = nil
        fontSuccessMessage = "Editor font reset to System Monospaced (13.5 pt)."
    }

    public func clearFontFeedback() {
        fontErrorMessage = nil
        fontSuccessMessage = nil
    }

    private func applyFontspecDeclaration(_ declaration: String, role: LaTeXFontRole, customCommand: String) {
        var lines = sourceText.components(separatedBy: .newlines)
        let beginDocIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("\\begin{document}")
        })
        let preambleEnd = beginDocIndex ?? lines.count

        // 1. Ensure \usepackage{fontspec} is loaded in the preamble
        let fontspecPkgRegex = try? NSRegularExpression(
            pattern: #"\\usepackage(?:\[[^\]]*\])?\{[^}]*\bfontspec\b[^}]*\}"#
        )
        var fontspecLineIndex: Int?
        for idx in 0..<preambleEnd {
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("%") { continue }
            let nsLine = lines[idx] as NSString
            if fontspecPkgRegex?.firstMatch(in: lines[idx], range: NSRange(location: 0, length: nsLine.length)) != nil {
                fontspecLineIndex = idx
                break
            }
        }

        var updatedPreambleEnd = preambleEnd
        if fontspecLineIndex == nil {
            if let docClassIdx = lines[0..<preambleEnd].firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("\\documentclass")
            }) {
                lines.insert("\\usepackage{fontspec}", at: docClassIdx + 1)
                fontspecLineIndex = docClassIdx + 1
            } else {
                lines.insert("\\usepackage{fontspec}", at: 0)
                fontspecLineIndex = 0
            }
            updatedPreambleEnd += 1
        }

        // 2. Replace existing role declaration in preamble if present, else insert cleanly
        let replacePattern: String
        switch role {
        case .main:
            replacePattern = #"^\s*\\setmainfont(?:\[[^\]]*\])?\{[^}]*\}.*$"#
        case .sans:
            replacePattern = #"^\s*\\setsansfont(?:\[[^\]]*\])?\{[^}]*\}.*$"#
        case .mono:
            replacePattern = #"^\s*\\setmonofont(?:\[[^\]]*\])?\{[^}]*\}.*$"#
        case .customFamily:
            let sanitizedCmd = NSRegularExpression.escapedPattern(
                for: FontLibraryService.sanitizeCustomCommandName(customCommand)
            )
            replacePattern = #"^\s*\\newfontfamily\s*\{?\\\#(sanitizedCmd)\}?(?:\[[^\]]*\])?\{[^}]*\}.*$"#
        }

        let replaceRegex = try? NSRegularExpression(pattern: replacePattern)
        for idx in 0..<updatedPreambleEnd {
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("%") { continue }
            let nsLine = lines[idx] as NSString
            if replaceRegex?.firstMatch(in: lines[idx], range: NSRange(location: 0, length: nsLine.length)) != nil {
                lines[idx] = declaration
                sourceText = lines.joined(separator: "\n")
                return
            }
        }

        // Insert after the last fontspec-related line in preamble, or right after \usepackage{fontspec}
        var insertAt = (fontspecLineIndex ?? 0) + 1
        for idx in 0..<updatedPreambleEnd {
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\\setmainfont") ||
                trimmed.hasPrefix("\\setsansfont") ||
                trimmed.hasPrefix("\\setmonofont") ||
                trimmed.hasPrefix("\\newfontfamily") {
                insertAt = idx + 1
            }
        }
        lines.insert(declaration, at: min(insertAt, updatedPreambleEnd))
        sourceText = lines.joined(separator: "\n")
    }
}
