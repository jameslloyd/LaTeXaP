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
                refreshDirtyFlag()
                refreshDerivedMetadata()
                if autoCompileEnabled, !isInGitConflictState {
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

    // MARK: - Academic Citations & Bibliography State (v0.2.0)
    @Published public var managedBibContent: String = "" {
        didSet {
            if managedBibContent != oldValue {
                refreshDirtyFlag()
                refreshDerivedMetadata()
                if autoCompileEnabled, !isInGitConflictState {
                    scheduleDebouncedCompilation()
                }
            }
        }
    }
    @Published public var bibSearchResults: [BibEntry] = []
    @Published public var isSearchingCrossRef: Bool = false
    @Published public var selectedCitationStyle: CitationCommandStyle = .cite
    @Published public var selectedBibliographyStyle: BibliographyStylePreset = .apa
    @Published public var showCitationPickerPopover: Bool = false

    // MARK: - Academic Templates & Paper Wizard State (v0.2.0)
    @Published public var showPaperWizardSheet: Bool = false
    @Published public var isBlindReviewEnabled: Bool = false
    @Published public var isDoubleSpacedEnabled: Bool = false

    // MARK: - Academic Stats, Rubric Targets & Student Mode (v0.2.0)
    @Published public var academicStats: AcademicDocumentStats = AcademicDocumentStats()
    @Published public var rubricTargets: RubricTargetConfig = RubricTargetConfig()
    @Published public var preflightReport: AcademicPreflightReport = .empty
    @Published public var demystifiedDiagnostics: [DemystifiedDiagnostic] = []

    // MARK: - Spellcheck & Cursor-Accurate Insertion (v0.2.0)
    @Published public var proseSpellCheckEnabled: Bool = false {
        didSet {
            userDefaults.set(proseSpellCheckEnabled, forKey: Self.proseSpellCheckEnabledKey)
            refreshSpellingIssues()
        }
    }
    @Published public var spellingIssues: [SpellingIssue] = []
    @Published public var pendingEditorInsertion: EditorInsertionRequest?
    @Published public var showFigureAssistantSheet: Bool = false
    @Published public var pendingDroppedFigureURL: URL?

    // MARK: - Spreadsheet Table & PGFPlots Chart State (v0.2.0)
    @Published public var tableGridData: TableGridData = TableGridData()
    @Published public var chartConfig: PGFPlotChartConfig = PGFPlotChartConfig()

    // MARK: - Submission Export State (v0.2.0)
    @Published public var isExportingSubmissionBundle: Bool = false
    @Published public var submissionExportMessage: String?
    @Published public var lastExportedZipURL: URL?

    // MARK: - GitHub Multi-Project Storage State (v0.3.0)
    @Published public var connectedRepos: [GitHubRepoConnection] = []
    @Published public var activeRepo: GitHubRepoConnection?
    @Published public var repoProjects: [AcademicProjectDescriptor] = []
    @Published public var activeProject: AcademicProjectDescriptor?
    @Published public var gitSyncState: GitSyncState = .disconnected
    @Published public var pendingProjectChanges: [GitFileChange] = []
    @Published public var projectCommitHistory: [GitCommitRecord] = []
    @Published public var showRepoSetupSheet: Bool = false
    @Published public var showCommitMessagePopover: Bool = false
    @Published public var showProjectHistorySheet: Bool = false
    @Published public var showNewRepoProjectSheet: Bool = false
    @Published public var commitMessageDraft: String = ""
    @Published public var commitPushImmediately: Bool = true
    @Published public var hasUnsavedBufferEdits: Bool = false
    @Published public var repoStatusMessage: String?
    @Published public var lastCommitSummary: String?
    @Published public var availableGitHubRepos: [GitHubRemoteRepository] = []
    @Published public var authenticatedGitHubUser: GitHubAuthenticatedUser?
    @Published public var looseRepoTeXFiles: [String] = []

    private static let editorFontNameDefaultsKey = "LaTeXaP.editorFontName"
    private static let editorFontSizeDefaultsKey = "LaTeXaP.editorFontSize"
    private static let rubricTargetsDefaultsKey = "LaTeXaP.rubricTargets"
    private static let proseSpellCheckEnabledKey = "LaTeXaP.proseSpellCheckEnabled"
    private static let ignoredSpellingWordsKey = "LaTeXaP.ignoredSpellingWords"
    private static let connectedGitHubReposKey = "LaTeXaP.connectedGitHubRepos"
    private static let activeGitHubRepoIDKey = "LaTeXaP.activeGitHubRepoID"
    private static let activeGitHubProjectIDKey = "LaTeXaP.activeGitHubProjectID"

    private let tectonicService = TectonicService()
    private let fontLibraryService: FontLibraryService
    private let gitRepositoryService: GitRepositoryService
    private let gitCredentialStore: any GitCredentialStore
    private let userDefaults: UserDefaults
    public let tempFiguresDirectory: URL
    private var debounceTask: Task<Void, Never>?
    private var lastCompilerDiagnostics: [LaTeXDiagnostic] = []
    private var lastRenderedPageCount: Int = 0
    private var ignoredSpellingWords: Set<String> = []
    private var lastSavedSourceText: String = ""
    private var lastSavedBibContent: String = ""

    public init(
        initialTemplate: LaTeXTemplate = LaTeXCatalog.defaultTemplate,
        fontLibraryService: FontLibraryService = FontLibraryService(),
        userDefaults: UserDefaults = .standard,
        tempFiguresDirectory: URL? = nil,
        compileOnInit: Bool = true,
        gitRepositoryService: GitRepositoryService = GitRepositoryService(),
        gitCredentialStore: any GitCredentialStore = GitKeychainService.shared
    ) {
        self.fontLibraryService = fontLibraryService
        self.userDefaults = userDefaults
        self.gitRepositoryService = gitRepositoryService
        self.gitCredentialStore = gitCredentialStore
        if let tempFiguresDirectory {
            self.tempFiguresDirectory = tempFiguresDirectory.standardizedFileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            self.tempFiguresDirectory = appSupport
                .appendingPathComponent("LaTeXaP", isDirectory: true)
                .appendingPathComponent("TempFigures", isDirectory: true)
                .standardizedFileURL
        }
        try? FileManager.default.createDirectory(at: self.tempFiguresDirectory, withIntermediateDirectories: true)

        self.sourceText = initialTemplate.content
        self.lastSavedSourceText = initialTemplate.content
        self.lastSavedBibContent = ""
        self.editorFontName = userDefaults.string(forKey: Self.editorFontNameDefaultsKey) ?? ""
        if userDefaults.object(forKey: Self.editorFontSizeDefaultsKey) != nil {
            let storedSize = userDefaults.double(forKey: Self.editorFontSizeDefaultsKey)
            self.editorFontSize = CGFloat(min(max(storedSize, 10.0), 24.0))
        }
        if let rubricData = userDefaults.data(forKey: Self.rubricTargetsDefaultsKey),
           let decodedRubric = try? JSONDecoder().decode(RubricTargetConfig.self, from: rubricData) {
            self.rubricTargets = decodedRubric
        }
        self.proseSpellCheckEnabled = userDefaults.bool(forKey: Self.proseSpellCheckEnabledKey)
        if let storedIgnored = userDefaults.stringArray(forKey: Self.ignoredSpellingWordsKey) {
            self.ignoredSpellingWords = Set(storedIgnored)
        }

        if let repoData = userDefaults.data(forKey: Self.connectedGitHubReposKey),
           let decodedRepos = try? JSONDecoder().decode([GitHubRepoConnection].self, from: repoData) {
            self.connectedRepos = decodedRepos
            if let activeIDStr = userDefaults.string(forKey: Self.activeGitHubRepoIDKey),
               let activeUUID = UUID(uuidString: activeIDStr),
               let matched = decodedRepos.first(where: { $0.id == activeUUID }) {
                self.activeRepo = matched
                self.commitPushImmediately = matched.autoPushOnSave
            } else {
                self.activeRepo = decodedRepos.first
                self.commitPushImmediately = decodedRepos.first?.autoPushOnSave ?? true
            }
        }

        self.customFonts = fontLibraryService.registerAllStoredFonts()
        refreshDerivedMetadata()
        if compileOnInit {
            if let repoToRestore = activeRepo {
                Task { [weak self] in
                    await self?.restoreActiveRepoOnLaunch(repoToRestore)
                }
            }
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
        bibEntries = BibliographyService.extractEntries(fromSource: sourceText, bibFileContent: managedBibContent)
        documentLabels = BibliographyService.extractLabels(from: sourceText)
        documentStats = Expl3Linter.computeStatistics(source: sourceText)
        staticLintWarnings = Expl3Linter.lint(source: sourceText)
        diagnostics = lastCompilerDiagnostics + staticLintWarnings
        demystifiedDiagnostics = ContextSuggestionsEngine.demystify(diagnostics: diagnostics, source: sourceText)
        academicStats = Expl3Linter.computeAcademicStatistics(
            source: sourceText,
            bibEntries: bibEntries,
            pageCount: lastRenderedPageCount
        )
        preflightReport = AcademicPreflightService.analyze(
            source: sourceText,
            bibEntries: bibEntries,
            diagnostics: diagnostics,
            documentDirectory: currentFileURL?.deletingLastPathComponent(),
            tempFiguresDirectory: tempFiguresDirectory,
            stats: academicStats,
            rubricTargets: rubricTargets
        )
        isBlindReviewEnabled = sourceText.contains("\\linenumbers")
        isDoubleSpacedEnabled = sourceText.contains("\\doublespacing")
        refreshSpellingIssues()
    }

    private func refreshSpellingIssues() {
        guard proseSpellCheckEnabled else {
            spellingIssues = []
            return
        }
        spellingIssues = LaTeXSpellCheckService.scan(source: sourceText, ignoredWords: ignoredSpellingWords)
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
        var additionalTextFiles: [String: String] = [:]
        let trimmedBib = managedBibContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBib.isEmpty {
            additionalTextFiles["references.bib"] = trimmedBib + "\n"
        }

        var assetDirs: [URL] = [tempFiguresDirectory]
        if let docDir {
            assetDirs.insert(docDir, at: 0)
        }

        let result = await tectonicService.compile(
            source: codeSnapshot,
            documentDirectory: docDir,
            fontDirectories: [fontLibraryService.fontsDirectory],
            additionalTextFiles: additionalTextFiles,
            assetSearchDirectories: assetDirs
        )

        lastCompilerDiagnostics = result.diagnostics
        diagnostics = lastCompilerDiagnostics + staticLintWarnings
        demystifiedDiagnostics = ContextSuggestionsEngine.demystify(diagnostics: diagnostics, source: sourceText)
        consoleLog = result.logOutput

        if result.success, let url = result.pdfURL {
            pdfURL = url
            pdfRevision += 1
            synctexData = result.synctexData
            let pageCount = PDFDocument(url: url)?.pageCount ?? 1
            lastRenderedPageCount = pageCount
            academicStats = Expl3Linter.computeAcademicStatistics(
                source: sourceText,
                bibEntries: bibEntries,
                pageCount: pageCount
            )
            preflightReport = AcademicPreflightService.analyze(
                source: sourceText,
                bibEntries: bibEntries,
                diagnostics: diagnostics,
                documentDirectory: docDir,
                tempFiguresDirectory: tempFiguresDirectory,
                stats: academicStats,
                rubricTargets: rubricTargets
            )
            compilationState = .success(durationMs: result.durationMs, pageCount: pageCount)
        } else {
            preflightReport = AcademicPreflightService.analyze(
                source: sourceText,
                bibEntries: bibEntries,
                diagnostics: diagnostics,
                documentDirectory: docDir,
                tempFiguresDirectory: tempFiguresDirectory,
                stats: academicStats,
                rubricTargets: rubricTargets
            )
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
        activeProject = nil
        managedBibContent = ""
        bibSearchResults = []
        bibLookupError = nil
        lastExportedZipURL = nil
        sourceText = template.content
        markSavedStateClean()
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
        let safeKey = AcademicSanitizer.sanitizeIdentifier(entry.key, fallback: "ref")
        let safeAuthor = AcademicSanitizer.sanitizeExternalMetadata(entry.author, fallback: "Unknown Author")
        let safeTitle = AcademicSanitizer.sanitizeExternalMetadata(entry.title, fallback: "Untitled")
        let safeYear = AcademicSanitizer.sanitizeIdentifier(String(entry.year.prefix(4)), fallback: "2026")
        let formattedItem = """
\\bibitem{\(safeKey)}
\(safeAuthor), ``\(safeTitle),'' \(safeYear).
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
        guard let validatedURL = Self.validatedDroppedImageURL(url) else {
            pendingDroppedFigureURL = nil
            return
        }
        pendingDroppedFigureURL = validatedURL
        showFigureAssistantSheet = true
    }

    public static func validatedDroppedImageURL(_ url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        let standardized = url.standardizedFileURL
        guard !isSymbolicLinkPath(standardized) else { return nil }
        let ext = standardized.pathExtension.lowercased()
        let allowedExts: Set<String> = ["png", "jpg", "jpeg", "pdf", "tiff", "tif"]
        guard allowedExts.contains(ext) else { return nil }

        let resolved = standardized.resolvingSymlinksInPath()
        let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else { return nil }
        let size = Int64(values?.fileSize ?? 0)
        guard size <= SubmissionExportService.maxAssetBytes else { return nil }
        return resolved
    }

    // MARK: - File Operations (Open / Save / Export PDF)

    public func openTexFile() {
        let panel = NSOpenPanel()
        panel.title = "Open LaTeX Document"
        panel.allowedContentTypes = [UTType(filenameExtension: "tex") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if loadDocumentFromDisk(at: url) {
                Task { await compileNow() }
            }
        }
    }

    @discardableResult
    func loadDocumentFromDisk(at url: URL) -> Bool {
        guard let loaded = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        currentFileURL = url
        activeProject = nil
        bibSearchResults = []
        bibLookupError = nil
        lastExportedZipURL = nil
        let docDir = url.deletingLastPathComponent()
        let bibURL = docDir.appendingPathComponent("references.bib")
        if !Self.isSymbolicLinkPath(bibURL),
           let bibText = try? String(contentsOf: bibURL, encoding: .utf8) {
            managedBibContent = bibText
        } else {
            managedBibContent = ""
        }
        sourceText = loaded
        markSavedStateClean()
        return true
    }

    public func saveTexFile(saveAs: Bool = false) {
        if !saveAs, let existingURL = currentFileURL {
            persistDocumentAndAssets(to: existingURL)
            return
        }
        let panel = NSSavePanel()
        panel.title = "Save LaTeX3 Document"
        panel.nameFieldStringValue = currentFileURL?.lastPathComponent ?? "document.tex"
        panel.allowedContentTypes = [UTType(filenameExtension: "tex") ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            currentFileURL = url
            persistDocumentAndAssets(to: url)
        }
    }

    func persistDocumentAndAssets(to texURL: URL, bibURL explicitBibURL: URL? = nil) {
        guard texURL.isFileURL, !Self.isSymbolicLinkPath(texURL) else { return }
        try? sourceText.write(to: texURL, atomically: true, encoding: .utf8)
        let docDir = texURL.deletingLastPathComponent()
        let fm = FileManager.default

        // Sync references.bib (or validated project bibFile) beside saved .tex file
        let trimmedBib = managedBibContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let bibDest = explicitBibURL ?? docDir.appendingPathComponent("references.bib")
        if bibDest.isFileURL, !Self.isSymbolicLinkPath(bibDest) {
            if !trimmedBib.isEmpty {
                try? (trimmedBib + "\n").write(to: bibDest, atomically: true, encoding: .utf8)
            } else if activeProject != nil, fm.fileExists(atPath: bibDest.path) {
                try? "".write(to: bibDest, atomically: true, encoding: .utf8)
            }
        }

        // Migrate any TempFigures assets referenced in sourceText to <docDir>/figures/
        let figureRefs = AcademicPreflightService.extractFigurePaths(from: sourceText)
        guard !figureRefs.isEmpty else {
            markSavedStateClean()
            refreshDerivedMetadata()
            return
        }
        let resolvedTempDir = tempFiguresDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let tempPrefix = resolvedTempDir.path.hasSuffix("/") ? resolvedTempDir.path : resolvedTempDir.path + "/"

        if let docFiguresDir = Self.validatedContainedFiguresDirectory(in: docDir) {
            let resolvedFigDir = docFiguresDir.resolvingSymlinksInPath()
            let figPrefix = resolvedFigDir.path.hasSuffix("/") ? resolvedFigDir.path : resolvedFigDir.path + "/"

            for ref in figureRefs where ref.path.hasPrefix("figures/") {
                let leaf = String(ref.path.dropFirst("figures/".count))
                guard let validLeaf = AcademicSanitizer.validatedRelativeAssetPath(leaf) else { continue }
                let tempSrc = tempFiguresDirectory.appendingPathComponent(validLeaf).standardizedFileURL
                guard !Self.isSymbolicLinkPath(tempSrc) else { continue }
                let resolvedTempSrc = tempSrc.resolvingSymlinksInPath()
                guard resolvedTempSrc.path.hasPrefix(tempPrefix) else { continue }
                let srcVals = try? resolvedTempSrc.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard srcVals?.isRegularFile == true,
                      srcVals?.isSymbolicLink != true,
                      Int64(srcVals?.fileSize ?? 0) <= SubmissionExportService.maxAssetBytes else {
                    continue
                }

                let destURL = docFiguresDir.appendingPathComponent(validLeaf).standardizedFileURL
                guard !Self.isSymbolicLinkPath(destURL) else { continue }
                let destParent = destURL.deletingLastPathComponent()
                let resolvedParent = destParent.resolvingSymlinksInPath()
                guard resolvedParent.path == resolvedFigDir.path || resolvedParent.path.hasPrefix(figPrefix) else {
                    continue
                }
                if fm.fileExists(atPath: resolvedTempSrc.path), !fm.fileExists(atPath: destURL.path) {
                    try? fm.createDirectory(at: destParent, withIntermediateDirectories: true)
                    guard !Self.isSymbolicLinkPath(destParent) else { continue }
                    try? fm.copyItem(at: resolvedTempSrc, to: destURL)
                }
            }
        }
        refreshDerivedMetadata()
        markSavedStateClean()
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

    // MARK: - Academic Paper Authoring Suite Actions (v0.2.0)

    public func searchCrossRefCitations() {
        let query = bibLookupQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearchingCrossRef = true
        isFetchingBib = true
        bibLookupError = nil

        Task { [weak self] in
            guard let self else { return }
            defer {
                self.isSearchingCrossRef = false
                self.isFetchingBib = false
            }
            do {
                let results = try await BibliographyService.smartLookup(query: query)
                self.bibSearchResults = results
                // If user pasted a direct DOI / arXiv / ISBN / URL yielding 1 exact entry, import automatically
                let isDirectID = query.lowercased().hasPrefix("10.") ||
                    query.lowercased().contains("doi.org/") ||
                    query.lowercased().contains("arxiv.org/") ||
                    query.lowercased().hasPrefix("arxiv:") ||
                    query.range(of: #"^\d{4}\.\d{4,5}"#, options: .regularExpression) != nil ||
                    BibliographyService.extractValidISBN(from: query) != nil
                if isDirectID, let first = results.first {
                    self.importBibEntry(first, intoBibFile: true)
                    self.bibLookupQuery = ""
                }
            } catch {
                self.bibLookupError = error.localizedDescription
            }
        }
    }

    public func importBibEntry(_ entry: BibEntry, intoBibFile: Bool = true) {
        if intoBibFile {
            let existing = (try? BibliographyService.parseBibContent(managedBibContent, strict: false)) ?? []
            if let existingSame = existing.first(where: { $0.key == entry.key && $0.title.caseInsensitiveCompare(entry.title) == .orderedSame }) {
                _ = existingSame
                return
            }
            let outcome = BibliographyService.mergeEntries(
                [entry],
                intoExistingBibContent: managedBibContent,
                replaceDuplicates: false
            )
            managedBibContent = outcome.mergedContent
            if let docDir = currentFileURL?.deletingLastPathComponent(),
               !Self.isSymbolicLinkPath(docDir) {
                let bibURL = docDir.appendingPathComponent("references.bib")
                if !Self.isSymbolicLinkPath(bibURL) {
                    try? managedBibContent.write(to: bibURL, atomically: true, encoding: .utf8)
                }
            }
        } else {
            appendBibItemToSource(entry)
        }
    }

    public func importBibFileViaPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import BibTeX Library (.bib)"
        let bibTypes: [UTType] = [UTType(filenameExtension: "bib") ?? .plainText, .plainText]
        panel.allowedContentTypes = bibTypes
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            handleDroppedBibFileURL(url)
        }
    }

    public func handleDroppedBibFileURL(_ url: URL) {
        bibLookupError = nil
        do {
            let imported = try BibliographyService.parseBibFile(at: url)
            guard !imported.isEmpty else {
                bibLookupError = "No BibTeX entries were found in '\(url.lastPathComponent)'."
                return
            }
            let outcome = BibliographyService.mergeEntries(
                imported,
                intoExistingBibContent: managedBibContent,
                replaceDuplicates: false
            )
            managedBibContent = outcome.mergedContent
            if let docDir = currentFileURL?.deletingLastPathComponent(),
               !Self.isSymbolicLinkPath(docDir) {
                let bibURL = docDir.appendingPathComponent("references.bib")
                if !Self.isSymbolicLinkPath(bibURL) {
                    try? managedBibContent.write(to: bibURL, atomically: true, encoding: .utf8)
                }
            }
        } catch {
            bibLookupError = error.localizedDescription
        }
    }

    public func insertFormattedCitation(_ entry: BibEntry, style: CitationCommandStyle, pageLocator: String?) {
        selectedCitationStyle = style
        // Ensure entry exists in bibliography library if not already present inline or in managed .bib
        if !bibEntries.contains(where: { $0.key == entry.key }) {
            importBibEntry(entry, intoBibFile: true)
        }
        let formatted = style.format(key: entry.key, pageLocator: pageLocator)
        insertTextAtCaret(formatted)
    }

    public func applyBibliographyStyle(_ style: BibliographyStylePreset) {
        selectedBibliographyStyle = style
        var updated = sourceText
        let styleOpt = style.biblatexStyleOption
        let desiredPkg = "\\usepackage[style=\(styleOpt),backend=bibtex]{biblatex}"

        if let bibRegex = try? NSRegularExpression(pattern: #"\\usepackage(?:\[[^\]]*\])?\{biblatex\}"#) {
            let ns = updated as NSString
            if bibRegex.firstMatch(in: updated, range: NSRange(location: 0, length: ns.length)) != nil {
                updated = bibRegex.stringByReplacingMatches(
                    in: updated,
                    range: NSRange(location: 0, length: ns.length),
                    withTemplate: NSRegularExpression.escapedTemplate(for: desiredPkg)
                )
            } else if let beginDocRange = updated.range(of: "\\begin{document}") {
                updated.insert(contentsOf: "\(desiredPkg)\n\\addbibresource{references.bib}\n", at: beginDocRange.lowerBound)
            } else {
                updated = "\(desiredPkg)\n\\addbibresource{references.bib}\n" + updated
            }
        }

        if !updated.contains("\\addbibresource"), let beginDocRange = updated.range(of: "\\begin{document}") {
            updated.insert(contentsOf: "\\addbibresource{references.bib}\n", at: beginDocRange.lowerBound)
        }
        if !updated.contains("\\printbibliography") && !updated.contains("\\bibliography{") && !updated.contains("\\begin{thebibliography}"),
           let endDocRange = updated.range(of: "\\end{document}") {
            updated.replaceSubrange(endDocRange, with: "\n\\printbibliography\n\n\\end{document}")
        }

        sourceText = updated
    }

    public func applyPaperSetupWizard(_ config: PaperSetupConfig) {
        currentFileURL = nil
        activeProject = nil
        selectedBibliographyStyle = config.bibliographyStyle
        isDoubleSpacedEnabled = config.doubleSpacing
        isBlindReviewEnabled = config.anonymizedBlindReview
        sourceText = LaTeXCatalog.generateWizardDocument(from: config)
        markSavedStateClean()
        if autoCompileEnabled {
            Task { await compileNow() }
        }
    }

    public func toggleBlindReview(_ enabled: Bool) {
        isBlindReviewEnabled = enabled
        if enabled {
            sourceText = SubmissionExportService.applyBlindReviewTransform(to: sourceText)
        } else {
            var lines = sourceText.components(separatedBy: .newlines)
            lines.removeAll { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed == "\\linenumbers" || trimmed == "\\usepackage{lineno}"
            }
            sourceText = lines.joined(separator: "\n")
        }
    }

    public func toggleDoubleSpacing(_ enabled: Bool) {
        isDoubleSpacedEnabled = enabled
        var updated = sourceText
        if enabled {
            if let setspacePreset = LaTeXCatalog.commonPackages.first(where: { $0.package == "setspace" }) {
                if !updated.contains("\\usepackage{setspace}") {
                    var lines = updated.components(separatedBy: .newlines)
                    if let docIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("\\documentclass") }) {
                        lines.insert(setspacePreset.usepackageStatement, at: docIdx + 1)
                        updated = lines.joined(separator: "\n")
                    } else {
                        updated = setspacePreset.usepackageStatement + "\n" + updated
                    }
                }
            }
            if !updated.contains("\\doublespacing") {
                if let beginDoc = updated.range(of: "\\begin{document}") {
                    updated.insert(contentsOf: "\\doublespacing\n", at: beginDoc.lowerBound)
                } else {
                    updated += "\n\\doublespacing"
                }
            }
        } else {
            var lines = updated.components(separatedBy: .newlines)
            lines.removeAll { $0.trimmingCharacters(in: .whitespaces) == "\\doublespacing" }
            updated = lines.joined(separator: "\n")
        }
        sourceText = updated
    }

    public func updateRubricTargets(_ targets: RubricTargetConfig) {
        rubricTargets = targets
        if let encoded = try? JSONEncoder().encode(targets) {
            userDefaults.set(encoded, forKey: Self.rubricTargetsDefaultsKey)
        }
        refreshDerivedMetadata()
        markSavedStateClean()
    }

    public func applyAcademicFix(_ op: AcademicFixOperation) {
        switch op {
        case .replaceLine(let lineNumber, let originalSubstring, let replacement):
            var lines = sourceText.components(separatedBy: .newlines)
            let idx = lineNumber - 1
            guard idx >= 0, idx < lines.count else { return }
            if let range = lines[idx].range(of: originalSubstring) {
                lines[idx].replaceSubrange(range, with: replacement)
                sourceText = lines.joined(separator: "\n")
            }

        case .insertPackage(let packageName, let options):
            let cleanPkg = AcademicSanitizer.sanitizeIdentifier(packageName, fallback: "")
            guard !cleanPkg.isEmpty else { return }
            let alreadyLoaded = sourceText.range(
                of: #"\\usepackage(?:\[[^\]]*\])?\{[^}]*\b"# + NSRegularExpression.escapedPattern(for: cleanPkg) + #"\b[^}]*\}"#,
                options: .regularExpression
            ) != nil
            guard !alreadyLoaded else { return }

            let stmt = options.isEmpty ? "\\usepackage{\(cleanPkg)}" : "\\usepackage[\(options)]{\(cleanPkg)}"
            var lines = sourceText.components(separatedBy: .newlines)
            if let docIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("\\documentclass") }) {
                lines.insert(stmt, at: docIdx + 1)
                if cleanPkg == "pgfplots" && !sourceText.contains("\\pgfplotsset") {
                    lines.insert("\\pgfplotsset{compat=1.18}", at: docIdx + 2)
                }
                sourceText = lines.joined(separator: "\n")
            } else {
                sourceText = stmt + "\n" + sourceText
            }

        case .wrapLineInMath(let lineNumber):
            var lines = sourceText.components(separatedBy: .newlines)
            let idx = lineNumber - 1
            guard idx >= 0, idx < lines.count else { return }
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.contains("$") else { return }
            let leadingWS = String(lines[idx].prefix(while: { $0 == " " || $0 == "\t" }))
            lines[idx] = "\(leadingWS)$\(trimmed)$"
            sourceText = lines.joined(separator: "\n")

        case .appendMissingBrace(let lineNumber):
            var lines = sourceText.components(separatedBy: .newlines)
            let idx = lineNumber - 1
            guard idx >= 0, idx < lines.count else { return }
            lines[idx] += "}"
            sourceText = lines.joined(separator: "\n")

        case .insertRawSnippet(let snippet):
            insertTextAtCaret(snippet)
        }
    }

    public func applySpellingSuggestion(_ issue: SpellingIssue, replacement: String) {
        let nsSource = sourceText as NSString
        guard issue.nsRange.location != NSNotFound,
              issue.nsRange.location + issue.nsRange.length <= nsSource.length else {
            return
        }
        let currentSlice = nsSource.substring(with: issue.nsRange)
        guard currentSlice == issue.word else {
            refreshSpellingIssues()
            return
        }
        sourceText = nsSource.replacingCharacters(in: issue.nsRange, with: replacement)
    }

    public func ignoreSpellingWord(_ word: String) {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        ignoredSpellingWords.insert(normalized)
        userDefaults.set(Array(ignoredSpellingWords).sorted(), forKey: Self.ignoredSpellingWordsKey)
        refreshSpellingIssues()
    }

    public func insertTextAtCaret(_ text: String, backtrackOffset: Int = 0) {
        pendingEditorInsertion = EditorInsertionRequest(text: text, cursorBacktrackOffset: backtrackOffset)
    }

    public func insertFigureWithConfig(sourceURL: URL, secondaryURL: URL?, config: FigureInsertConfig) {
        guard let primaryRel = copyImageAssetToProjectFigures(from: sourceURL) else {
            return
        }
        var updatedConfig = config
        updatedConfig.primaryRelativePath = primaryRel

        if let secondaryURL {
            if let secondaryRel = copyImageAssetToProjectFigures(from: secondaryURL) {
                updatedConfig.secondaryRelativePath = secondaryRel
            }
        } else {
            updatedConfig.secondaryRelativePath = nil
        }

        applyAcademicFix(.insertPackage(packageName: "graphicx", options: ""))
        if updatedConfig.secondaryRelativePath != nil {
            applyAcademicFix(.insertPackage(packageName: "subcaption", options: ""))
        }

        let snippet = AcademicToolsGenerator.generateFigureSnippet(from: updatedConfig)
        insertTextAtCaret(snippet)
    }

    public func insertSpreadsheetTable() {
        applyAcademicFix(.insertPackage(packageName: "booktabs", options: ""))
        let latex = AcademicToolsGenerator.generateBooktabsTable(from: tableGridData)
        insertTextAtCaret(latex)
    }

    public func insertPGFPlotChart() {
        applyAcademicFix(.insertPackage(packageName: "pgfplots", options: ""))
        let latex = AcademicToolsGenerator.generatePGFPlotChart(from: chartConfig)
        insertTextAtCaret(latex)
    }

    public func exportSubmissionBundle(stripComments: Bool = false, anonymize: Bool = false) {
        let panel = NSSavePanel()
        panel.title = "Export Clean Submission Bundle (.zip)"
        let baseName = currentFileURL?.deletingPathExtension().lastPathComponent ?? "paper"
        panel.nameFieldStringValue = "\(baseName)-submission.zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let destURL = panel.url else {
            return
        }

        isExportingSubmissionBundle = true
        submissionExportMessage = nil
        lastExportedZipURL = nil
        let sourceSnapshot = sourceText
        let mainName = currentFileURL?.lastPathComponent ?? "main.tex"
        let bibSnapshot = managedBibContent
        let docDir = currentFileURL?.deletingLastPathComponent()
        let tempFigs = tempFiguresDirectory
        let fontsSnapshot = customFonts
        let fontDir = fontLibraryService.fontsDirectory

        Task { [weak self] in
            guard let self else { return }
            defer { self.isExportingSubmissionBundle = false }
            do {
                let result = try await SubmissionExportService.exportBundle(
                    source: sourceSnapshot,
                    mainFileName: mainName,
                    destinationZipURL: destURL,
                    managedBibContent: bibSnapshot,
                    documentDirectory: docDir,
                    tempFiguresDirectory: tempFigs,
                    customFonts: fontsSnapshot,
                    fontLibraryDirectory: fontDir,
                    stripComments: stripComments,
                    anonymize: anonymize,
                    verifyCompileWithTectonic: true
                )
                self.lastExportedZipURL = result.zipURL
                let warningNote = result.preflightWarnings.isEmpty ? "" : " (\(result.preflightWarnings.count) warning(s))"
                self.submissionExportMessage = "Exported \(result.includedFiles.count) file(s) to '\(result.zipURL.lastPathComponent)'\(warningNote)."
            } catch {
                self.submissionExportMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Private Asset Staging Helper

    private static func isSymbolicLinkPath(_ url: URL) -> Bool {
        let std = url.standardizedFileURL
        if let vals = try? std.resourceValues(forKeys: [.isSymbolicLinkKey]), vals.isSymbolicLink == true {
            return true
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: std.path),
           (attrs[.type] as? FileAttributeType) == .typeSymbolicLink {
            return true
        }
        return false
    }

    static func validatedContainedFiguresDirectory(in docDir: URL) -> URL? {
        guard docDir.isFileURL, !isSymbolicLinkPath(docDir) else { return nil }
        let fm = FileManager.default
        let resolvedDocDir = docDir.standardizedFileURL.resolvingSymlinksInPath()
        let figuresDir = docDir.appendingPathComponent("figures", isDirectory: true).standardizedFileURL
        guard !isSymbolicLinkPath(figuresDir) else { return nil }

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: figuresDir.path, isDirectory: &isDir) {
            guard isDir.boolValue else { return nil }
        } else {
            do {
                try fm.createDirectory(at: figuresDir, withIntermediateDirectories: true)
            } catch {
                return nil
            }
        }

        guard !isSymbolicLinkPath(figuresDir) else { return nil }
        let resolvedFigures = figuresDir.resolvingSymlinksInPath()
        let prefix = resolvedDocDir.path.hasSuffix("/") ? resolvedDocDir.path : resolvedDocDir.path + "/"
        guard resolvedFigures.path.hasPrefix(prefix) else { return nil }
        return figuresDir
    }

    func copyImageAssetToProjectFigures(from sourceURL: URL) -> String? {
        guard let resolved = Self.validatedDroppedImageURL(sourceURL) else { return nil }

        let safeLeaf = AcademicSanitizer.sanitizeFigureFileName(resolved.lastPathComponent)
        let targetDir: URL
        if let docDir = currentFileURL?.deletingLastPathComponent() {
            guard let safeDocFigs = Self.validatedContainedFiguresDirectory(in: docDir) else {
                return nil
            }
            targetDir = safeDocFigs
        } else {
            guard !Self.isSymbolicLinkPath(tempFiguresDirectory) else { return nil }
            try? FileManager.default.createDirectory(at: tempFiguresDirectory, withIntermediateDirectories: true)
            targetDir = tempFiguresDirectory
        }

        let destURL = targetDir.appendingPathComponent(safeLeaf).standardizedFileURL
        guard !Self.isSymbolicLinkPath(destURL) else { return nil }
        let resolvedTarget = targetDir.resolvingSymlinksInPath()
        let resolvedDestParent = destURL.deletingLastPathComponent().resolvingSymlinksInPath()
        guard resolvedDestParent.path == resolvedTarget.path else { return nil }

        if resolved != destURL.resolvingSymlinksInPath() {
            try? FileManager.default.removeItem(at: destURL)
            do {
                try FileManager.default.copyItem(at: resolved, to: destURL)
            } catch {
                return nil
            }
        }
        return "figures/\(safeLeaf)"
    }

    // MARK: - GitHub Repository Multi-Project Storage Actions (v0.3.0)

    public var isInGitConflictState: Bool {
        if case .conflict = gitSyncState {
            return true
        }
        return false
    }

    public var defaultCommitMessagePreview: String {
        GitHubWorkspaceValidator.defaultCommitMessage(projectName: activeProject?.displayName ?? "Project")
    }

    private func refreshDirtyFlag() {
        hasUnsavedBufferEdits = (sourceText != lastSavedSourceText) || (managedBibContent != lastSavedBibContent)
    }

    private func markSavedStateClean() {
        lastSavedSourceText = sourceText
        lastSavedBibContent = managedBibContent
        hasUnsavedBufferEdits = false
    }

    public func detectAndTestGitHubCLI() async -> GitHubAuthenticatedUser? {
        let store = gitCredentialStore
        let token = await Task.detached(priority: .userInitiated) {
            store.detectGitHubCLIToken()
        }.value
        guard let token, !token.isEmpty else {
            authenticatedGitHubUser = nil
            return nil
        }
        do {
            let user = try await GitHubAPIService.fetchAuthenticatedUser(token: token)
            authenticatedGitHubUser = user
            if let repos = try? await GitHubAPIService.listUserRepositories(token: token) {
                availableGitHubRepos = repos
            }
            return user
        } catch {
            repoStatusMessage = error.localizedDescription
            return nil
        }
    }

    public func validateAndFetchGitHubRepos(token: String) async throws -> [GitHubRemoteRepository] {
        let user = try await GitHubAPIService.fetchAuthenticatedUser(token: token)
        authenticatedGitHubUser = user
        let repos = try await GitHubAPIService.listUserRepositories(token: token)
        availableGitHubRepos = repos
        return repos
    }

    public func saveDocument() {
        if activeRepo != nil && activeProject != nil {
            Task { [weak self] in
                await self?.saveAndCommitCurrentProject(customMessage: nil, pushImmediately: nil)
            }
        } else {
            saveTexFile(saveAs: false)
        }
    }

    public func connectGitHubRepository(
        remoteURL: String,
        branch: String = "main",
        authMethod: GitAuthMethod = .personalAccessToken,
        token: String? = nil,
        autoPushOnSave: Bool = true,
        includePDFsInCommits: Bool = false
    ) async {
        guard let parsed = await gitRepositoryService.parseRemoteURL(remoteURL) else {
            gitSyncState = .failed(message: "Enter a valid GitHub repository URL (https://github.com/owner/repo or owner/repo).")
            repoStatusMessage = "Invalid GitHub repository URL."
            return
        }
        guard let validBranch = GitHubWorkspaceValidator.validatedBranchName(branch) else {
            gitSyncState = .failed(message: "Invalid branch name '\(branch)'.")
            repoStatusMessage = "Invalid branch name."
            return
        }

        let cleanFolder = "\(parsed.owner)-\(parsed.repo)"
        let connection = GitHubRepoConnection(
            owner: parsed.owner,
            repoName: parsed.repo,
            remoteURLString: parsed.normalizedURL,
            branch: validBranch,
            authMethod: authMethod,
            localFolderName: cleanFolder,
            autoPushOnSave: autoPushOnSave,
            includePDFsInCommits: includePDFsInCommits,
            lastSyncedAt: nil
        )

        if authMethod == .personalAccessToken,
           let cleanToken = token?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cleanToken.isEmpty {
            do {
                try gitCredentialStore.saveToken(cleanToken, forAccount: connection.fullName)
            } catch {
                gitSyncState = .failed(message: error.localizedDescription)
                repoStatusMessage = error.localizedDescription
                return
            }
        }

        gitSyncState = .syncing(status: "Cloning \(connection.fullName)...")
        repoStatusMessage = nil

        do {
            let outcome = try await gitRepositoryService.cloneOrOpenRepository(connection: connection, token: token)
            var updatedConn = connection
            if case .idle(_, _, let lastSync) = outcome.syncState {
                updatedConn.lastSyncedAt = lastSync
            }
            upsertConnectedRepo(updatedConn)
            activeRepo = updatedConn
            commitPushImmediately = updatedConn.autoPushOnSave
            repoProjects = outcome.manifest.projects
            looseRepoTeXFiles = outcome.looseTeXPaths
            gitSyncState = outcome.syncState
            persistConnectedRepos()

            if let first = outcome.manifest.projects.first {
                await openProjectFromActiveRepo(first)
            } else {
                activeProject = nil
                currentFileURL = nil
                pendingProjectChanges = []
                projectCommitHistory = []
                userDefaults.removeObject(forKey: Self.activeGitHubProjectIDKey)
            }
            repoStatusMessage = "Connected to \(updatedConn.fullName)."
        } catch {
            gitSyncState = .failed(message: error.localizedDescription)
            repoStatusMessage = error.localizedDescription
        }
    }

    public func createAndConnectGitHubRepository(
        name: String,
        description: String = "",
        isPrivate: Bool = true,
        branch: String = "main",
        token: String,
        autoPushOnSave: Bool = true,
        includePDFsInCommits: Bool = false
    ) async {
        gitSyncState = .syncing(status: "Creating repository '\(name)' on GitHub...")
        repoStatusMessage = nil
        do {
            let created = try await GitHubAPIService.createRepository(
                name: name,
                description: description,
                isPrivate: isPrivate,
                autoInit: true,
                token: token
            )
            await connectGitHubRepository(
                remoteURL: created.cloneURL,
                branch: created.defaultBranch.isEmpty ? branch : created.defaultBranch,
                authMethod: .personalAccessToken,
                token: token,
                autoPushOnSave: autoPushOnSave,
                includePDFsInCommits: includePDFsInCommits
            )
        } catch {
            gitSyncState = .failed(message: error.localizedDescription)
            repoStatusMessage = error.localizedDescription
        }
    }

    public func switchActiveRepo(_ repo: GitHubRepoConnection) async {
        activeRepo = repo
        commitPushImmediately = repo.autoPushOnSave
        persistConnectedRepos()
        await restoreActiveRepoOnLaunch(repo)
    }

    public func updateActiveRepoSettings(autoPushOnSave: Bool, includePDFsInCommits: Bool) async {
        guard var repo = activeRepo else { return }
        repo.autoPushOnSave = autoPushOnSave
        repo.includePDFsInCommits = includePDFsInCommits
        upsertConnectedRepo(repo)
        activeRepo = repo
        commitPushImmediately = autoPushOnSave
        persistConnectedRepos()

        if let repoURL = try? await gitRepositoryService.localRepositoryURL(for: repo) {
            try? await gitRepositoryService.updateGitIgnore(in: repoURL, includePDFs: includePDFsInCommits)
        }
    }

    public func disconnectRepo(_ repo: GitHubRepoConnection, deleteLocalClone: Bool = false) {
        try? gitCredentialStore.deleteToken(forAccount: repo.fullName)
        connectedRepos.removeAll { $0.id == repo.id }
        if activeRepo?.id == repo.id {
            activeRepo = connectedRepos.first
            repoProjects = []
            activeProject = nil
            currentFileURL = nil
            pendingProjectChanges = []
            projectCommitHistory = []
            looseRepoTeXFiles = []
            userDefaults.removeObject(forKey: Self.activeGitHubProjectIDKey)
            gitSyncState = activeRepo == nil ? .disconnected : .idle(aheadCount: 0, behindCount: 0, lastSync: activeRepo?.lastSyncedAt)
            if let nextRepo = activeRepo {
                commitPushImmediately = nextRepo.autoPushOnSave
                Task { [weak self] in
                    await self?.restoreActiveRepoOnLaunch(nextRepo)
                }
            }
        }
        persistConnectedRepos()

        if deleteLocalClone {
            Task { [gitRepositoryService] in
                if let url = try? await gitRepositoryService.localRepositoryURL(for: repo) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    public func createProjectInActiveRepo(
        displayName: String,
        customSlug: String? = nil,
        template: LaTeXTemplate = LaTeXCatalog.defaultTemplate,
        importCurrentDocument: Bool = false
    ) async {
        guard let repo = activeRepo else {
            repoStatusMessage = "Connect a GitHub repository first."
            return
        }
        gitSyncState = .committing
        repoStatusMessage = nil

        do {
            let repoURL = try await gitRepositoryService.localRepositoryURL(for: repo)
            let mainText = importCurrentDocument ? sourceText : template.content
            let bibText = importCurrentDocument ? managedBibContent : ""
            let outcome = try await gitRepositoryService.createProject(
                in: repoURL,
                connection: repo,
                displayName: displayName,
                customSlug: customSlug,
                mainContent: mainText,
                bibContent: bibText,
                templateId: importCurrentDocument ? nil : template.id,
                rubricTargets: rubricTargets,
                copyFiguresFrom: importCurrentDocument ? tempFiguresDirectory : nil,
                token: nil
            )
            repoProjects = outcome.manifest.projects
            gitSyncState = outcome.syncState
            if case .idle(_, _, let syncedAt) = outcome.syncState, let syncedAt {
                var updatedRepo = repo
                updatedRepo.lastSyncedAt = syncedAt
                upsertConnectedRepo(updatedRepo)
                activeRepo = updatedRepo
                persistConnectedRepos()
            }
            await openProjectFromActiveRepo(outcome.project)
            repoStatusMessage = "Created project '\(outcome.project.displayName)'."
        } catch {
            gitSyncState = .failed(message: error.localizedDescription)
            repoStatusMessage = error.localizedDescription
        }
    }

    public func importExistingTeXFileAsProject(relativeTeXPath: String, displayName: String) async {
        guard let repo = activeRepo else { return }
        gitSyncState = .committing
        do {
            let repoURL = try await gitRepositoryService.localRepositoryURL(for: repo)
            let outcome = try await gitRepositoryService.importLooseTeXFileIntoProject(
                in: repoURL,
                connection: repo,
                relativeTeXPath: relativeTeXPath,
                displayName: displayName,
                token: nil
            )
            repoProjects = outcome.manifest.projects
            gitSyncState = outcome.syncState
            await openProjectFromActiveRepo(outcome.project)
            await loadProjectCommitHistory()
            repoStatusMessage = "Imported '\(relativeTeXPath)' into project '\(outcome.project.displayName)'."
        } catch {
            gitSyncState = .failed(message: error.localizedDescription)
            repoStatusMessage = error.localizedDescription
        }
    }

    private static func hasSymlinkAlongRelativePath(_ relativePath: String, baseDir: URL) -> Bool {
        var cursor = baseDir.standardizedFileURL
        for part in relativePath.split(separator: "/").map(String.init) {
            cursor = cursor.appendingPathComponent(part).standardizedFileURL
            if isSymbolicLinkPath(cursor) {
                return true
            }
        }
        return false
    }

    private static func validatedProjectFilePaths(
        in repoURL: URL,
        project: AcademicProjectDescriptor
    ) -> (projectDir: URL, mainURL: URL, bibURL: URL)? {
        guard GitHubWorkspaceValidator.isValidProjectSlug(project.slug),
              project.relativePath == "projects/\(project.slug)",
              let mainRel = GitHubWorkspaceValidator.validatedProjectRelativeFile(project.mainTexFile, allowedExtensions: ["tex"]),
              let bibRel = GitHubWorkspaceValidator.validatedProjectRelativeFile(project.bibFile, allowedExtensions: ["bib"]) else {
            return nil
        }

        let stdRepo = repoURL.standardizedFileURL
        let projectsRoot = stdRepo.appendingPathComponent("projects", isDirectory: true).standardizedFileURL
        let projectDir = projectsRoot.appendingPathComponent(project.slug, isDirectory: true).standardizedFileURL
        guard !isSymbolicLinkPath(stdRepo),
              !isSymbolicLinkPath(projectsRoot),
              !isSymbolicLinkPath(projectDir),
              !hasSymlinkAlongRelativePath(mainRel, baseDir: projectDir),
              !hasSymlinkAlongRelativePath(bibRel, baseDir: projectDir) else {
            return nil
        }

        let resolvedRepo = stdRepo.resolvingSymlinksInPath().path
        let repoPrefix = resolvedRepo.hasSuffix("/") ? resolvedRepo : resolvedRepo + "/"
        let resolvedProject = projectDir.resolvingSymlinksInPath().path
        guard resolvedProject.hasPrefix(repoPrefix) else {
            return nil
        }

        let mainURL = projectDir.appendingPathComponent(mainRel).standardizedFileURL
        let bibURL = projectDir.appendingPathComponent(bibRel).standardizedFileURL
        let projPrefix = resolvedProject.hasSuffix("/") ? resolvedProject : resolvedProject + "/"
        guard mainURL.resolvingSymlinksInPath().path.hasPrefix(projPrefix),
              bibURL.resolvingSymlinksInPath().path.hasPrefix(projPrefix) else {
            return nil
        }

        return (projectDir, mainURL, bibURL)
    }

    public func openProjectFromActiveRepo(_ project: AcademicProjectDescriptor) async {
        guard let repo = activeRepo else { return }
        do {
            let repoURL = try await gitRepositoryService.localRepositoryURL(for: repo)
            guard let paths = Self.validatedProjectFilePaths(in: repoURL, project: project) else {
                repoStatusMessage = "Refused to open unsafe or symlinked path inside repository project."
                return
            }

            let loadedMain = (try? String(contentsOf: paths.mainURL, encoding: .utf8)) ?? ""
            let loadedBib = (try? String(contentsOf: paths.bibURL, encoding: .utf8)) ?? ""

            activeProject = project
            currentFileURL = paths.mainURL
            bibSearchResults = []
            bibLookupError = nil
            lastExportedZipURL = nil
            if let projRubric = project.rubricTargets {
                rubricTargets = projRubric
            }
            managedBibContent = loadedBib
            sourceText = loadedMain
            markSavedStateClean()
            userDefaults.set(project.id.uuidString, forKey: Self.activeGitHubProjectIDKey)

            pendingProjectChanges = (try? await gitRepositoryService.changedFiles(in: repoURL, projectRelativePath: project.relativePath)) ?? []
            await loadProjectCommitHistory()
            if autoCompileEnabled, !isInGitConflictState {
                await compileNow()
            }
        } catch {
            repoStatusMessage = error.localizedDescription
        }
    }

    public func discardUnsavedProjectEdits() async {
        if let project = activeProject {
            await openProjectFromActiveRepo(project)
        }
    }

    public func deleteProjectFromActiveRepo(_ project: AcademicProjectDescriptor, commitMessage: String? = nil) async {
        guard let repo = activeRepo else { return }
        gitSyncState = .committing
        do {
            let repoURL = try await gitRepositoryService.localRepositoryURL(for: repo)
            let outcome = try await gitRepositoryService.deleteProject(
                in: repoURL,
                connection: repo,
                project: project,
                commitMessage: commitMessage,
                token: nil
            )
            repoProjects = outcome.manifest.projects
            gitSyncState = outcome.syncState
            if activeProject?.id == project.id {
                activeProject = nil
                currentFileURL = nil
                pendingProjectChanges = []
                projectCommitHistory = []
                userDefaults.removeObject(forKey: Self.activeGitHubProjectIDKey)
                if let next = repoProjects.first {
                    await openProjectFromActiveRepo(next)
                }
            }
            repoStatusMessage = "Deleted project '\(project.displayName)'."
        } catch {
            gitSyncState = .failed(message: error.localizedDescription)
            repoStatusMessage = error.localizedDescription
        }
    }

    public func saveActiveDocumentAndCommit(customMessage: String? = nil, push: Bool? = nil) async {
        await saveAndCommitCurrentProject(customMessage: customMessage, pushImmediately: push)
    }

    public func saveAndCommitCurrentProject(customMessage: String? = nil, pushImmediately: Bool? = nil) async {
        guard var repo = activeRepo, let project = activeProject else {
            saveTexFile(saveAs: false)
            return
        }

        do {
            let repoURL = try await gitRepositoryService.localRepositoryURL(for: repo)
            guard let paths = Self.validatedProjectFilePaths(in: repoURL, project: project) else {
                gitSyncState = .failed(message: "Refused to save to unsafe or symlinked project path.")
                repoStatusMessage = "Refused to save to unsafe or symlinked project path."
                return
            }
            currentFileURL = paths.mainURL
            persistDocumentAndAssets(to: paths.mainURL, bibURL: paths.bibURL)

            let defaultMsg = GitHubWorkspaceValidator.defaultCommitMessage(projectName: project.displayName)
            let chosenMsg = (customMessage?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? defaultMsg
            let shouldPush = pushImmediately ?? repo.autoPushOnSave

            gitSyncState = .committing
            let result = try await gitRepositoryService.commitProjectChanges(
                in: repoURL,
                connection: repo,
                project: project,
                message: chosenMsg,
                pushAfterCommit: shouldPush,
                token: nil
            )

            if case .idle(_, _, let syncedAt) = result.syncState, let syncedAt {
                repo.lastSyncedAt = syncedAt
                upsertConnectedRepo(repo)
                activeRepo = repo
                persistConnectedRepos()
            }

            gitSyncState = result.syncState
            let discovery = try await gitRepositoryService.discoverProjects(
                in: repoURL,
                defaultBranch: repo.branch,
                repoFullName: repo.fullName
            )
            repoProjects = discovery.manifest.projects
            if let updatedProj = repoProjects.first(where: { $0.slug == project.slug }) {
                activeProject = updatedProj
            }
            pendingProjectChanges = (try? await gitRepositoryService.changedFiles(in: repoURL, projectRelativePath: project.relativePath)) ?? []
            await loadProjectCommitHistory()

            if result.committed {
                lastCommitSummary = chosenMsg
                if case .offlinePendingPush = result.syncState {
                    repoStatusMessage = "Saved & committed locally (offline, push pending)."
                } else if case .conflict = result.syncState {
                    repoStatusMessage = "Commit saved locally, but remote changes caused a merge conflict."
                } else {
                    repoStatusMessage = "Committed \"\(chosenMsg)\"."
                }
            } else {
                repoStatusMessage = "No changes to commit in \(project.displayName)."
            }
        } catch {
            gitSyncState = .failed(message: error.localizedDescription)
            repoStatusMessage = error.localizedDescription
        }
    }

    public func prepareCustomCommitPopover() async {
        guard let repo = activeRepo, let project = activeProject else { return }
        do {
            let repoURL = try await gitRepositoryService.localRepositoryURL(for: repo)
            guard let paths = Self.validatedProjectFilePaths(in: repoURL, project: project) else {
                repoStatusMessage = "Refused to stage unsafe or symlinked project path."
                return
            }
            currentFileURL = paths.mainURL
            persistDocumentAndAssets(to: paths.mainURL, bibURL: paths.bibURL)
            pendingProjectChanges = try await gitRepositoryService.changedFiles(in: repoURL, projectRelativePath: project.relativePath)
            commitMessageDraft = GitHubWorkspaceValidator.defaultCommitMessage(projectName: project.displayName)
            commitPushImmediately = repo.autoPushOnSave
            showCommitMessagePopover = true
        } catch {
            repoStatusMessage = error.localizedDescription
        }
    }

    public func syncActiveRepository() async {
        guard var repo = activeRepo else { return }
        gitSyncState = .syncing(status: "Syncing with GitHub...")
        do {
            let repoURL = try await gitRepositoryService.localRepositoryURL(for: repo)
            let token = effectiveStoredToken(for: repo)
            let state = await gitRepositoryService.syncRepository(
                in: repoURL,
                branch: repo.branch,
                token: token,
                authMethod: repo.authMethod
            )
            gitSyncState = state
            if case .idle(_, _, let syncedAt) = state, let syncedAt {
                repo.lastSyncedAt = syncedAt
                upsertConnectedRepo(repo)
                activeRepo = repo
                persistConnectedRepos()
            }
            let discovery = try await gitRepositoryService.discoverProjects(
                in: repoURL,
                defaultBranch: repo.branch,
                repoFullName: repo.fullName
            )
            repoProjects = discovery.manifest.projects
            looseRepoTeXFiles = discovery.looseTeXPaths
            if let currentSlug = activeProject?.slug,
               let refreshedProj = repoProjects.first(where: { $0.slug == currentSlug }) {
                await openProjectFromActiveRepo(refreshedProj)
            }
        } catch {
            gitSyncState = .failed(message: error.localizedDescription)
            repoStatusMessage = error.localizedDescription
        }
    }

    public func loadProjectCommitHistory() async {
        guard let repo = activeRepo, let project = activeProject else {
            projectCommitHistory = []
            return
        }
        do {
            let repoURL = try await gitRepositoryService.localRepositoryURL(for: repo)
            projectCommitHistory = try await gitRepositoryService.projectHistory(
                in: repoURL,
                projectRelativePath: project.relativePath,
                limit: 50
            )
        } catch {
            projectCommitHistory = []
        }
    }

    public func previewFileAtCommit(_ commit: GitCommitRecord, relativeFilePath: String) async -> String? {
        guard let repo = activeRepo else { return nil }
        guard let repoURL = try? await gitRepositoryService.localRepositoryURL(for: repo) else { return nil }
        return try? await gitRepositoryService.fileContentAtCommit(
            in: repoURL,
            commitSHA: commit.id,
            relativeFilePath: relativeFilePath
        )
    }

    public func previewDiffAtCommit(_ commit: GitCommitRecord) async -> String {
        guard let repo = activeRepo, let project = activeProject else { return "" }
        guard let repoURL = try? await gitRepositoryService.localRepositoryURL(for: repo) else { return "" }
        return (try? await gitRepositoryService.commitDiff(
            in: repoURL,
            commitSHA: commit.id,
            projectRelativePath: project.relativePath
        )) ?? ""
    }

    public func restoreProjectToCommit(_ commit: GitCommitRecord) async {
        guard let repo = activeRepo, let project = activeProject else { return }
        gitSyncState = .committing
        do {
            let repoURL = try await gitRepositoryService.localRepositoryURL(for: repo)
            let state = try await gitRepositoryService.restoreProjectToCommit(
                in: repoURL,
                connection: repo,
                project: project,
                commit: commit,
                pushAfterRestore: repo.autoPushOnSave,
                token: nil
            )
            gitSyncState = state
            await openProjectFromActiveRepo(project)
            repoStatusMessage = "Restored '\(project.displayName)' to version \(commit.shortHash)."
        } catch {
            gitSyncState = .failed(message: error.localizedDescription)
            repoStatusMessage = error.localizedDescription
        }
    }

    public func resolveConflictFile(_ relativePath: String, choice: GitConflictResolutionChoice) async {
        await resolveConflicts([relativePath: choice], keepBothCopies: false)
    }

    public func resolveConflictKeepBoth() async {
        guard case .conflict(let files, _) = gitSyncState else { return }
        var map: [String: GitConflictResolutionChoice] = [:]
        for f in files {
            map[f] = .keepLocal
        }
        await resolveConflicts(map, keepBothCopies: true)
    }

    public func resolveConflicts(
        _ choices: [String: GitConflictResolutionChoice],
        keepBothCopies: Bool = false
    ) async {
        guard let repo = activeRepo, let project = activeProject else { return }
        gitSyncState = .syncing(status: "Resolving conflicts...")
        do {
            let repoURL = try await gitRepositoryService.localRepositoryURL(for: repo)
            let state = try await gitRepositoryService.resolveConflict(
                in: repoURL,
                connection: repo,
                project: project,
                choices: choices,
                keepBothCopies: keepBothCopies,
                token: nil
            )
            gitSyncState = state
            await openProjectFromActiveRepo(project)
        } catch {
            gitSyncState = .failed(message: error.localizedDescription)
            repoStatusMessage = error.localizedDescription
        }
    }

    private func restoreActiveRepoOnLaunch(_ repo: GitHubRepoConnection) async {
        do {
            let repoURL = try await gitRepositoryService.localRepositoryURL(for: repo)
            let discovery = try await gitRepositoryService.discoverProjects(
                in: repoURL,
                defaultBranch: repo.branch,
                repoFullName: repo.fullName
            )
            repoProjects = discovery.manifest.projects
            looseRepoTeXFiles = discovery.looseTeXPaths
            gitSyncState = .idle(aheadCount: 0, behindCount: 0, lastSync: repo.lastSyncedAt)
            let preferredID = userDefaults.string(forKey: Self.activeGitHubProjectIDKey).flatMap(UUID.init(uuidString:))
            if let match = repoProjects.first(where: { $0.id == preferredID }) ?? repoProjects.first {
                await openProjectFromActiveRepo(match)
            }
        } catch {
            gitSyncState = .failed(message: error.localizedDescription)
        }
    }

    private func upsertConnectedRepo(_ repo: GitHubRepoConnection) {
        if let idx = connectedRepos.firstIndex(where: { $0.id == repo.id || $0.fullName.caseInsensitiveCompare(repo.fullName) == .orderedSame }) {
            connectedRepos[idx] = repo
        } else {
            connectedRepos.append(repo)
        }
    }

    private func persistConnectedRepos() {
        if let encoded = try? JSONEncoder().encode(connectedRepos) {
            userDefaults.set(encoded, forKey: Self.connectedGitHubReposKey)
        }
        if let activeID = activeRepo?.id.uuidString {
            userDefaults.set(activeID, forKey: Self.activeGitHubRepoIDKey)
        } else {
            userDefaults.removeObject(forKey: Self.activeGitHubRepoIDKey)
        }
    }

    private func effectiveStoredToken(for connection: GitHubRepoConnection) -> String? {
        switch connection.authMethod {
        case .personalAccessToken:
            return gitCredentialStore.loadToken(forAccount: connection.fullName)
                ?? gitCredentialStore.loadToken(forAccount: "github.com")
        case .ghCLI:
            return gitCredentialStore.detectGitHubCLIToken()
                ?? gitCredentialStore.loadToken(forAccount: connection.fullName)
        case .sshKey:
            return nil
        }
    }
}
