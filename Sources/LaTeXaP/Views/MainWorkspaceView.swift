import SwiftUI
import UniformTypeIdentifiers

enum SidebarTab: String, CaseIterable, Identifiable {
    case outline = "Outline"
    case packages = "Packages"
    case fonts = "Fonts"
    case bibliography = "BibTeX"
    case snippets = "LaTeX3"
    case templates = "Templates"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .outline: return "list.bullet.indent"
        case .packages: return "shippingbox"
        case .fonts: return "textformat"
        case .bibliography: return "books.vertical"
        case .snippets: return "curlybraces.square"
        case .templates: return "doc.on.doc"
        }
    }
}

@MainActor
private final class MainWorkspaceUIState: ObservableObject {
    @Published var showEditorFontPopover: Bool = false
    @Published var isSidebarFontDropTargeted: Bool = false
    @Published var showPaperBudgetPopover: Bool = false
    @Published var showSubmissionPreExportAlert: Bool = false
    @Published var wizardInitialTemplateId: String? = nil
    @Published var bibLibraryFilter: String = ""
    @Published var bibPageLocator: String = ""
    @Published var isBibDropTargeted: Bool = false
    @Published var expandedRawDiagnosticIDs: Set<String> = []
    @Published var pendingProjectToSwitch: AcademicProjectDescriptor? = nil
    @Published var showDirtySwitchAlert: Bool = false
    @Published var projectPendingDeletion: AcademicProjectDescriptor? = nil
    @Published var showDeleteProjectConfirm: Bool = false
}

public struct MainWorkspaceView: View {
    @ObservedObject var viewModel: DocumentViewModel
    @StateObject private var uiState = MainWorkspaceUIState()
    @FocusState private var isFontsToolbarFocused: Bool
    @FocusState private var isVisualToolsToolbarFocused: Bool
    @FocusState private var isCiteToolbarFocused: Bool
    @FocusState private var isFigureToolbarFocused: Bool
    @FocusState private var isBudgetPillFocused: Bool
    @FocusState private var isWizardButtonFocused: Bool
    @FocusState private var isBibLookupFieldFocused: Bool
    @FocusState private var isCommitToolbarFocused: Bool
    @FocusState private var isRepoSidebarFocused: Bool
    @FocusState private var isHistoryTriggerFocused: Bool

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
                if viewModel.isInGitConflictState {
                    gitConflictBanner
                    Divider()
                }

                if let exportMessage = viewModel.submissionExportMessage {
                    submissionExportBanner(message: exportMessage)
                    Divider()
                }

