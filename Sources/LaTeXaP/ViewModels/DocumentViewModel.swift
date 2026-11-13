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
                outlineItems = OutlineParser.parse(source: sourceText)
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
    @Published public var consoleLog: String = ""
    @Published public var pdfURL: URL?
    @Published public var pdfRevision: Int = 0
    @Published public var synctexData: SyncTeXData?
    @Published public var outlineItems: [DocumentOutlineItem] = []

    @Published public var autoCompileEnabled: Bool = true
    @Published public var showConsoleDrawer: Bool = true
    @Published public var showSidebar: Bool = true
    @Published public var editorFontSize: CGFloat = 13.5
    @Published public var selectedSidebarTab: String = "Outline"
    @Published public var packageSearchText: String = ""
    @Published public var selectedDiagnosticTab: Int = 2

    private let tectonicService = TectonicService()
    private var debounceTask: Task<Void, Never>?

    public init(initialTemplate: LaTeXTemplate = LaTeXCatalog.defaultTemplate) {
        self.sourceText = initialTemplate.content
        self.outlineItems = OutlineParser.parse(source: initialTemplate.content)
        Task {
            await compileNow()
        }
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

        diagnostics = result.diagnostics
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
        let lines = sourceText.components(separatedBy: .newlines)
        let targetIndex = max(0, min(lines.count, cursorLine))
        var updated = lines
        updated.insert(snippet.code, at: targetIndex)
        sourceText = updated.joined(separator: "\n")
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
                let lines = sourceText.components(separatedBy: .newlines)
                let targetIndex = max(0, min(lines.count, cursorLine))
                var updated = lines
                updated.insert(snippet, at: targetIndex)
                sourceText = updated.joined(separator: "\n")
            }
        }
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
