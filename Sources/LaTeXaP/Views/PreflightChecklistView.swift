import AppKit
import SwiftUI

public struct PreflightChecklistView: View {
    @ObservedObject var viewModel: DocumentViewModel

    public init(viewModel: DocumentViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let report = viewModel.preflightReport
        let blockers = report.items.filter { $0.severity == .blocker }.count
        let warnings = report.items.filter { $0.severity == .warning }.count

        VStack(spacing: 0) {
            // Summary strip
            HStack(spacing: 12) {
                if report.isSubmissionReady && report.items.allSatisfy({ $0.severity == .pass }) {
                    Label("All Pre-Flight Checks Passed — Ready to export PDF or submission bundle.", systemImage: "checkmark.seal.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 8) {
                        if blockers > 0 {
                            Label("\(blockers) Blocker\(blockers == 1 ? "" : "s")", systemImage: "xmark.octagon.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                        if warnings > 0 {
                            Label("\(warnings) Warning\(warnings == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        if blockers == 0 && warnings == 0 {
                            Label("Submission Ready", systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                }

                Spacer()

                Button {
                    viewModel.exportSubmissionBundle()
                } label: {
                    Label("Export Submission (.zip)...", systemImage: "archivebox")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .disabled(viewModel.isExportingSubmissionBundle)
                .accessibilityLabel("Export Submission Zip Bundle")
                .accessibilityHint("Creates a clean zip archive with main.tex, bib, and figures")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if report.items.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Label("All Pre-Flight Checks Passed — Ready to export PDF or submission bundle.", systemImage: "checkmark.seal.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.green)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(report.items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: iconName(for: item.severity))
                            .foregroundStyle(color(for: item.severity))
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(item.category.uppercased())
                                    .font(.system(size: 9.5, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(color(for: item.severity).opacity(0.14))
                                    .foregroundStyle(color(for: item.severity))
                                    .clipShape(Capsule())

                                if let line = item.line {
                                    Button("Line \(line)") {
                                        viewModel.jumpToLineRequest = line
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                }

                                Text(item.title)
                                    .font(.system(size: 12.5, weight: .semibold))
                            }

                            Text(item.detail)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        if let fixOp = item.fixOperation, let fixTitle = item.fixButtonTitle {
                            Button(fixTitle) {
                                viewModel.applyAcademicFix(fixOp)
                                postAnnouncement("Applied pre-flight fix: \(fixTitle)")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else if item.category == "Citations" && item.severity != .pass {
                            Button("Find Citation") {
                                if let missingKey = report.unresolvedCitations.first {
                                    viewModel.bibLookupQuery = missingKey
                                }
                                viewModel.showCitationPickerPopover = true
                            }
                            .controlSize(.small)
                        } else if item.category == "Figures" && item.severity != .pass {
                            Button("Browse Image") {
                                viewModel.pendingDroppedFigureURL = nil
                                viewModel.showFigureAssistantSheet = true
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let line = item.line {
                            viewModel.jumpToLineRequest = line
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(item.severity.rawValue), \(item.category), \(item.title)")
                }
                .listStyle(.plain)
            }
        }
    }

    private func iconName(for severity: PreflightSeverity) -> String {
        switch severity {
        case .pass: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .blocker: return "xmark.octagon.fill"
        }
    }

    private func color(for severity: PreflightSeverity) -> Color {
        switch severity {
        case .pass: return .green
        case .warning: return .orange
        case .blocker: return .red
        }
    }

    private func postAnnouncement(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }
}