                HSplitView {
                    editorPane
                        .frame(minWidth: 360, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity)

                    pdfPreviewPane
                        .frame(minWidth: 360, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                }

                if viewModel.showConsoleDrawer {
                    Divider()
                    DiagnosticsDrawerView(viewModel: viewModel)
                        .frame(minHeight: 140, idealHeight: 195, maxHeight: 320)
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
                    viewModel.saveDocument()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .help(
                    viewModel.activeRepo != nil && viewModel.activeProject != nil
                        ? "Save & Commit current project to GitHub (⌘S)"
                        : "Save current .tex source file (⌘S)"
                )

                if viewModel.activeRepo != nil, viewModel.activeProject != nil {
                    Button {
                        Task { await viewModel.prepareCustomCommitPopover() }
                    } label: {
                        Label("Commit...", systemImage: "arrow.triangle.branch")
                    }
                    .focused($isCommitToolbarFocused)
                    .popover(isPresented: $viewModel.showCommitMessagePopover, arrowEdge: .bottom) {
                        CommitSavePopoverView(viewModel: viewModel)
                    }
                    .help("Save & Commit with a custom commit message (⌥⌘S)")
                    .accessibilityLabel("Commit with message")
                    .accessibilityHint("Opens popover to enter a commit message and choose whether to push to GitHub")

                    Button {
                        Task { await viewModel.syncActiveRepository() }
                    } label: {
                        if viewModel.gitSyncState.isBusy {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.small)
                                Text("Syncing")
                            }
                        } else {
                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(viewModel.gitSyncState.isBusy)
                    .help("Pull remote updates and push local commits to GitHub")
                    .accessibilityLabel("Sync with GitHub")
                }
            }

            ToolbarItemGroup(placement: .principal) {
                compilationBadge

                autoCompileToolbarButton

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
                if let update = viewModel.availableUpdate {
                    Button {
                        NSWorkspace.shared.open(update.htmlURL)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Update v\(update.latestVersion)")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.14))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("LaTeXaP \(update.tagName) is available on GitHub — click to view release")
                }

                Button {
                    viewModel.showVisualToolsSheet = true
                } label: {
                    Label("Math & Tables", systemImage: "function")
                }
                .focused($isVisualToolsToolbarFocused)
                .help("Open Visual Math Palette, Matrix Builder, Table Editor & Chart Builder")

                Button {
                    viewModel.showCitationPickerPopover.toggle()
                } label: {
                    Label("Cite", systemImage: "quote.bubble")
                }
                .focused($isCiteToolbarFocused)
                .popover(isPresented: $viewModel.showCitationPickerPopover, arrowEdge: .bottom) {
                    CitationPickerPopoverView(viewModel: viewModel)
                }
                .help("Open Quick Citation Picker (⇧⌘K)")
                .accessibilityLabel("Cite")
                .accessibilityHint("Opens the Quick Citation Picker popover")

                Button {
                    viewModel.showFontManagerSheet = true
                } label: {
                    Label("Fonts", systemImage: "textformat")
                }
                .focused($isFontsToolbarFocused)
                .help("Open Font Manager to add, preview, and apply custom or system fonts (⇧⌘F)")
                .accessibilityLabel("Fonts")
                .accessibilityHint("Opens the Font Manager sheet")

                Button {
                    viewModel.pendingDroppedFigureURL = nil
                    viewModel.showFigureAssistantSheet = true
                } label: {
                    Label("Insert Figure", systemImage: "photo.badge.plus")
                }
                .focused($isFigureToolbarFocused)
                .help("Open Figure Assistant to insert single or side-by-side figures (or drag-and-drop into the editor)")
                .accessibilityLabel("Insert Figure")
                .accessibilityHint("Opens the Figure Assistant sheet")

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.showConsoleDrawer.toggle()
                    }
                } label: {
                    Label("Diagnostics", systemImage: "exclamationmark.triangle")
                }
                .help("Toggle Live Diagnostics, Pre-Flight & TeX Log Drawer")

                Menu {
                    Button {
                        viewModel.exportPDF()
                    } label: {
                        Label("Export PDF...", systemImage: "doc.richtext")
                    }
                    .keyboardShortcut("e", modifiers: [.command, .shift])

                    Button {
                        triggerSubmissionExportFlow()
                    } label: {
                        Label("Export Submission Bundle (.zip)...", systemImage: "archivebox")
                    }
                    .keyboardShortcut("e", modifiers: [.command, .shift, .option])
                } label: {
                    if viewModel.isExportingSubmissionBundle {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.small)
                            Text("Exporting...")
                        }
                    } else {
                        Label("Export", systemImage: "arrow.up.doc.fill")
                    }
                } primaryAction: {
                    viewModel.exportPDF()
                }
                .help("Export PDF (⇧⌘E) or Submission Bundle .zip (⌥⇧⌘E)")
                .accessibilityLabel("Export")
                .accessibilityHint("Exports PDF or packages a clean submission zip bundle")
            }
        }
        .sheet(isPresented: $viewModel.showVisualToolsSheet, onDismiss: {
            isVisualToolsToolbarFocused = true
        }) {
            VisualToolsSheetView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showFontManagerSheet, onDismiss: {
            isFontsToolbarFocused = true
        }) {
            FontManagerView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showPaperWizardSheet, onDismiss: {
            uiState.wizardInitialTemplateId = nil
            isWizardButtonFocused = true
        }) {
            PaperWizardSheetView(viewModel: viewModel, initialTemplateId: uiState.wizardInitialTemplateId)
        }
        .sheet(isPresented: $viewModel.showFigureAssistantSheet, onDismiss: {
            viewModel.pendingDroppedFigureURL = nil
            isFigureToolbarFocused = true
        }) {
            FigureAssistantSheetView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showRepoSetupSheet, onDismiss: {
            isRepoSidebarFocused = true
        }) {
            GitHubWorkspaceSetupSheetView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showNewRepoProjectSheet, onDismiss: {
            isRepoSidebarFocused = true
        }) {
            NewRepoProjectSheetView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showProjectHistorySheet, onDismiss: {
            isHistoryTriggerFocused = true
        }) {
            ProjectHistorySheetView(viewModel: viewModel)
        }
        .alert("Unsaved Changes in Current Project", isPresented: $uiState.showDirtySwitchAlert, presenting: uiState.pendingProjectToSwitch) { nextProject in
            Button("Save & Commit, Then Switch") {
                uiState.pendingProjectToSwitch = nil
                Task {
                    await viewModel.saveAndCommitCurrentProject()
                    await viewModel.openProjectFromActiveRepo(nextProject)
                }
            }
            Button("Discard Edits & Switch", role: .destructive) {
                uiState.pendingProjectToSwitch = nil
                Task {
                    await viewModel.discardUnsavedProjectEdits()
                    await viewModel.openProjectFromActiveRepo(nextProject)
                }
            }
            Button("Cancel", role: .cancel) {
                uiState.pendingProjectToSwitch = nil
            }
        } message: { nextProject in
            let currentName = viewModel.activeProject?.displayName ?? "current project"
            Text("'\(currentName)' has uncommitted edits. Save & commit before opening '\(nextProject.displayName)'?")
        }
        .alert("Delete Project from Repository?", isPresented: $uiState.showDeleteProjectConfirm, presenting: uiState.projectPendingDeletion) { project in
            Button("Delete '\(project.displayName)'", role: .destructive) {
                uiState.projectPendingDeletion = nil
                Task { await viewModel.deleteProjectFromActiveRepo(project) }
            }
            Button("Cancel", role: .cancel) {
                uiState.projectPendingDeletion = nil
            }
        } message: { project in
            Text("This removes '\(project.relativePath)' from the repository and commits the deletion (earlier commits remain recoverable in Git history).")
        }
        .alert("Pre-Flight Checks Found Issues", isPresented: $uiState.showSubmissionPreExportAlert) {
            Button("Review Pre-Flight") {
                viewModel.selectedDiagnosticTab = 1
                viewModel.showConsoleDrawer = true
            }
            Button("Export Anyway") {
                viewModel.exportSubmissionBundle(stripComments: false, anonymize: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let blockers = viewModel.preflightReport.items.filter { $0.severity == .blocker }.count
            let warnings = viewModel.preflightReport.items.filter { $0.severity == .warning }.count
            Text("Pre-Flight detected \(blockers) blocker(s) and \(warnings) warning(s) that could cause grading or compilation failures. Review Pre-Flight before packaging or export anyway?")
        }
        .onChange(of: viewModel.showCitationPickerPopover) { _, isShown in
            if !isShown {
                isCiteToolbarFocused = true
            }
        }
        .onChange(of: viewModel.showCommitMessagePopover) { _, isShown in
            if !isShown {
                isCommitToolbarFocused = true
            }
        }
        .onChange(of: viewModel.repoStatusMessage) { _, message in
            if let message, !message.isEmpty {
                NSAccessibility.post(
                    element: NSApp as Any,
                    notification: .announcementRequested,
                    userInfo: [.announcement: message]
                )
            }
        }
        .onChange(of: uiState.showPaperBudgetPopover) { _, isShown in
            if !isShown {
                isBudgetPillFocused = true
            }
        }
        .onChange(of: viewModel.submissionExportMessage) { _, newMessage in
            if let newMessage, !newMessage.isEmpty {
                NSAccessibility.post(
                    element: NSApp as Any,
                    notification: .announcementRequested,
                    userInfo: [.announcement: newMessage]
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .latexapRequestSubmissionExport)) { _ in
            triggerSubmissionExportFlow()
        }
    }

    private func triggerSubmissionExportFlow() {
        let issues = viewModel.preflightReport.items.filter { $0.severity != .pass }
        if !viewModel.preflightReport.isSubmissionReady || !issues.isEmpty {
            uiState.showSubmissionPreExportAlert = true
        } else {
            viewModel.exportSubmissionBundle(stripComments: false, anonymize: false)
        }
    }

    @ViewBuilder
    private func submissionExportBanner(message: String) -> some View {
        let isError = message.localizedCaseInsensitiveContains("failed") || message.localizedCaseInsensitiveContains("error")
        HStack(spacing: 8) {
            Image(systemName: isError ? "xmark.octagon.fill" : "checkmark.seal.fill")
                .foregroundStyle(isError ? .red : .green)
            Text(message)
                .font(.caption.weight(.medium))
                .lineLimit(2)
            Spacer()
            if !isError, let zipURL = viewModel.lastExportedZipURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([zipURL])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .controlSize(.small)
                .accessibilityLabel("Reveal submission zip in Finder")
            }
            if isError {
                Button("Review Pre-Flight") {
                    viewModel.selectedDiagnosticTab = 1
                    viewModel.showConsoleDrawer = true
                }
                .controlSize(.small)
            }
            Button("Dismiss") {
                viewModel.submissionExportMessage = nil
                viewModel.lastExportedZipURL = nil
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isError ? Color.red.opacity(0.10) : Color.green.opacity(0.10))
        .accessibilityElement(children: .contain)
    }

    private var gitConflictBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Merge conflict detected in \(viewModel.activeProject?.displayName ?? "active project"). Compilation is paused until conflicts are resolved.")
                .font(.caption.weight(.medium))
                .lineLimit(2)
            Spacer()
            Button("Resolve Conflicts...") {
                viewModel.showProjectHistorySheet = true
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Resolve merge conflicts")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.14))
        .accessibilityElement(children: .contain)
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            githubWorkspaceHeaderStrip

            Divider()

            Picker("", selection: $viewModel.selectedSidebarTab) {
                ForEach(SidebarTab.allCases) { tab in
                    Image(systemName: tab.icon)
                        .help(tab.rawValue)
                        .accessibilityLabel(tab.rawValue)
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
            case .fonts:
                fontsTabView
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

    private var fontsTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("FONTS & TYPOGRAPHY")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button {
                        viewModel.openImportFontPanel()
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.caption)
                    }
                    .controlSize(.mini)
                    .accessibilityLabel("Add custom font files")
                }

                Button {
                    viewModel.showFontManagerSheet = true
                } label: {
                    Label("Manage & Add Fonts...", systemImage: "textformat")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityHint("Opens the Font Manager sheet (Shift-Command-F)")

                if viewModel.isImportingFont {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Importing font...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let err = viewModel.fontErrorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                        Text(err)
                            .font(.caption2)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            viewModel.clearFontFeedback()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(6)
                    .background(Color.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if let success = viewModel.fontSuccessMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(success)
                            .font(.caption2)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            viewModel.clearFontFeedback()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(6)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(10)

            Divider()

            List {
                Section("Editor Typography") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.editorFontName.isEmpty ? "System Monospaced" : viewModel.editorFontName)
                                .font(.system(size: 12, weight: .semibold))
                            Text("\(String(format: "%.1f", viewModel.editorFontSize)) pt")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Change") {
                            uiState.showEditorFontPopover = true
                        }
                        .controlSize(.mini)
                    }
                    .padding(.vertical, 2)
                }

                Section("Custom Fonts (\(viewModel.customFonts.count))") {
                    if viewModel.customFonts.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Drop .ttf, .otf, or .ttc files here", systemImage: "doc.badge.plus")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(uiState.isSidebarFontDropTargeted ? Color.accentColor : Color.secondary)
                            Text("Or click Add to import fonts for XeTeX (fontspec) and the editor.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    uiState.isSidebarFontDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                                    style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                                )
                        )
                        .onDrop(of: [.fileURL], isTargeted: $uiState.isSidebarFontDropTargeted, perform: handleSidebarFontDrop(providers:))
                    } else {
                        ForEach(viewModel.customFonts) { font in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(font.displayName)
                                        .font(Font(LaTeXSyntaxHighlighter.resolveFont(name: font.postScriptName, size: 12.5, weight: .regular)))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(font.format.displayBadge)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.14))
                                        .foregroundStyle(Color.accentColor)
                                        .clipShape(Capsule())
                                }
                                HStack(spacing: 6) {
                                    Button("Main") {
                                        viewModel.applyCustomFontToDocument(font, role: .main)
                                    }
                                    .controlSize(.mini)
                                    Button("Sans") {
                                        viewModel.applyCustomFontToDocument(font, role: .sans)
                                    }
                                    .controlSize(.mini)
                                    Button("Mono") {
                                        viewModel.applyCustomFontToDocument(font, role: .mono)
                                    }
                                    .controlSize(.mini)
                                    if font.isMonospace {
                                        Button("Editor") {
                                            viewModel.selectEditorFont(font.postScriptName)
                                        }
                                        .controlSize(.mini)
                                    }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                Section("CTAN Font Packages") {
                    ForEach(LaTeXCatalog.ctanFontPresets) { preset in
                        let isIncluded = viewModel.sourceText.contains("{\(preset.packageName)}")
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(preset.classification)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(isIncluded ? "Added" : "Insert") {
                                viewModel.applyCTANFontPreset(preset)
                            }
                            .controlSize(.mini)
                            .disabled(isIncluded)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .listStyle(.plain)
            .onDrop(of: [.fileURL], isTargeted: $uiState.isSidebarFontDropTargeted, perform: handleSidebarFontDrop(providers:))
        }
    }

    private func handleSidebarFontDrop(providers: [NSItemProvider]) -> Bool {
        let lock = NSLock()
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   url.isFileURL {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                } else if let url = item as? URL, url.isFileURL {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty {
                viewModel.importCustomFonts(urls: urls)
            }
        }
        return true
    }

    private var bibliographyTabView: some View {
        let filterText = uiState.bibLibraryFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredEntries = viewModel.bibEntries.filter { entry in
            filterText.isEmpty ||
            entry.key.localizedCaseInsensitiveContains(filterText) ||
            entry.title.localizedCaseInsensitiveContains(filterText) ||
            entry.author.localizedCaseInsensitiveContains(filterText) ||
            entry.year.localizedCaseInsensitiveContains(filterText)
        }
        let filteredLabels = viewModel.documentLabels.filter { item in
            filterText.isEmpty ||
            item.label.localizedCaseInsensitiveContains(filterText) ||
            item.contextPreview.localizedCaseInsensitiveContains(filterText)
        }
        let uncitedKeys = Set(viewModel.preflightReport.uncitedBibKeys)
        let locator: String? = {
            let trimmed = uiState.bibPageLocator.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Picker(
                        "Style",
                        selection: Binding(
                            get: { viewModel.selectedBibliographyStyle },
                            set: { viewModel.applyBibliographyStyle($0) }
                        )
                    ) {
                        ForEach(BibliographyStylePreset.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityLabel("Bibliography formatting style")

                    Spacer()

                    Button {
                        viewModel.importBibFileViaPanel()
                    } label: {
                        Label("Import .bib", systemImage: "doc.badge.plus")
                            .font(.caption)
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Import BibTeX file")
                    .accessibilityHint("Choose a .bib file to merge into your bibliography")
                }

                Text("SMART CITATION LOOKUP")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: 6) {
                    TextField("DOI, arXiv ID, ISBN, or Paper Title...", text: $viewModel.bibLookupQuery)
                        .textFieldStyle(.roundedBorder)
                        .focused($isBibLookupFieldFocused)
                        .onSubmit {
                            viewModel.searchCrossRefCitations()
                        }
                        .accessibilityLabel("Citation lookup query")
                        .accessibilityHint("Enter a DOI, arXiv ID, ISBN, or paper title and press Return")

                    Button {
                        viewModel.searchCrossRefCitations()
                    } label: {
                        if viewModel.isSearchingCrossRef || viewModel.isFetchingBib {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    .disabled(
                        viewModel.bibLookupQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        viewModel.isSearchingCrossRef ||
                        viewModel.isFetchingBib
                    )
                    .help("Search CrossRef, arXiv, or ISBN and fetch BibTeX metadata")
                    .accessibilityLabel("Search citations")
                }

                if let err = viewModel.bibLookupError {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button {
                            viewModel.bibLookupError = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss citation error")
                    }
                    .padding(6)
                    .background(Color.red.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                if !viewModel.bibSearchResults.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("LOOKUP MATCHES (\(viewModel.bibSearchResults.count))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear") {
                                viewModel.bibSearchResults = []
                            }
                            .font(.caption2)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }

                        ForEach(Array(viewModel.bibSearchResults.prefix(5))) { match in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(match.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(2)
                                Text([match.author, match.year, match.venue].filter { !$0.isEmpty }.joined(separator: " • "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Button("+ Add") {
                                        viewModel.importBibEntry(match, intoBibFile: true)
                                    }
                                    .controlSize(.mini)

                                    Button("+ Cite") {
                                        viewModel.importBibEntry(match, intoBibFile: true)
                                        viewModel.insertFormattedCitation(
                                            match,
                                            style: viewModel.selectedCitationStyle,
                                            pageLocator: locator
                                        )
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.mini)
                                    Spacer()
                                }
                            }
                            .padding(6)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            .padding(10)

            Divider()

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Filter saved citations & labels...", text: $uiState.bibLibraryFilter)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .accessibilityLabel("Filter saved citations and labels")
                    if !uiState.bibLibraryFilter.isEmpty {
                        Button {
                            uiState.bibLibraryFilter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear filter")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 6) {
                    Text("Locator:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("e.g. p. 12", text: $uiState.bibPageLocator)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.mini)
                        .accessibilityLabel("Optional citation page locator")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            if viewModel.bibEntries.isEmpty && viewModel.documentLabels.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("No Citations Yet", systemImage: "books.vertical")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(uiState.isBibDropTargeted ? Color.accentColor : Color.primary)
                    Text("Drop a .bib file from Zotero/Scholar here, click Import .bib, or search by DOI, arXiv, or title above.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            uiState.isBibDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                        )
                )
                .padding(10)
                Spacer()
            } else {
                List {
                    if !filteredEntries.isEmpty {
                        Section("Bibliography Entries (\(filteredEntries.count))") {
                            ForEach(filteredEntries) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(entry.key)
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(.pink)
                                        if !entry.year.isEmpty {
                                            Text(entry.year)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        if uncitedKeys.contains(entry.key) {
                                            Label("Uncited", systemImage: "exclamationmark.circle.fill")
                                                .font(.system(size: 9.5, weight: .semibold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.orange.opacity(0.16))
                                                .foregroundStyle(.orange)
                                                .clipShape(Capsule())
                                        }
                                        Spacer()
                                    }
                                    Text(entry.title)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(2)
                                    if !entry.author.isEmpty {
                                        Text(entry.author)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    HStack(spacing: 5) {
                                        Button("\\cite") {
                                            viewModel.insertFormattedCitation(entry, style: .cite, pageLocator: locator)
                                        }
                                        .controlSize(.mini)
                                        .accessibilityLabel("Insert cite command for \(entry.key)")

                                        Button("\\parencite") {
                                            viewModel.insertFormattedCitation(entry, style: .parencite, pageLocator: locator)
                                        }
                                        .controlSize(.mini)
                                        .accessibilityLabel("Insert parencite command for \(entry.key)")

                                        Button("\\textcite") {
                                            viewModel.insertFormattedCitation(entry, style: .textcite, pageLocator: locator)
                                        }
                                        .controlSize(.mini)
                                        .accessibilityLabel("Insert textcite command for \(entry.key)")
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }

                    if !filteredLabels.isEmpty {
                        Section("Cross-Reference Labels (\(filteredLabels.count))") {
                            ForEach(filteredLabels) { item in
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
                                    HStack(spacing: 4) {
                                        Button("\\ref") {
                                            viewModel.insertTextAtCaret("\\ref{\(item.label)}")
                                        }
                                        .controlSize(.mini)
                                        .accessibilityLabel("Insert ref to \(item.label)")

                                        Button("\\cref") {
                                            viewModel.insertTextAtCaret("\\cref{\(item.label)}")
                                        }
                                        .controlSize(.mini)
                                        .accessibilityLabel("Insert cleveref cref to \(item.label)")
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $uiState.isBibDropTargeted, perform: handleSidebarBibDrop(providers:))
        .onChange(of: viewModel.bibSearchResults) { _, results in
            if !results.isEmpty {
                NSAccessibility.post(
                    element: NSApp as Any,
                    notification: .announcementRequested,
                    userInfo: [.announcement: "\(results.count) citation lookup results found"]
                )
            }
        }
        .onChange(of: viewModel.bibLookupError) { _, error in
            if let error, !error.isEmpty {
                NSAccessibility.post(
                    element: NSApp as Any,
                    notification: .announcementRequested,
                    userInfo: [.announcement: "Citation lookup failed: \(error)"]
                )
            }
        }
    }

    private func handleSidebarBibDrop(providers: [NSItemProvider]) -> Bool {
        let lock = NSLock()
        var droppedBibURL: URL?
        let group = DispatchGroup()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let resolvedURL: URL?
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   url.isFileURL {
                    resolvedURL = url
                } else if let url = item as? URL, url.isFileURL {
                    resolvedURL = url
                } else {
                    resolvedURL = nil
                }

                if let url = resolvedURL, url.pathExtension.lowercased() == "bib" {
                    lock.lock()
                    if droppedBibURL == nil {
                        droppedBibURL = url
                    }
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            if let url = droppedBibURL {
                viewModel.handleDroppedBibFileURL(url)
            }
        }
        return true
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
        let orderedCategories = ["Academic Papers", "STEM & Theses", "LaTeX3 Core"]
        let extraCategories = Array(Set(LaTeXCatalog.templates.map(\.category)))
            .filter { !orderedCategories.contains($0) }
            .sorted()
        let categories = orderedCategories + extraCategories

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ACADEMIC & LATEX3 TEMPLATES")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                Button {
                    uiState.wizardInitialTemplateId = nil
                    viewModel.showPaperWizardSheet = true
                } label: {
                    Label("New with Setup Wizard...", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .focused($isWizardButtonFocused)
                .accessibilityLabel("New with Setup Wizard")
                .accessibilityHint("Opens the Academic Paper Setup Wizard (Shift-Command-N)")
            }
            .padding(10)

            Divider()

            List {
                ForEach(categories, id: \.self) { category in
                    let items = LaTeXCatalog.templates.filter { $0.category == category }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { template in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: template.icon)
                                            .foregroundStyle(Color.accentColor)
                                        Text(template.name)
                                            .font(.system(size: 12.5, weight: .semibold))
                                        Spacer()
                                    }
                                    Text(template.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    HStack(spacing: 6) {
                                        Button("Load Starter") {
                                            viewModel.loadTemplate(template)
                                        }
                                        .controlSize(.mini)

                                        Button("Customize...") {
                                            uiState.wizardInitialTemplateId = template.id
                                            viewModel.showPaperWizardSheet = true
                                        }
                                        .controlSize(.mini)
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        } header: {
                            Text(category)
                                .font(.caption.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Editor & PDF Panes

    private var editorPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(.secondary)
                Text(viewModel.currentFileURL?.lastPathComponent ?? "Untitled.tex")
                    .font(.system(size: 12, weight: .semibold))
                if !viewModel.rubricTargets.studentModeHideExpl3 {
                    Text("• LaTeX3 / expl3")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Toggle(isOn: $viewModel.proseSpellCheckEnabled) {
                    HStack(spacing: 4) {
                        Image(systemName: "textformat.abc")
                        Text("Spellcheck")
                        if viewModel.proseSpellCheckEnabled && !viewModel.spellingIssues.isEmpty {
                            Text("\(viewModel.spellingIssues.count)")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    .font(.system(size: 10.5, weight: .medium))
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Toggle LaTeX-Aware Prose Spellcheck (⌥⌘;)")
                .accessibilityLabel("Prose Spellcheck")
                .accessibilityValue(
                    viewModel.proseSpellCheckEnabled
                    ? "On, \(viewModel.spellingIssues.count) issues"
                    : "Off"
                )
                .accessibilityHint("Checks prose spelling while ignoring TeX commands and math")

                Button {
                    uiState.showEditorFontPopover.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "textformat.size")
                        Text(viewModel.editorFontName.isEmpty ? "System Mono" : viewModel.editorFontName)
                            .lineLimit(1)
                        Text("\(String(format: "%.0f", viewModel.editorFontSize))pt")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $uiState.showEditorFontPopover, arrowEdge: .bottom) {
                    EditorFontPopoverView(viewModel: viewModel)
                }
                .help("Configure code editor font family and size")
                .accessibilityLabel("Editor Font")
                .accessibilityValue("\(viewModel.editorFontName.isEmpty ? "System Monospaced" : viewModel.editorFontName), \(String(format: "%.1f", viewModel.editorFontSize)) points")
                .accessibilityHint("Opens popover to select editor font family and size")

                editorThemeSegmentedControl

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
                pendingInsertion: $viewModel.pendingEditorInsertion,
                diagnostics: viewModel.diagnostics,
                fontSize: viewModel.editorFontSize,
                fontName: viewModel.editorFontName,
                customFonts: viewModel.customFonts,
                bibEntries: viewModel.bibEntries,
                spellingIssues: viewModel.spellingIssues,
                spellCheckEnabled: viewModel.proseSpellCheckEnabled,
                lightBackground: viewModel.useLightEditorBackground,
                onDropImageFile: { droppedURL in
                    viewModel.handleDroppedImageURL(droppedURL)
                },
                onDropFontFiles: { droppedFontURLs in
                    viewModel.importCustomFonts(urls: droppedFontURLs)
                },
                onDropBibFile: { droppedBibURL in
                    viewModel.handleDroppedBibFileURL(droppedBibURL)
                },
                onApplySpellingFix: { issue, replacement in
                    viewModel.applySpellingSuggestion(issue, replacement: replacement)
                },
                onIgnoreSpellingWord: { word in
                    viewModel.ignoreSpellingWord(word)
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

                Button {
                    viewModel.autoCompileEnabled.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.autoCompileEnabled ? Color.green : Color.secondary.opacity(0.45))
                            .frame(width: 6, height: 6)
                        Image(systemName: viewModel.autoCompileEnabled ? "bolt.fill" : "bolt.slash")
                            .foregroundStyle(viewModel.autoCompileEnabled ? Color.green : Color.secondary)
                        Text(viewModel.autoCompileEnabled ? "Auto-Compile Active" : "Auto-Compile Paused")
                            .foregroundStyle(viewModel.autoCompileEnabled ? Color.primary : Color.secondary)
                    }
                    .font(.system(size: 10.5, weight: viewModel.autoCompileEnabled ? .semibold : .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        viewModel.autoCompileEnabled
                            ? Color.green.opacity(0.15)
                            : Color.secondary.opacity(0.10)
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                viewModel.autoCompileEnabled
                                    ? Color.green.opacity(0.55)
                                    : Color.secondary.opacity(0.22),
                                lineWidth: 1
                            )
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(
                    viewModel.autoCompileEnabled
                        ? "Automatically compile PDF as you type is ACTIVE — click to pause"
                        : "Automatically compile PDF as you type is PAUSED — click to enable"
                )
                .accessibilityLabel("Automatically compile PDF as you type")
                .accessibilityValue(viewModel.autoCompileEnabled ? "Active" : "Paused")

                Text("(⌘-Click in PDF to jump to source line)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

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

    private var autoCompileToolbarButton: some View {
        Button {
            viewModel.autoCompileEnabled.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(viewModel.autoCompileEnabled ? Color.green : Color.secondary.opacity(0.45))
                    .frame(width: 7, height: 7)
                Image(systemName: viewModel.autoCompileEnabled ? "bolt.fill" : "bolt.slash")
                    .foregroundStyle(viewModel.autoCompileEnabled ? Color.green : Color.secondary)
                Text(viewModel.autoCompileEnabled ? "Auto-Compile: ON" : "Auto-Compile: OFF")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(viewModel.autoCompileEnabled ? Color.primary : Color.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                viewModel.autoCompileEnabled
                    ? Color.green.opacity(0.18)
                    : Color.secondary.opacity(0.10)
            )
            .overlay(
                Capsule()
                    .stroke(
                        viewModel.autoCompileEnabled
                            ? Color.green.opacity(0.65)
                            : Color.secondary.opacity(0.25),
                        lineWidth: 1
                    )
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(
            viewModel.autoCompileEnabled
                ? "Automatically compile PDF as you type (ACTIVE — click to pause live compilation)"
                : "Automatically compile PDF as you type (OFF — click to enable live compilation)"
        )
        .accessibilityLabel("Automatically compile PDF as you type")
        .accessibilityValue(viewModel.autoCompileEnabled ? "Active" : "Off")
    }

    private var editorThemeSegmentedControl: some View {
        HStack(spacing: 2) {
            Button {
                viewModel.useLightEditorBackground = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(viewModel.useLightEditorBackground ? Color.orange : Color.secondary)
                    Text("Light")
                }
                .font(.system(size: 10.5, weight: viewModel.useLightEditorBackground ? .semibold : .medium))
                .foregroundStyle(viewModel.useLightEditorBackground ? Color.primary : Color.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(
                    viewModel.useLightEditorBackground
                        ? Color.accentColor.opacity(0.18)
                        : Color.clear
                )
                .overlay(
                    Capsule()
                        .stroke(
                            viewModel.useLightEditorBackground ? Color.accentColor.opacity(0.55) : Color.clear,
                            lineWidth: 1
                        )
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Switch LaTeX editing pane to Light theme")
            .accessibilityLabel("Editing pane Light theme")
            .accessibilityValue(viewModel.useLightEditorBackground ? "Selected" : "Not selected")

            Button {
                viewModel.useLightEditorBackground = false
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "moon.fill")
                        .foregroundStyle(!viewModel.useLightEditorBackground ? Color.indigo : Color.secondary)
                    Text("Dark")
                }
                .font(.system(size: 10.5, weight: !viewModel.useLightEditorBackground ? .semibold : .medium))
                .foregroundStyle(!viewModel.useLightEditorBackground ? Color.primary : Color.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(
                    !viewModel.useLightEditorBackground
                        ? Color.accentColor.opacity(0.18)
                        : Color.clear
                )
                .overlay(
                    Capsule()
                        .stroke(
                            !viewModel.useLightEditorBackground ? Color.accentColor.opacity(0.55) : Color.clear,
                            lineWidth: 1
                        )
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Switch LaTeX editing pane to Dark theme")
            .accessibilityLabel("Editing pane Dark theme")
            .accessibilityValue(!viewModel.useLightEditorBackground ? "Selected" : "Not selected")
        }
        .padding(2)
        .background(Color.secondary.opacity(0.10))
        .overlay(
            Capsule()
                .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

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
        let preflightIssueCount = viewModel.preflightReport.items.filter { $0.severity != .pass }.count
        let budgetDisplay = budgetPillDisplay()

        return HStack(spacing: 14) {
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
            .accessibilityLabel("\(errorCount) errors, \(warningCount) warnings")
            .accessibilityHint("Toggles the diagnostics drawer")

            Button {
                viewModel.selectedDiagnosticTab = 1
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.showConsoleDrawer = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: preflightIssueCount == 0 ? "checkmark.seal.fill" : "checklist")
                        .foregroundStyle(preflightIssueCount == 0 ? .green : .orange)
                    Text(preflightIssueCount == 0 ? "Pre-Flight Ready" : "Pre-Flight: \(preflightIssueCount)")
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(preflightIssueCount == 0 ? "Pre-Flight Ready" : "Pre-Flight \(preflightIssueCount) issues")
            .accessibilityHint("Opens the Academic Pre-Flight checklist tab")

            if let firstError = viewModel.diagnostics.first(where: { $0.severity == .error }) {
                Text(firstError.message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else if let repoMsg = viewModel.repoStatusMessage, !repoMsg.isEmpty {
                Text(repoMsg)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if viewModel.activeRepo != nil, viewModel.activeProject != nil {
                let syncMeta = syncStatusVisual(for: viewModel.gitSyncState)
                Button {
                    viewModel.showProjectHistorySheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: syncMeta.icon)
                            .foregroundStyle(syncMeta.color)
                        Text(viewModel.lastCommitSummary ?? syncMeta.title)
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(syncMeta.color.opacity(0.10))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Open Project Commit History & Version Restore (⌥⌘H)")
                .accessibilityLabel("GitHub sync status: \(syncMeta.title)")
                .accessibilityHint("Opens Project Commit History")
            }

            HStack(spacing: 10) {
                Button {
                    uiState.showPaperBudgetPopover.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: budgetDisplay.icon)
                            .foregroundStyle(budgetDisplay.color)
                        Text(budgetDisplay.label)
                            .foregroundStyle(budgetDisplay.isWarning ? budgetDisplay.color : .primary)
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(budgetDisplay.color.opacity(budgetDisplay.isWarning ? 0.14 : 0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .focused($isBudgetPillFocused)
                .popover(isPresented: $uiState.showPaperBudgetPopover, arrowEdge: .top) {
                    RubricTargetsPopoverView(viewModel: viewModel)
                }
                .help("View detailed paper word counts, abstract budget, and rubric targets")
                .accessibilityLabel("Word and page budget")
                .accessibilityValue(budgetDisplay.accessibilityValue)
                .accessibilityHint("Opens paper breakdown and rubric target settings")

                Text("•")
                    .foregroundStyle(.secondary)
                Text("\(viewModel.documentStats.mathCount) math")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

                if !viewModel.rubricTargets.studentModeHideExpl3 {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.documentStats.expl3SymbolCount) expl3")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

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

    private func budgetPillDisplay() -> (
        label: String,
        icon: String,
        color: Color,
        isWarning: Bool,
        accessibilityValue: String
    ) {
        let proseWords = viewModel.academicStats.proseWordCount
        let pages = max(viewModel.academicStats.pageCount, 1)
        let targetWords = viewModel.rubricTargets.targetProseWords
        let maxPages = viewModel.rubricTargets.maxPageCount

        let wordPart: String
        if let targetWords, targetWords > 0 {
            wordPart = "\(proseWords) / \(targetWords) words"
        } else {
            wordPart = "\(proseWords) words"
        }

        let pagePart: String
        if let maxPages, maxPages > 0 {
            pagePart = "\(pages)/\(maxPages)p"
        } else {
            pagePart = "\(pages)p"
        }

        var isOver = false
        var isNear = false
        var statusSummary = "on track"

        if let targetWords, targetWords > 0 {
            let ratio = Double(proseWords) / Double(targetWords)
            if proseWords > targetWords {
                isOver = true
                statusSummary = "over word limit"
            } else if ratio >= 0.90 {
                isNear = true
                statusSummary = "near word limit"
            }
        }
        if let maxPages, maxPages > 0, pages > maxPages {
            isOver = true
            statusSummary = "over page limit"
        }

        let icon: String
        let color: Color
        if isOver {
            icon = "exclamationmark.octagon.fill"
            color = .red
        } else if isNear {
            icon = "exclamationmark.triangle.fill"
            color = .orange
        } else {
            icon = "doc.text"
            color = .secondary
        }

        let accessibilityValue = "\(wordPart), \(pagePart), \(statusSummary)"
        return ("\(wordPart) • \(pagePart)", icon, color, isOver || isNear, accessibilityValue)
    }

    private func badgeColor(for badge: String) -> Color {
        switch badge {
        case "expl3": return .purple
        case "xparse": return .indigo
        case "env": return .teal
        default: return .blue
        }
    }

    // MARK: - GitHub Multi-Project Sidebar Strip

    @ViewBuilder
    private var githubWorkspaceHeaderStrip: some View {
        if let repo = viewModel.activeRepo {
            let syncVisual = syncStatusVisual(for: viewModel.gitSyncState)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "externaldrive.badge.icloud")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)

                    Text(repo.fullName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)

                    Text(repo.branch)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.14))
                        .clipShape(Capsule())

                    Spacer()

                    Button {
                        viewModel.showRepoSetupSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .focused($isRepoSidebarFocused)
                    .help("Repository Settings, Switch Repo, or Disconnect (⇧⌘G)")
                    .accessibilityLabel("GitHub repository settings")
                }

                HStack(spacing: 6) {
                    Menu {
                        if viewModel.repoProjects.isEmpty {
                            Text("No projects yet")
                        } else {
                            ForEach(viewModel.repoProjects) { project in
                                Button {
                                    requestSwitchProject(project)
                                } label: {
                                    HStack {
                                        Text(project.displayName)
                                        if viewModel.activeProject?.id == project.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }

                        Divider()

                        Button {
                            viewModel.showNewRepoProjectSheet = true
                        } label: {
                            Label("New Project in Repo...", systemImage: "folder.badge.plus")
                        }

                        if let active = viewModel.activeProject {
                            Button {
                                viewModel.showProjectHistorySheet = true
                            } label: {
                                Label("Project Commit History...", systemImage: "clock.arrow.circlepath")
                            }

                            Button(role: .destructive) {
                                uiState.projectPendingDeletion = active
                                uiState.showDeleteProjectConfirm = true
                            } label: {
                                Label("Delete '\(active.displayName)'...", systemImage: "trash")
                            }
                        }

                        Divider()

                        Button {
                            viewModel.showRepoSetupSheet = true
                        } label: {
                            Label("Repository Settings & Switch Repo...", systemImage: "gearshape")
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Text(viewModel.activeProject?.displayName ?? "Select or Create Project...")
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            if viewModel.hasUnsavedBufferEdits {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 6, height: 6)
                                    .help("Uncommitted edits")
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel("Active repository project")
                    .accessibilityValue(viewModel.activeProject?.displayName ?? "None selected")
                }

                HStack(spacing: 6) {
                    Button {
                        if viewModel.isInGitConflictState {
                            viewModel.showProjectHistorySheet = true
                        } else {
                            Task { await viewModel.syncActiveRepository() }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if viewModel.gitSyncState.isBusy {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: syncVisual.icon)
                                    .foregroundStyle(syncVisual.color)
                            }
                            Text(syncVisual.title)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(syncVisual.isWarning ? syncVisual.color : .secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(syncVisual.color.opacity(0.10))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.gitSyncState.isBusy)
                    .help(viewModel.isInGitConflictState ? "Resolve merge conflict" : "Sync active repository with GitHub")
                    .accessibilityLabel("Git sync status: \(syncVisual.title)")

                    Spacer()

                    if viewModel.activeProject != nil {
                        Button {
                            viewModel.showProjectHistorySheet = true
                        } label: {
                            Label("History", systemImage: "clock.arrow.circlepath")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .focused($isHistoryTriggerFocused)
                        .help("Open Project Commit History (⌥⌘H)")
                        .accessibilityLabel("Project commit history")
                    }

                    Button {
                        viewModel.showNewRepoProjectSheet = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("New Project in Repository")
                    .accessibilityLabel("New project in repository")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.65))
            .accessibilityElement(children: .contain)
        } else {
            HStack(spacing: 6) {
                Button {
                    viewModel.showRepoSetupSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link.badge.plus")
                            .foregroundStyle(.blue)
                        Text("Connect GitHub Repo...")
                            .font(.system(size: 11.5, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .focused($isRepoSidebarFocused)
                .help("Connect a GitHub repository to manage and version multiple LaTeX projects (⇧⌘G)")
                .accessibilityLabel("Connect GitHub Repository")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func syncStatusVisual(for state: GitSyncState) -> (title: String, icon: String, color: Color, isWarning: Bool) {
        switch state {
        case .disconnected:
            return ("Disconnected", "icloud.slash", .secondary, false)
        case .idle(let ahead, let behind, _):
            if ahead > 0 && behind > 0 {
                return ("\(ahead)↑ \(behind)↓", "arrow.up.arrow.down.circle.fill", .orange, true)
            } else if ahead > 0 {
                return ("\(ahead) Ahead", "arrow.up.circle.fill", .blue, false)
            } else if behind > 0 {
                return ("\(behind) Behind", "arrow.down.circle.fill", .orange, true)
            }
            return ("Synced", "checkmark.icloud.fill", .green, false)
        case .committing:
            return ("Committing...", "arrow.triangle.branch", .blue, false)
        case .syncing(let status):
            return (status.isEmpty ? "Syncing..." : status, "arrow.triangle.2.circlepath", .blue, false)
        case .offlinePendingPush(let ahead):
            return ("\(max(1, ahead)) Local • Offline", "icloud.slash.fill", .orange, true)
        case .conflict(let files, _):
            return ("Conflict (\(max(1, files.count)))", "exclamationmark.triangle.fill", .red, true)
        case .failed:
            return ("Sync Error", "xmark.octagon.fill", .red, true)
        }
    }

    private func requestSwitchProject(_ project: AcademicProjectDescriptor) {
        guard project.id != viewModel.activeProject?.id else { return }
        if viewModel.hasUnsavedBufferEdits {
            uiState.pendingProjectToSwitch = project
            uiState.showDirtySwitchAlert = true
        } else {
            Task { await viewModel.openProjectFromActiveRepo(project) }
        }
    }
}

@MainActor
private final class DiagnosticsDrawerUIState: ObservableObject {
    @Published var expandedRawIDs: Set<String> = []
}

public struct DiagnosticsDrawerView: View {
    @ObservedObject var viewModel: DocumentViewModel
    @StateObject private var uiState = DiagnosticsDrawerUIState()
    @FocusState private var isDiagnosticsListFocused: Bool

    public var body: some View {
        let contextAnalysis = ContextSuggestionsEngine.analyze(
            source: viewModel.sourceText,
            cursorLine: viewModel.cursorLine,
            diagnostics: viewModel.diagnostics
        )
        let preflightIssueCount = viewModel.preflightReport.items.filter { $0.severity != .pass }.count

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("", selection: $viewModel.selectedDiagnosticTab) {
                    Text("Diagnostics (\(viewModel.diagnostics.count))").tag(0)
                    Text("Pre-Flight (\(preflightIssueCount))").tag(1)
                    Text("Full TeX Transcript").tag(2)
                    Text("Context Suggestions (\(contextAnalysis.items.count))").tag(3)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 620)

                if viewModel.selectedDiagnosticTab == 3 {
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
                .accessibilityLabel("Close diagnostics drawer")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if viewModel.selectedDiagnosticTab == 0 {
                diagnosticsTabContent
            } else if viewModel.selectedDiagnosticTab == 1 {
                PreflightChecklistView(viewModel: viewModel)
            } else if viewModel.selectedDiagnosticTab == 2 {
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

    @ViewBuilder
    private var diagnosticsTabContent: some View {
        if viewModel.diagnostics.isEmpty && viewModel.demystifiedDiagnostics.isEmpty {
            HStack {
                Spacer()
                Label("No errors or warnings reported by Tectonic.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            }
            .frame(maxHeight: .infinity)
            .focused($isDiagnosticsListFocused)
        } else if !viewModel.demystifiedDiagnostics.isEmpty {
            List(viewModel.demystifiedDiagnostics) { item in
                let isExpanded = uiState.expandedRawIDs.contains(item.id)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: iconName(for: item.severity))
                            .foregroundStyle(color(for: item.severity))

                        if let line = item.line {
                            Button("Line \(line)") {
                                viewModel.jumpToLineRequest = line
                                viewModel.cursorLine = line
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .accessibilityLabel("Jump to line \(line)")
                        } else {
                            Text("Global")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .leading)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.shortTitle)
                                .font(.system(size: 12.5, weight: .semibold))
                            Text(item.explanation)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            if !item.rawMessage.isEmpty {
                                Button(isExpanded ? "Hide Log" : "Raw Log") {
                                    if isExpanded {
                                        uiState.expandedRawIDs.remove(item.id)
                                    } else {
                                        uiState.expandedRawIDs.insert(item.id)
                                    }
                                }
                                .buttonStyle(.borderless)
                                .font(.caption2)
                                .accessibilityLabel(isExpanded ? "Hide raw compiler message" : "Show raw compiler message")
                            }

                            if let fixTitle = item.fixButtonTitle, let op = item.fixOperation {
                                Button(fixTitle) {
                                    viewModel.applyAcademicFix(op)
                                    isDiagnosticsListFocused = true
                                    let lineSuffix = item.line.map { " on line \($0)" } ?? ""
                                    NSAccessibility.post(
                                        element: NSApp as Any,
                                        notification: .announcementRequested,
                                        userInfo: [.announcement: "Applied fix: \(fixTitle)\(lineSuffix)"]
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .accessibilityLabel("Auto-fix: \(fixTitle)")
                                .accessibilityHint("Applies deterministic LaTeX fix and recompiles")
                            }
                        }
                    }

                    if isExpanded && !item.rawMessage.isEmpty {
                        Text(item.rawMessage)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .contain)
            }
            .listStyle(.plain)
            .focused($isDiagnosticsListFocused)
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
