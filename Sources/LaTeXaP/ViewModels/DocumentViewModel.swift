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
    @Published public var editorFontSize: CGFloat = 13.5
    @Published public var selectedSidebarTab: String = "Outline"
    @Published public var packageSearchText: String = ""
    @Published public var selectedDiagnosticTab: Int = 2

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

    private let tectonicService = TectonicService()
    private var debounceTask: Task<Void, Never>?
    private var lastCompilerDiagnostics: [LaTeXDiagnostic] = []

    public init(initialTemplate: LaTeXTemplate = LaTeXCatalog.defaultTemplate) {
        self.sourceText = initialTemplate.content
        refreshDerivedMetadata()
        Task {
            await compileNow()
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

        let result = await tectonicService.compile(source: codeSnapshot, documentDirectory: docDir)

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
}
