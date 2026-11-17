import AppKit
import SwiftUI

private enum RepoSetupMode: String, CaseIterable, Identifiable {
    case connectExisting = "Connect Existing Repo"
    case createNew = "Create New GitHub Repo"

    var id: String { rawValue }
}

private enum RepoSetupFocusField: Hashable {
    case remoteURLField
    case branchField
    case tokenField
    case newRepoNameField
    case newRepoDescriptionField
}

@MainActor
private final class GitHubWorkspaceSetupUIState: ObservableObject {
    @Published var mode: RepoSetupMode = .connectExisting
    @Published var authMethod: GitAuthMethod = .ghCLI
    @Published var remoteURLInput: String = ""
    @Published var branchInput: String = "main"
    @Published var tokenInput: String = ""
    @Published var autoPushOnSave: Bool = true
    @Published var includePDFsInCommits: Bool = false

    @Published var selectedFetchedRepoFullName: String = ""
    @Published var isFetchingRepos: Bool = false
    @Published var localErrorMessage: String? = nil

    // Create New Repository fields
    @Published var newRepoName: String = ""
    @Published var newRepoDescription: String = ""
    @Published var newRepoIsPrivate: Bool = true
    @Published var newRepoBranch: String = "main"

    // Disconnect confirmation
    @Published var repoPendingDisconnect: GitHubRepoConnection? = nil
    @Published var showDisconnectConfirm: Bool = false

    // Loose TeX import
    @Published var looseTexNameDrafts: [String: String] = [:]
}

public struct GitHubWorkspaceSetupSheetView: View {
    @ObservedObject var viewModel: DocumentViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiState = GitHubWorkspaceSetupUIState()
    @FocusState private var focusedField: RepoSetupFocusField?

