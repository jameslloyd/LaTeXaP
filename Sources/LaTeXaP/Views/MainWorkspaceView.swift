import SwiftUI

enum SidebarTab: String, CaseIterable, Identifiable {
    case outline = "Outline"
    case packages = "Packages"
    case bibliography = "BibTeX"
    case snippets = "LaTeX3"
    case templates = "Templates"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .outline: return "list.bullet.indent"
        case .packages: return "shippingbox"
        case .bibliography: return "books.vertical"
        case .snippets: return "curlybraces.square"
        case .templates: return "doc.on.doc"
        }
    }
}

public struct MainWorkspaceView: View {
    @ObservedObject var viewModel: DocumentViewModel

    public init(viewModel: DocumentViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationSplitView(
            columnVisibility: Binding(
                get: { viewModel.showSidebar ? .all : .detailOnly },
                set: { viewModel.showSidebar = ($0 != .detailOnly) }
            )
        ) {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 230, ideal: 265, max: 340)
        } detail: {
            VStack(spacing: 0) {
                HSplitView {
                    editorPane
                        .frame(minWidth: 360, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity)

                    pdfPreviewPane
                        .frame(minWidth: 360, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                }

                if viewModel.showConsoleDrawer {
                    Divider()
                    DiagnosticsDrawerView(viewModel: viewModel)
                        .frame(minHeight: 140, idealHeight: 190, maxHeight: 300)
                        .transition(.move(edge: .bottom))
                }

                Divider()
                statusBar
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    viewModel.openTexFile()
                } label: {
                    Label("Open .tex", systemImage: "folder")
                }
                .help("Open an existing LaTeX document (⌘O)")

                Button {
                    viewModel.saveTexFile()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .help("Save current .tex source file (⌘S)")
            }

            ToolbarItemGroup(placement: .principal) {
                compilationBadge

                Toggle(isOn: $viewModel.autoCompileEnabled) {
                    Label("Live Render", systemImage: "bolt.fill")
                }
                .toggleStyle(.button)
                .help("Automatically compile PDF as you type")

                Button {
                    Task { await viewModel.compileNow() }
                } label: {
                    Label("Compile", systemImage: "play.fill")
                }
                .keyboardShortcut("b", modifiers: [.command])
                .help("Run Tectonic LaTeX3 compilation now (⌘B)")

                Button {
                    viewModel.triggerForwardSync()
                } label: {
                    Label("Sync PDF", systemImage: "arrow.left.and.right.square")
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                .help("Forward SyncTeX: Jump to PDF location for current editor line (⇧⌘J)")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.showVisualToolsSheet = true
                } label: {
                    Label("Math & Tables", systemImage: "function")
                }
                .help("Open Visual Math Symbol Palette, Matrix Generator & CSV Table Builder")

                Button {
                    viewModel.importFigureViaPanel()
                } label: {
                    Label("Insert Figure", systemImage: "photo.badge.plus")
                }
                .help("Import an image or PDF figure (or drag-and-drop into the editor)")

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.showConsoleDrawer.toggle()
                    }
                } label: {
                    Label("Diagnostics", systemImage: "exclamationmark.triangle")
                }
                .help("Toggle Live Diagnostics & TeX Log Drawer")

                Button {
                    viewModel.exportPDF()
                } label: {
                    Label("Export PDF", systemImage: "arrow.up.doc.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .help("Export compiled PDF document (⇧⌘E)")
            }
        }
        .sheet(isPresented: $viewModel.showVisualToolsSheet) {
            VisualToolsSheetView(viewModel: viewModel)
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            Picker("", selection: $viewModel.selectedSidebarTab) {
                ForEach(SidebarTab.allCases) { tab in
                    Image(systemName: tab.icon)
                        .help(tab.rawValue)
                        .tag(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(10)

            Divider()

            switch SidebarTab(rawValue: viewModel.selectedSidebarTab) ?? .outline {
            case .outline:
                outlineTabView
            case .packages:
                packagesTabView
            case .bibliography:
                bibliographyTabView
            case .snippets:
                snippetsTabView
            case .templates:
                templatesTabView
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var outlineTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DOCUMENT & EXPL3 STRUCTURE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            if viewModel.outlineItems.isEmpty {
                ContentUnavailableView(
                    "No Sections or Macros",
                    systemImage: "list.bullet.indent",
                    description: Text("Add \\section{...} or \\NewDocumentCommand to populate the outline.")
                )
            } else {
                List(viewModel.outlineItems) { item in
                    Button {
                        viewModel.jumpToLineRequest = item.line
                        viewModel.cursorLine = item.line
                        viewModel.triggerForwardSync()
                    } label: {
                        HStack(spacing: 8) {
                            Text(item.badge)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(badgeColor(for: item.badge).opacity(0.16))
                                .foregroundStyle(badgeColor(for: item.badge))
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            Text(item.title)
                                .font(.system(size: 12.5, weight: item.level == 1 ? .semibold : .regular))
                                .lineLimit(1)

                            Spacer()

                            Text("L\(item.line)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.leading, CGFloat(max(0, item.level - 1) * 10))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var packagesTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter CTAN packages...", text: $viewModel.packageSearchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(10)

            Text("Tectonic automatically downloads any CTAN package on first use.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            let filtered = LaTeXCatalog.commonPackages.filter {
                viewModel.packageSearchText.isEmpty ||
                $0.package.localizedCaseInsensitiveContains(viewModel.packageSearchText) ||
                $0.description.localizedCaseInsensitiveContains(viewModel.packageSearchText) ||
                $0.category.localizedCaseInsensitiveContains(viewModel.packageSearchText)
            }

            List(filtered) { pkg in
                let isIncluded = viewModel.sourceText.contains("{\(pkg.package)}")
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(pkg.package)
                            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        Text(pkg.category)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                        Spacer()
                        Button {
                            viewModel.insertPackage(pkg)
                        } label: {
                            Label(isIncluded ? "Added" : "Insert", systemImage: isIncluded ? "checkmark.circle.fill" : "plus.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isIncluded)
                    }
                    Text(pkg.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
            .listStyle(.plain)
        }
    }

    private var bibliographyTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("FETCH BY DOI OR ARXIV ID")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    TextField("e.g. 10.1145/... or 2305.12345", text: $viewModel.bibLookupQuery)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            viewModel.fetchAndAppendBibEntry()
                        }

                    Button {
                        viewModel.fetchAndAppendBibEntry()
                    } label: {
                        if viewModel.isFetchingBib {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down.doc.fill")
                        }
                    }
                    .disabled(viewModel.bibLookupQuery.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isFetchingBib)
                    .help("Fetch BibTeX entry from DOI or arXiv and append to bibliography")
                }

                if let err = viewModel.bibLookupError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .padding(10)

            Divider()

            Text("CITATIONS (\(viewModel.bibEntries.count)) & LABELS (\(viewModel.documentLabels.count))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            List {
                if !viewModel.bibEntries.isEmpty {
                    Section("Bibliography Keys (\\cite{...})") {
                        ForEach(viewModel.bibEntries) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(entry.key)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.pink)
                                    if !entry.year.isEmpty {
                                        Text(entry.year)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Cite") {
                                        viewModel.insertInlineText("\\cite{\(entry.key)}")
                                    }
                                    .controlSize(.mini)
                                }
                                Text(entry.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !viewModel.documentLabels.isEmpty {
                    Section("Cross-Reference Labels (\\ref{...})") {
                        ForEach(viewModel.documentLabels) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.label)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.cyan)
                                    Text("Line \(item.line) • \(item.contextPreview)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("\\ref") {
                                    viewModel.insertInlineText("\\ref{\(item.label)}")
                                }
                                .controlSize(.mini)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var snippetsTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LATEX3 (EXPL3 & XPARSE) SNIPPETS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            List(LaTeXCatalog.snippets) { snippet in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(snippet.title)
                            .font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        Button("Insert") {
                            viewModel.insertSnippet(snippet)
                        }
                        .controlSize(.small)
                    }
                    Text(snippet.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(snippet.code)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(3)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
        }
    }

    private var templatesTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("STARTER TEMPLATES")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            List(LaTeXCatalog.templates) { template in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: template.icon)
                            .foregroundStyle(Color.accentColor)
                        Text(template.name)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    Text(template.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Load Template") {
                        viewModel.loadTemplate(template)
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 5)
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Editor & PDF Panes

    private var editorPane: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(.secondary)
                Text(viewModel.currentFileURL?.lastPathComponent ?? "Untitled.tex")
                    .font(.system(size: 12, weight: .semibold))
                Text("• LaTeX3 / expl3")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Line \(viewModel.cursorLine)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            LaTeXCodeEditorView(
                text: $viewModel.sourceText,
                cursorLine: $viewModel.cursorLine,
                jumpToLineRequest: $viewModel.jumpToLineRequest,
                diagnostics: viewModel.diagnostics,
                fontSize: viewModel.editorFontSize,
                onDropImageFile: { droppedURL in
                    viewModel.handleDroppedImageURL(droppedURL)
                }
            )
        }
    }

    private var pdfPreviewPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.richtext")
                    .foregroundStyle(.secondary)
                Text("Live PDF Preview")
                    .font(.system(size: 12, weight: .semibold))

                Text("(⌘-Click in PDF to jump to source line)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    viewModel.pdfZoomScale = max(0.5, viewModel.pdfZoomScale - 0.15)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Zoom Out")

                Button {
                    viewModel.pdfZoomScale = min(3.0, viewModel.pdfZoomScale + 0.15)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Zoom In")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ZStack {
                PDFPreviewContainer(
                    pdfURL: viewModel.pdfURL,
                    pdfRevision: viewModel.pdfRevision,
                    forwardSyncBox: $viewModel.forwardSyncBox,
                    zoomScale: $viewModel.pdfZoomScale,
                    onBackwardSync: { page, xPt, yTopPt in
                        viewModel.handleBackwardSync(page: page, xPt: xPt, yTopPt: yTopPt)
                    }
                )

                if viewModel.pdfURL == nil {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Compiling LaTeX3 document with Tectonic...")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - Badges & Status Bar

    @ViewBuilder
    private var compilationBadge: some View {
        switch viewModel.compilationState {
        case .idle:
            Label("Ready", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .compiling:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Rendering...")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(Capsule())
        case .success(let durationMs, let pageCount):
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("PDF Ready (\(pageCount)p • \(durationMs) ms)")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.12))
            .clipShape(Capsule())
        case .failed(let errorCount):
            Button {
                viewModel.showConsoleDrawer = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text("\(errorCount) Error\(errorCount == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.14))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var statusBar: some View {
        let errorCount = viewModel.diagnostics.filter { $0.severity == .error }.count
        let warningCount = viewModel.diagnostics.filter { $0.severity == .warning }.count

        return HStack(spacing: 16) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.showConsoleDrawer.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Label("\(errorCount)", systemImage: "xmark.circle.fill")
                        .foregroundStyle(errorCount > 0 ? .red : .secondary)
                    Label("\(warningCount)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(warningCount > 0 ? .orange : .secondary)
                }
                .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.plain)

            if let firstError = viewModel.diagnostics.first(where: { $0.severity == .error }) {
                Text(firstError.message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 12) {
                Text("\(viewModel.documentStats.wordCount) words")
                Text("•")
                Text("\(viewModel.documentStats.mathCount) math")
                Text("•")
                Text("\(viewModel.documentStats.expl3SymbolCount) expl3")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)

            Text("|")
                .foregroundStyle(.quaternary)

            Text("Engine: Tectonic (XeTeX + LaTeX3 + SyncTeX)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func badgeColor(for badge: String) -> Color {
        switch badge {
        case "expl3": return .purple
        case "xparse": return .indigo
        case "env": return .teal
        default: return .blue
        }
    }
}

public struct DiagnosticsDrawerView: View {
    @ObservedObject var viewModel: DocumentViewModel

    public var body: some View {
        let contextAnalysis = ContextSuggestionsEngine.analyze(
            source: viewModel.sourceText,
            cursorLine: viewModel.cursorLine,
            diagnostics: viewModel.diagnostics
        )

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("", selection: $viewModel.selectedDiagnosticTab) {
                    Text("Diagnostics (\(viewModel.diagnostics.count))").tag(0)
                    Text("Full TeX Transcript").tag(1)
                    Text("Context Suggestions (\(contextAnalysis.items.count))").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 480)

                if viewModel.selectedDiagnosticTab == 2 {
                    Label(contextAnalysis.contextBadge, systemImage: "sparkles")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                Button {
                    viewModel.showConsoleDrawer = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if viewModel.selectedDiagnosticTab == 0 {
                if viewModel.diagnostics.isEmpty {
                    HStack {
                        Spacer()
                        Label("No errors or warnings reported by Tectonic.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.secondary)
                            .padding()
                        Spacer()
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List(viewModel.diagnostics) { diag in
                        Button {
                            if let line = diag.line {
                                viewModel.jumpToLineRequest = line
                            }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: iconName(for: diag.severity))
                                    .foregroundStyle(color(for: diag.severity))

                                if let line = diag.line {
                                    Text("Line \(line)")
                                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                        .frame(width: 64, alignment: .leading)
                                } else {
                                    Text("Global")
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 64, alignment: .leading)
                                }

                                Text(diag.message)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)

                                Spacer()
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            } else if viewModel.selectedDiagnosticTab == 1 {
                ScrollView {
                    Text(viewModel.consoleLog.isEmpty ? "No transcript output yet." : viewModel.consoleLog)
                        .font(.system(size: 11.5, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .textSelection(.enabled)
                }
                .background(Color(NSColor.textBackgroundColor))
            } else {
                List(contextAnalysis.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(item.title)
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(item.category)
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.14))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(Capsule())
                            }

                            Text(item.explanation)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        if let actionLabel = item.actionLabel {
                            Button(actionLabel) {
                                viewModel.applyContextAdvice(item)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
    }

    private func iconName(for severity: DiagnosticSeverity) -> String {
        switch severity {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func color(for severity: DiagnosticSeverity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}
