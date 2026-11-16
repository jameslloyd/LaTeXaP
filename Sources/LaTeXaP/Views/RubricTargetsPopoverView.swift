import AppKit
import SwiftUI

private enum RubricFocusField: Hashable {
    case targetWords
    case maxPages
    case maxAbstract
}

@MainActor
private final class RubricTargetsUIState: ObservableObject {
    @Published var targetWordsText: String
    @Published var maxPagesText: String
    @Published var maxAbstractText: String
    @Published var studentModeHideExpl3: Bool

    init(targets: RubricTargetConfig) {
        self.targetWordsText = targets.targetProseWords.map(String.init) ?? ""
        self.maxPagesText = targets.maxPageCount.map(String.init) ?? ""
        self.maxAbstractText = targets.maxAbstractWords.map(String.init) ?? ""
        self.studentModeHideExpl3 = targets.studentModeHideExpl3
    }
}

public struct RubricTargetsPopoverView: View {
    @ObservedObject var viewModel: DocumentViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiState: RubricTargetsUIState
    @FocusState private var focusedField: RubricFocusField?

    public init(viewModel: DocumentViewModel) {
        self.viewModel = viewModel
        self._uiState = StateObject(wrappedValue: RubricTargetsUIState(targets: viewModel.rubricTargets))
    }

    private var budgetStatus: (icon: String, color: Color, message: String, ratio: Double?) {
        let stats = viewModel.academicStats
        if let targetWords = viewModel.rubricTargets.targetProseWords, targetWords > 0 {
            let ratio = Double(stats.proseWordCount) / Double(targetWords)
            let diff = targetWords - stats.proseWordCount
            if diff < 0 {
                return ("xmark.octagon.fill", .red, "Over limit by \(-diff) words", min(1.0, ratio))
            } else if ratio >= 0.90 {
                return ("exclamationmark.triangle.fill", .orange, "Near limit (\(Int(ratio * 100))% • \(diff) left)", ratio)
            } else {
                return ("checkmark.circle.fill", .green, "On track: \(diff) words remaining", ratio)
            }
        }
        if let maxPages = viewModel.rubricTargets.maxPageCount, maxPages > 0, stats.pageCount > 0 {
            let ratio = Double(stats.pageCount) / Double(maxPages)
            if stats.pageCount > maxPages {
                return ("xmark.octagon.fill", .red, "Over page limit by \(stats.pageCount - maxPages)p", 1.0)
            } else if ratio >= 0.90 {
                return ("exclamationmark.triangle.fill", .orange, "Near page limit (\(stats.pageCount)/\(maxPages)p)", ratio)
            } else {
                return ("checkmark.circle.fill", .green, "On track: \(stats.pageCount)/\(maxPages) pages", ratio)
            }
        }
        return ("doc.text", .secondary, "No word or page target set", nil)
    }

    public var body: some View {
        let stats = viewModel.academicStats
        let status = budgetStatus

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Paper Budget & Targets", systemImage: "chart.bar.doc.horizontal")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                if viewModel.rubricTargets.targetProseWords != nil ||
                   viewModel.rubricTargets.maxPageCount != nil ||
                   viewModel.rubricTargets.maxAbstractWords != nil {
                    Button("Clear") {
                        uiState.targetWordsText = ""
                        uiState.maxPagesText = ""
                        uiState.maxAbstractText = ""
                        commitTargets()
                    }
                    .controlSize(.mini)
                    .accessibilityLabel("Clear rubric targets")
                }
            }

            // Progress Banner
            if let ratio = status.ratio {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: status.icon)
                            .foregroundStyle(status.color)
                        Text(status.message)
                            .font(.caption.weight(.semibold))
                    }
                    ProgressView(value: min(1.0, max(0.0, ratio)))
                        .tint(status.color)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(status.color.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityElement(children: .combine)
            }

            // Breakdown Grid
            VStack(alignment: .leading, spacing: 6) {
                Text("LIVE DOCUMENT BREAKDOWN")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                breakdownRow("Body Prose Words", value: "\(stats.proseWordCount)")
                breakdownRow("Abstract Words", value: "\(stats.abstractWordCount)")
                breakdownRow("Math Expressions", value: "\(viewModel.documentStats.mathCount)")
                breakdownRow("References / Citations", value: "\(stats.referenceCount)")
                breakdownRow("Figures & Tables", value: "\(stats.figureCount) fig • \(stats.tableCount) tbl")
                breakdownRow("Rendered PDF Pages", value: stats.pageCount > 0 ? "\(stats.pageCount) p" : "—")
                breakdownRow("Est. Reading Time", value: "\(max(1, stats.estimatedReadingMinutes)) min")
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Rubric Targets Form
            VStack(alignment: .leading, spacing: 8) {
                Text("RUBRIC TARGETS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                HStack {
                    Text("Target Prose Words")
                        .font(.caption)
                    Spacer()
                    TextField("e.g. 2500", text: $uiState.targetWordsText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .targetWords)
                        .onChange(of: uiState.targetWordsText) { _, _ in commitTargets() }
                        .accessibilityLabel("Target prose words")
                }

                HStack {
                    Text("Max PDF Pages")
                        .font(.caption)
                    Spacer()
                    TextField("e.g. 8", text: $uiState.maxPagesText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .maxPages)
                        .onChange(of: uiState.maxPagesText) { _, _ in commitTargets() }
                        .accessibilityLabel("Maximum PDF pages")
                }

                HStack {
                    Text("Max Abstract Words")
                        .font(.caption)
                    Spacer()
                    TextField("e.g. 250", text: $uiState.maxAbstractText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .maxAbstract)
                        .onChange(of: uiState.maxAbstractText) { _, _ in commitTargets() }
                        .accessibilityLabel("Maximum abstract words")
                }
            }

            Divider()

            Toggle(isOn: $uiState.studentModeHideExpl3) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Student Mode")
                        .font(.callout.weight(.medium))
                    Text("Hide LaTeX3 (expl3) counters and macro lint")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: uiState.studentModeHideExpl3) { _, _ in commitTargets() }
            .accessibilityHint("Hides LaTeX3 expl3 metrics in the status bar and diagnostics")
        }
        .padding(14)
        .frame(width: 295)
        .onAppear {
            focusedField = .targetWords
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    private func breakdownRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
        }
        .accessibilityElement(children: .combine)
    }

    private func commitTargets() {
        let updated = RubricTargetConfig(
            targetProseWords: Int(uiState.targetWordsText.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil },
            maxPageCount: Int(uiState.maxPagesText.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil },
            maxAbstractWords: Int(uiState.maxAbstractText.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil },
            studentModeHideExpl3: uiState.studentModeHideExpl3
        )
        viewModel.updateRubricTargets(updated)
    }
}
