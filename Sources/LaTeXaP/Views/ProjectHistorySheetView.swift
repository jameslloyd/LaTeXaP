import AppKit
import SwiftUI

private enum HistoryPreviewMode: String, CaseIterable, Identifiable {
    case fileContent = "File Snapshot"
    case diff = "Commit Diff"

    var id: String { rawValue }
}

private enum HistoryFocusField: Hashable {
    case commitList
    case previewModePicker
    case restoreButton
}

@MainActor
private final class ProjectHistoryUIState: ObservableObject {
    @Published var selectedCommitID: String? = nil
    @Published var previewMode: HistoryPreviewMode = .fileContent
    @Published var selectedFileRelativePath: String = ""
    @Published var previewText: String = ""
    @Published var isLoadingPreview: Bool = false
    @Published var showRestoreConfirm: Bool = false
}

public struct ProjectHistorySheetView: View {
    @ObservedObject var viewModel: DocumentViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiState = ProjectHistoryUIState()
    @FocusState private var focusedField: HistoryFocusField?

    public init(viewModel: DocumentViewModel) {
        self.viewModel = viewModel
    }

    private var selectedCommit: GitCommitRecord? {
        viewModel.projectCommitHistory.first(where: { $0.id == uiState.selectedCommitID })
            ?? viewModel.projectCommitHistory.first
    }