    public init(viewModel: DocumentViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !viewModel.connectedRepos.isEmpty {
                        connectedReposSection
                    }

                    if let repo = viewModel.activeRepo, !viewModel.looseRepoTeXFiles.isEmpty {
                        looseTeXDiscoverySection(repo: repo)
                    }

                    setupNewRepoSection
                }
                .padding(18)
            }

            Divider()
            footerBar
        }
        .frame(minWidth: 590, idealWidth: 620, minHeight: 540, idealHeight: 620)
        .onAppear {
            if let active = viewModel.activeRepo {
                uiState.autoPushOnSave = active.autoPushOnSave
                uiState.includePDFsInCommits = active.includePDFsInCommits
            }
            Task {
                _ = await viewModel.detectAndTestGitHubCLI()
            }
        }
        .onChange(of: viewModel.repoStatusMessage) { _, message in
            guard let message, !message.isEmpty else { return }
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [.announcement: message]
            )
        }
        .alert("Disconnect Repository?", isPresented: $uiState.showDisconnectConfirm, presenting: uiState.repoPendingDisconnect) { repo in
            Button("Disconnect (Keep Local Clone)") {
                viewModel.disconnectRepo(repo, deleteLocalClone: false)
            }
            Button("Disconnect & Delete Local Clone", role: .destructive) {
                viewModel.disconnectRepo(repo, deleteLocalClone: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: { repo in
            Text("Disconnect '\(repo.fullName)' from LaTeXaP and remove its saved Keychain credential? Remote commits on GitHub are never affected.")
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "externaldrive.badge.icloud")
                .font(.title2)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("GitHub Multi-Project Storage")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Store and version multiple papers cleanly inside projects/<slug>/ folders on GitHub.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close GitHub repository setup")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Connected Repositories Management

    private var connectedReposSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Connected Repositories")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if viewModel.activeRepo != nil {
                        Button {
                            dismiss()
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 300_000_000)
                                viewModel.showNewRepoProjectSheet = true
                            }
                        } label: {
                            Label("New Project in Repo...", systemImage: "folder.badge.plus")
                        }
                        .controlSize(.small)
                        .accessibilityLabel("Create new project in active repository")
                    }
                }

                ForEach(viewModel.connectedRepos) { repo in
                    let isActive = viewModel.activeRepo?.id == repo.id
                    HStack(spacing: 10) {
                        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(repo.fullName)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(repo.branch)
                                    .font(.caption2.monospaced())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.14))
                                    .clipShape(Capsule())
                            }
                            Text("\(repo.authMethod.displayName)\(repo.lastSyncedAt.map { " • Synced \($0.formatted(.relative(presentation: .named)))" } ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if !isActive {
                            Button("Activate") {
                                Task {
                                    await viewModel.switchActiveRepo(repo)
                                    uiState.autoPushOnSave = repo.autoPushOnSave
                                    uiState.includePDFsInCommits = repo.includePDFsInCommits
                                }
                            }
                            .controlSize(.small)
                        }

                        Button(role: .destructive) {
                            uiState.repoPendingDisconnect = repo
                            uiState.showDisconnectConfirm = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Disconnect \(repo.fullName)")
                        .accessibilityLabel("Disconnect \(repo.fullName)")
                    }
                    .padding(8)
                    .background(isActive ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityElement(children: .contain)
                }

                if let active = viewModel.activeRepo {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Active Repository Preferences (\(active.fullName))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Toggle("Auto-push to GitHub on Quick Save (⌘S)", isOn: Binding(
                            get: { active.autoPushOnSave },
                            set: { newVal in
                                Task {
                                    await viewModel.updateActiveRepoSettings(
                                        autoPushOnSave: newVal,
                                        includePDFsInCommits: active.includePDFsInCommits
                                    )
                                }
                            }
                        ))
                        .font(.subheadline)

                        Toggle("Include compiled PDFs in commits (excluded by default to keep repo compact)", isOn: Binding(
                            get: { active.includePDFsInCommits },
                            set: { newVal in
                                Task {
                                    await viewModel.updateActiveRepoSettings(
                                        autoPushOnSave: active.autoPushOnSave,
                                        includePDFsInCommits: newVal
                                    )
                                }
                            }
                        ))
                        .font(.subheadline)
                    }
                }
            }
            .padding(6)
        }
    }

    // MARK: - Loose TeX Migration

    private func looseTeXDiscoverySection(repo: GitHubRepoConnection) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.badge.gearshape")
                        .foregroundStyle(.orange)
                    Text("Existing .tex Files Found Outside projects/")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                }
                Text("Import any standalone .tex file from '\(repo.fullName)' into a managed LaTeXaP project folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(viewModel.looseRepoTeXFiles, id: \.self) { relPath in
                    HStack(spacing: 8) {
                        Text(relPath)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Button("Import as Project") {
                            let stem = ((relPath as NSString).lastPathComponent as NSString).deletingPathExtension
                            let displayName = stem.isEmpty ? "Imported Paper" : stem
                            Task {
                                await viewModel.importExistingTeXFileAsProject(
                                    relativeTeXPath: relPath,
                                    displayName: displayName
                                )
                            }
                        }
                        .controlSize(.small)
                        .disabled(viewModel.gitSyncState.isBusy)
                    }
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .contain)
                }
            }
            .padding(6)
        }
    }

    // MARK: - Add / Create Repository

    private var setupNewRepoSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Setup Mode", selection: $uiState.mode) {
                    ForEach(RepoSetupMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Repository setup mode")

                authSection

                Divider()

                if uiState.mode == .connectExisting {
                    connectExistingFields
                } else {
                    createNewRepoFields
                }

                Toggle("Auto-push to GitHub on Quick Save (⌘S)", isOn: $uiState.autoPushOnSave)
                    .font(.subheadline)

                Toggle("Include compiled PDFs in commits (off by default)", isOn: $uiState.includePDFsInCommits)
                    .font(.subheadline)

                if let errorText = uiState.localErrorMessage {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let statusText = viewModel.repoStatusMessage, !statusText.isEmpty {
                    let isFailure: Bool = {
                        if case .failed = viewModel.gitSyncState { return true }
                        return false
                    }()
                    Label(statusText, systemImage: isFailure ? "xmark.octagon.fill" : "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(isFailure ? .red : .secondary)
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var authSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if uiState.mode == .connectExisting {
                Picker("Authentication", selection: $uiState.authMethod) {
                    ForEach(GitAuthMethod.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .accessibilityLabel("GitHub authentication method")
            }

            if uiState.mode == .createNew || uiState.authMethod == .personalAccessToken {
                HStack(spacing: 8) {
                    SecureField("GitHub Personal Access Token (repo scope)", text: $uiState.tokenInput)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .tokenField)
                        .accessibilityLabel("GitHub Personal Access Token")
                        .accessibilityHint("Stored securely in macOS Keychain, never saved in plain text")

                    Button {
                        Task { await validateTokenAndFetchRepos() }
                    } label: {
                        if uiState.isFetchingRepos {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Validate & Fetch")
                        }
                    }
                    .disabled(uiState.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || uiState.isFetchingRepos)
                }
                Text("Stored securely in macOS Keychain. Fine-grained or classic PAT with Contents read/write (repo) scope.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if uiState.authMethod == .ghCLI {
                HStack(spacing: 8) {
                    Button("Detect & Test GitHub CLI (gh)") {
                        Task {
                            _ = await viewModel.detectAndTestGitHubCLI()
                        }
                    }
                    .controlSize(.small)

                    if let user = viewModel.authenticatedGitHubUser {
                        Label("Signed in as @\(user.login)", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("Uses `gh auth token` if GitHub CLI is installed and logged in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Uses your local SSH keys (~/.ssh) with git@github.com:owner/repo.git remotes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var connectExistingFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.availableGitHubRepos.isEmpty {
                Picker("Your GitHub Repositories", selection: $uiState.selectedFetchedRepoFullName) {
                    Text("Select a repository...").tag("")
                    ForEach(viewModel.availableGitHubRepos) { repo in
                        Text("\(repo.fullName)\(repo.isPrivate ? " (Private)" : "")")
                            .tag(repo.fullName)
                    }
                }
                .onChange(of: uiState.selectedFetchedRepoFullName) { _, fullName in
                    if let match = viewModel.availableGitHubRepos.first(where: { $0.fullName == fullName }) {
                        uiState.remoteURLInput = uiState.authMethod == .sshKey ? match.sshURL : match.cloneURL
                        uiState.branchInput = match.defaultBranch
                        uiState.localErrorMessage = nil
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Repository URL or owner/repo")
                    .font(.caption.weight(.medium))
                TextField("https://github.com/username/my-papers or username/my-papers", text: $uiState.remoteURLInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .remoteURLField)
                    .accessibilityLabel("GitHub repository URL or owner slash repository")

                if let parsed = GitHubWorkspaceValidator.parseAndValidateRemoteURL(uiState.remoteURLInput) {
                    Label("Validated: \(parsed.owner)/\(parsed.repo)", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else if !uiState.remoteURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("Enter a valid https://github.com/owner/repo, git@github.com:owner/repo.git, or owner/repo.", systemImage: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Default Branch")
                    .font(.caption.weight(.medium))
                TextField("main", text: $uiState.branchInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .focused($focusedField, equals: .branchField)
                    .accessibilityLabel("Repository branch")

                if !uiState.branchInput.isEmpty && GitHubWorkspaceValidator.validatedBranchName(uiState.branchInput) == nil {
                    Label("Branch name contains invalid Git ref characters.", systemImage: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private var createNewRepoFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Repository Name")
                    .font(.caption.weight(.medium))
                TextField("grad-school-papers", text: $uiState.newRepoName)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .newRepoNameField)
                    .accessibilityLabel("New GitHub repository name")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Description (optional)")
                    .font(.caption.weight(.medium))
                TextField("LaTeX research papers and coursework", text: $uiState.newRepoDescription)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .newRepoDescriptionField)
            }

            HStack(spacing: 16) {
                Toggle("Private Repository", isOn: $uiState.newRepoIsPrivate)
                TextField("Branch", text: $uiState.newRepoBranch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .accessibilityLabel("Initial branch name")
            }
        }
    }

    private var footerBar: some View {
        HStack {
            if viewModel.gitSyncState.isBusy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(viewModel.gitSyncState.badgeTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Close") {
                dismiss()
            }

            if uiState.mode == .connectExisting {
                Button("Connect & Clone Repository") {
                    Task { await submitConnectExisting() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmitConnectExisting || viewModel.gitSyncState.isBusy)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Create & Connect Repository") {
                    Task { await submitCreateNewRepo() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmitCreateNew || viewModel.gitSyncState.isBusy)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var canSubmitConnectExisting: Bool {
        GitHubWorkspaceValidator.parseAndValidateRemoteURL(uiState.remoteURLInput) != nil &&
            GitHubWorkspaceValidator.validatedBranchName(uiState.branchInput) != nil
    }

    private var canSubmitCreateNew: Bool {
        let nameOK = !uiState.newRepoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let branchOK = GitHubWorkspaceValidator.validatedBranchName(uiState.newRepoBranch) != nil
        let tokenOK = !uiState.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return nameOK && branchOK && tokenOK
    }

    private func validateTokenAndFetchRepos() async {
        uiState.localErrorMessage = nil
        uiState.isFetchingRepos = true
        defer { uiState.isFetchingRepos = false }
        let trimmed = uiState.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await viewModel.validateAndFetchGitHubRepos(token: trimmed)
        } catch {
            uiState.localErrorMessage = error.localizedDescription
        }
    }

    private func submitConnectExisting() async {
        uiState.localErrorMessage = nil
        let tokenToUse: String? = uiState.authMethod == .personalAccessToken
            ? uiState.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let branch = GitHubWorkspaceValidator.validatedBranchName(uiState.branchInput) ?? "main"
        await viewModel.connectGitHubRepository(
            remoteURL: uiState.remoteURLInput,
            branch: branch,
            authMethod: uiState.authMethod,
            token: tokenToUse,
            autoPushOnSave: uiState.autoPushOnSave,
            includePDFsInCommits: uiState.includePDFsInCommits
        )
        if case .failed = viewModel.gitSyncState {
            return
        }
        uiState.tokenInput = ""
        if !viewModel.repoProjects.isEmpty {
            dismiss()
        }
    }

    private func submitCreateNewRepo() async {
        uiState.localErrorMessage = nil
        let trimmedToken = uiState.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = GitHubWorkspaceValidator.validatedBranchName(uiState.newRepoBranch) ?? "main"
        await viewModel.createAndConnectGitHubRepository(
            name: uiState.newRepoName.trimmingCharacters(in: .whitespacesAndNewlines),
            description: uiState.newRepoDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            isPrivate: uiState.newRepoIsPrivate,
            branch: branch,
            token: trimmedToken,
            autoPushOnSave: uiState.autoPushOnSave,
            includePDFsInCommits: uiState.includePDFsInCommits
        )
        if case .failed = viewModel.gitSyncState {
            return
        }
        uiState.tokenInput = ""
    }
}

// MARK: - New Project in Repository Sheet

private enum NewRepoProjectSource: String, CaseIterable, Identifiable {
    case template = "From Academic Template"
    case importCurrent = "Import Current Open Document"

    var id: String { rawValue }
}

private enum NewRepoProjectFocus: Hashable {
    case displayName
    case customSlug
}

@MainActor
private final class NewRepoProjectUIState: ObservableObject {
    @Published var displayName: String = ""
    @Published var customSlug: String = ""
    @Published var slugManuallyEdited: Bool = false
    @Published var starterSource: NewRepoProjectSource = .template
    @Published var selectedTemplateId: String = LaTeXCatalog.defaultTemplate.id
    @Published var localError: String? = nil
}

public struct NewRepoProjectSheetView: View {
    @ObservedObject var viewModel: DocumentViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiState = NewRepoProjectUIState()
    @FocusState private var focusedField: NewRepoProjectFocus?

    public init(viewModel: DocumentViewModel) {
        self.viewModel = viewModel
    }

    private var effectiveSlug: String {
        let candidate = uiState.slugManuallyEdited ? uiState.customSlug : GitHubWorkspaceValidator.slugifyProjectName(uiState.displayName)
        return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var slugConflictExists: Bool {
        viewModel.repoProjects.contains { $0.slug.caseInsensitiveCompare(effectiveSlug) == .orderedSame }
    }

    private var isValidForm: Bool {
        let nameOK = !uiState.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let slugOK = GitHubWorkspaceValidator.isValidProjectSlug(effectiveSlug)
        return nameOK && slugOK && !slugConflictExists && viewModel.activeRepo != nil
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Project in Repository")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(viewModel.activeRepo?.fullName ?? "No repository connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            Form {
                Section("Project Identity") {
                    TextField("Project Name (e.g. NeurIPS 2026 Paper)", text: $uiState.displayName)
                        .focused($focusedField, equals: .displayName)
                        .accessibilityLabel("Project display name")
                        .onChange(of: uiState.displayName) { _, newValue in
                            if !uiState.slugManuallyEdited {
                                uiState.customSlug = GitHubWorkspaceValidator.slugifyProjectName(newValue)
                            }
                            uiState.localError = nil
                        }

                    TextField("Folder Slug (lowercase letters, numbers, hyphens)", text: $uiState.customSlug)
                        .focused($focusedField, equals: .customSlug)
                        .accessibilityLabel("Project folder slug")
                        .onChange(of: uiState.customSlug) { _, newValue in
                            let autoSlug = GitHubWorkspaceValidator.slugifyProjectName(uiState.displayName)
                            if newValue != autoSlug {
                                uiState.slugManuallyEdited = true
                            }
                            uiState.localError = nil
                        }

                    if !effectiveSlug.isEmpty {
                        if !GitHubWorkspaceValidator.isValidProjectSlug(effectiveSlug) {
                            Label("Slug must be 1–64 characters of lowercase letters, digits, and single hyphens.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if slugConflictExists {
                            Label("A project named 'projects/\(effectiveSlug)' already exists in this repository.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Label("Folder path: projects/\(effectiveSlug)/main.tex", systemImage: "folder.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Initial Content") {
                    Picker("Source", selection: $uiState.starterSource) {
                        ForEach(NewRepoProjectSource.allCases) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    if uiState.starterSource == .template {
                        Picker("Starter Template", selection: $uiState.selectedTemplateId) {
                            ForEach(LaTeXCatalog.templates) { template in
                                Text(template.name).tag(template.id)
                            }
                        }
                    } else {
                        Text("Copies your current LaTeX buffer, managed references.bib, and temporary figures into projects/\(effectiveSlug.isEmpty ? "project" : effectiveSlug)/.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let err = uiState.localError {
                    Label(err, systemImage: "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if viewModel.gitSyncState.isBusy {
                    ProgressView().controlSize(.small)
                    Text("Creating project...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create Project") {
                    Task { await createProject() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValidForm || viewModel.gitSyncState.isBusy)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 480, height: 420)
        .onAppear {
            focusedField = .displayName
        }
    }

    private func createProject() async {
        uiState.localError = nil
        let chosenTemplate = LaTeXCatalog.templates.first(where: { $0.id == uiState.selectedTemplateId }) ?? LaTeXCatalog.defaultTemplate
        await viewModel.createProjectInActiveRepo(
            displayName: uiState.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            customSlug: effectiveSlug,
            template: chosenTemplate,
            importCurrentDocument: uiState.starterSource == .importCurrent
        )
        if case .failed(let msg) = viewModel.gitSyncState {
            uiState.localError = msg
            return
        }
        dismiss()
    }
}
