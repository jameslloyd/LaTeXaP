import AppKit
import SwiftUI

private enum CommitPopoverFocus: Hashable {
    case messageField
}

@MainActor
private final class CommitSavePopoverUIState: ObservableObject {
    @Published var localStatusMessage: String? = nil
}

public struct CommitSavePopoverView: View {
    @ObservedObject var viewModel: DocumentViewModel
    @StateObject private var uiState = CommitSavePopoverUIState()
    @FocusState private var focusedField: CommitPopoverFocus?

    private let quickPrefixes: [String] = ["Draft:", "Revisions:", "Citations:", "Figures:", "Final:"]

    public init(viewModel: DocumentViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Save & Commit Project")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 6) {
                        Text(viewModel.activeProject?.displayName ?? "No Active Project")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let branch = viewModel.activeRepo?.branch {
                            Text("• \(branch)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Changed Files (\(viewModel.pendingProjectChanges.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if viewModel.pendingProjectChanges.isEmpty {
                    Text("All pending editor changes will be saved to disk and checked for commit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.pendingProjectChanges) { change in
                                HStack(spacing: 6) {
                                    Image(systemName: iconName(for: change.status))
                                        .font(.caption)
                                        .foregroundStyle(statusColor(for: change.status))
                                        .accessibilityHidden(true)

                                    Text(change.fileName)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .lineLimit(1)

                                    Spacer()

                                    Text(change.statusLabel)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(statusColor(for: change.status).opacity(0.14))
                                        .foregroundStyle(statusColor(for: change.status))
                                        .clipShape(Capsule())
                                }
                                .help(change.relativePath)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(change.fileName), \(change.statusLabel)")
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 110)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Commit Message")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(
                    "Describe your changes",
                    text: $viewModel.commitMessageDraft,
                    prompt: Text(viewModel.defaultCommitMessagePreview),
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .focused($focusedField, equals: .messageField)
                .accessibilityLabel("Commit message")
                .accessibilityHint("Leave blank to use the default timestamped commit message")

                HStack(spacing: 5) {
                    ForEach(quickPrefixes, id: \.self) { prefix in
                        Button(prefix) {
                            applyQuickPrefix(prefix)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .accessibilityLabel("Prefix commit message with \(prefix)")
                    }
                }

                Text("Leave blank to use default timestamped message.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Toggle(
                "Push to GitHub (origin/\(viewModel.activeRepo?.branch ?? "main"))",
                isOn: $viewModel.commitPushImmediately
            )
            .font(.subheadline)

            if case .failed(let message) = viewModel.gitSyncState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            } else if let statusMsg = uiState.localStatusMessage {
                Label(statusMsg, systemImage: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                if viewModel.gitSyncState.isBusy {
                    ProgressView().controlSize(.small)
                }

                Spacer()

                Button("Cancel") {
                    viewModel.showCommitMessagePopover = false
                }
                .keyboardShortcut(.cancelAction)

                Button(viewModel.commitPushImmediately ? "Commit & Push" : "Save & Commit") {
                    Task { await commitNow() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.gitSyncState.isBusy || viewModel.activeProject == nil)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(14)
        .frame(width: 390)
        .onAppear {
            uiState.localStatusMessage = nil
            focusedField = .messageField
        }
    }

    private func applyQuickPrefix(_ prefix: String) {
        let trimmed = viewModel.commitMessageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            viewModel.commitMessageDraft = "\(prefix) "
        } else {
            var cleaned = trimmed
            for existing in quickPrefixes where cleaned.hasPrefix(existing) {
                cleaned = cleaned.dropFirst(existing.count).trimmingCharacters(in: .whitespaces)
                break
            }
            viewModel.commitMessageDraft = cleaned.isEmpty ? "\(prefix) " : "\(prefix) \(cleaned)"
        }
        focusedField = .messageField
    }

    private func commitNow() async {
        await viewModel.saveAndCommitCurrentProject(
            customMessage: viewModel.commitMessageDraft,
            pushImmediately: viewModel.commitPushImmediately
        )

        if let summary = viewModel.repoStatusMessage ?? viewModel.lastCommitSummary {
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [.announcement: summary]
            )
        }

        if case .failed = viewModel.gitSyncState {
            return
        }
        if viewModel.isInGitConflictState {
            viewModel.showCommitMessagePopover = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                viewModel.showProjectHistorySheet = true
            }
            return
        }
        viewModel.showCommitMessagePopover = false
    }

    private func iconName(for status: String) -> String {
        switch status {
        case "A", "??": return "plus.circle.fill"
        case "D": return "minus.circle.fill"
        case "R": return "arrow.right.circle.fill"
        case "U": return "exclamationmark.triangle.fill"
        default: return "pencil.circle.fill"
        }
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "A", "??": return .green
        case "D": return .red
        case "R": return .blue
        case "U": return .orange
        default: return .orange
        }
    }
}