    private var candidatePreviewFiles: [String] {
        guard let project = viewModel.activeProject else { return [] }
        var paths: [String] = [
            "\(project.relativePath)/\(project.mainTexFile)",
            "\(project.relativePath)/\(project.bibFile)"
        ]
        if let commit = selectedCommit {
            for rel in commit.changedFiles where !paths.contains(rel) {
                paths.append(rel)
            }
        }
        return paths
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if case .conflict(let conflictedFiles, let conflictMessage) = viewModel.gitSyncState {
                conflictResolutionBanner(files: conflictedFiles, message: conflictMessage)
                Divider()
            }

            HSplitView {
                commitTimelinePane
                    .frame(minWidth: 250, idealWidth: 275, maxWidth: 330)

                commitDetailPane
                    .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            footerBar
        }
        .frame(minWidth: 740, idealWidth: 780, minHeight: 500, idealHeight: 560)
        .onAppear {
            if let project = viewModel.activeProject {
                uiState.selectedFileRelativePath = "\(project.relativePath)/\(project.mainTexFile)"
            }
            Task {
                await viewModel.loadProjectCommitHistory()
                if uiState.selectedCommitID == nil {
                    uiState.selectedCommitID = viewModel.projectCommitHistory.first?.id
                }
                await refreshPreview()
            }
            focusedField = .commitList
        }
        .onChange(of: uiState.selectedCommitID) { _, _ in
            Task { await refreshPreview() }
        }
        .onChange(of: uiState.previewMode) { _, _ in
            Task { await refreshPreview() }
        }
        .onChange(of: uiState.selectedFileRelativePath) { _, _ in
            if uiState.previewMode == .fileContent {
                Task { await refreshPreview() }
            }
        }
        .alert(
            "Restore Project Version?",
            isPresented: $uiState.showRestoreConfirm,
            presenting: selectedCommit
        ) { commit in
            Button("Restore \(commit.shortHash)") {
                Task {
                    await viewModel.restoreProjectToCommit(commit)
                    NSAccessibility.post(
                        element: NSApp as Any,
                        notification: .announcementRequested,
                        userInfo: [.announcement: "Restored project to commit \(commit.shortHash)"]
                    )
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { commit in
            let projectName = viewModel.activeProject?.displayName ?? "Project"
            Text("Restore '\(projectName)' to commit \(commit.shortHash) (\"\(commit.message)\")? This creates a new forward commit so your full history stays intact.")
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title2)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Project Commit History")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    Text(viewModel.activeProject?.displayName ?? "No Active Project")
                        .font(.caption.weight(.semibold))
                    if let repo = viewModel.activeRepo {
                        Text("• \(repo.fullName) (\(repo.branch))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button {
                Task {
                    await viewModel.loadProjectCommitHistory()
                    await refreshPreview()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .accessibilityLabel("Refresh commit history")

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Merge Conflict Resolution

    private func conflictResolutionBanner(files: [String], message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Merge Conflict Detected")
                        .font(.subheadline.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(message.isEmpty ? "Both your local workspace and GitHub modified overlapping lines. Choose how to resolve each file." : message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Keep Both Copies") {
                    Task {
                        await viewModel.resolveConflictKeepBoth()
                        NSAccessibility.post(
                            element: NSApp as Any,
                            notification: .announcementRequested,
                            userInfo: [.announcement: "Resolved conflict by keeping both local and GitHub versions"]
                        )
                    }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.gitSyncState.isBusy)
                .accessibilityHint("Saves a conflict copy of your local edits and pulls the GitHub version")
            }

            if !files.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(files, id: \.self) { filePath in
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            Text(filePath)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)

                            Spacer()

                            Button("Keep My Local Version") {
                                Task { await viewModel.resolveConflictFile(filePath, choice: .keepLocal) }
                            }
                            .controlSize(.small)
                            .disabled(viewModel.gitSyncState.isBusy)

                            Button("Use GitHub Version") {
                                Task { await viewModel.resolveConflictFile(filePath, choice: .useRemote) }
                            }
                            .controlSize(.small)
                            .disabled(viewModel.gitSyncState.isBusy)

                            if filePath.hasSuffix(".tex") || filePath.hasSuffix(".bib") {
                                Button("Open in Editor") {
                                    dismiss()
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityElement(children: .contain)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.11))
    }

    // MARK: - Commit Timeline

    private var commitTimelinePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("COMMITS (\(viewModel.projectCommitHistory.count))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            if viewModel.projectCommitHistory.isEmpty {
                ContentUnavailableView(
                    "No Commits Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Save & commit this project (⌘S or ⌥⌘S) to record versions here.")
                )
            } else {
                List(viewModel.projectCommitHistory, selection: $uiState.selectedCommitID) { commit in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(commit.message)
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            Text(commit.shortHash)
                                .font(.system(size: 10.5, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            Text(commit.date.formatted(.relative(presentation: .named)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Label(
                                commit.isPushed ? "Pushed" : "Local",
                                systemImage: commit.isPushed ? "checkmark.icloud.fill" : "arrow.up.circle"
                            )
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(commit.isPushed ? .green : .orange)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(commit.id)
                    .accessibilityElement(children: .contain)
                }
                .focused($focusedField, equals: .commitList)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Detail / Preview

    @ViewBuilder
    private var commitDetailPane: some View {
        if let commit = selectedCommit {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(commit.message)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        Label(commit.shortHash, systemImage: "number")
                            .font(.caption.monospaced())
                        Label(commit.authorName, systemImage: "person")
                            .font(.caption)
                        Label(commit.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Picker("View Mode", selection: $uiState.previewMode) {
                            ForEach(HistoryPreviewMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 230)
                        .focused($focusedField, equals: .previewModePicker)

                        if uiState.previewMode == .fileContent && !candidatePreviewFiles.isEmpty {
                            Picker("File", selection: $uiState.selectedFileRelativePath) {
                                ForEach(candidatePreviewFiles, id: \.self) { relPath in
                                    Text((relPath as NSString).lastPathComponent).tag(relPath)
                                }
                            }
                            .frame(maxWidth: 220)
                        }

                        Spacer()
                    }
                }
                .padding(12)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                if uiState.isLoadingPreview {
                    VStack {
                        Spacer()
                        ProgressView("Loading snapshot...")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if uiState.previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        uiState.previewMode == .diff ? "No Diff Available" : "File Not Present in Commit",
                        systemImage: "doc.text",
                        description: Text("Choose another file or commit to inspect its contents.")
                    )
                } else {
                    ScrollView([.vertical, .horizontal]) {
                        if uiState.previewMode == .diff {
                            diffHighlightedView(uiState.previewText)
                                .padding(12)
                        } else {
                            Text(uiState.previewText)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Select a Commit",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Select a commit on the left to inspect its LaTeX source or diff.")
            )
        }
    }

    private func diffHighlightedView(_ diffText: String) -> some View {
        let lines = diffText.components(separatedBy: .newlines)
        return LazyVStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(diffLineForeground(line))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(diffLineBackground(line))
            }
        }
        .textSelection(.enabled)
    }

    private func diffLineForeground(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return .green
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return .red
        } else if line.hasPrefix("@@") {
            return .blue
        }
        return .primary
    }

    private func diffLineBackground(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return Color.green.opacity(0.08)
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return Color.red.opacity(0.08)
        } else if line.hasPrefix("@@") {
            return Color.blue.opacity(0.07)
        }
        return .clear
    }

    private var footerBar: some View {
        HStack {
            if let commit = selectedCommit {
                Text("Commit \(commit.shortHash) • \(commit.changedFiles.count) changed file(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore This Version") {
                uiState.showRestoreConfirm = true
            }
            .buttonStyle(.borderedProminent)
            .focused($focusedField, equals: .restoreButton)
            .disabled(selectedCommit == nil || viewModel.gitSyncState.isBusy || viewModel.isInGitConflictState)
            .accessibilityLabel("Restore project to selected commit")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func refreshPreview() async {
        guard let commit = selectedCommit else {
            uiState.previewText = ""
            return
        }
        uiState.isLoadingPreview = true
        defer { uiState.isLoadingPreview = false }

        if uiState.previewMode == .diff {
            uiState.previewText = await viewModel.previewDiffAtCommit(commit)
        } else {
            let fallbackPath: String = {
                if let project = viewModel.activeProject {
                    return "\(project.relativePath)/\(project.mainTexFile)"
                }
                return commit.changedFiles.first ?? "main.tex"
            }()
            let targetPath = uiState.selectedFileRelativePath.isEmpty ? fallbackPath : uiState.selectedFileRelativePath
            uiState.previewText = (await viewModel.previewFileAtCommit(commit, relativeFilePath: targetPath)) ?? ""
        }
    }
}
