import AppKit
import SwiftUI

private enum PaperWizardFocusField: Hashable {
    case titleField
    case authorField
    case institutionField
    case courseField
    case targetWordsField
    case maxPagesField
}

@MainActor
private final class PaperWizardUIState: ObservableObject {
    @Published var config: PaperSetupConfig
    @Published var targetWordsText: String = ""
    @Published var maxPagesText: String = ""
    @Published var titleTouched: Bool = false
    @Published var showReplaceConfirmation: Bool = false

    init(
        initialTemplateId: String?,
        defaultStyle: BibliographyStylePreset,
        existingTargets: RubricTargetConfig
    ) {
        let fallbackId = LaTeXCatalog.templates.first(where: { $0.id == "apa7-student" })?.id
            ?? LaTeXCatalog.templates.first?.id
            ?? "expl3-showcase"
        self.config = PaperSetupConfig(
            templateId: initialTemplateId ?? fallbackId,
            title: "",
            author: "",
            institution: "",
            courseOrVenue: "",
            paperSize: .letterpaper,
            baseFontSizePt: 11,
            doubleSpacing: false,
            anonymizedBlindReview: false,
            bibliographyStyle: defaultStyle
        )
        if let words = existingTargets.targetProseWords {
            self.targetWordsText = "\(words)"
        }
        if let pages = existingTargets.maxPageCount {
            self.maxPagesText = "\(pages)"
        }
    }
}

public struct PaperWizardSheetView: View {
    @ObservedObject var viewModel: DocumentViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiState: PaperWizardUIState
    @FocusState private var focusedField: PaperWizardFocusField?

    public init(viewModel: DocumentViewModel, initialTemplateId: String? = nil) {
        self.viewModel = viewModel
        self._uiState = StateObject(
            wrappedValue: PaperWizardUIState(
                initialTemplateId: initialTemplateId,
                defaultStyle: viewModel.selectedBibliographyStyle,
                existingTargets: viewModel.rubricTargets
            )
        )
    }

    private var titleValidationError: String? {
        let trimmed = uiState.config.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if uiState.titleTouched && trimmed.isEmpty {
            return "Document title is required."
        }
        return nil
    }

    private var isCreateDisabled: Bool {
        uiState.config.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedTemplate: LaTeXTemplate? {
        LaTeXCatalog.templates.first(where: { $0.id == uiState.config.templateId })
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("New Academic Paper", systemImage: "doc.badge.gearshape")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Button {
                    closeSheet()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Paper Setup Wizard")
                .accessibilityHint("Cancels and closes the New Academic Paper wizard")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            HSplitView {
                // Left Template List
                VStack(alignment: .leading, spacing: 0) {
                    Text("STARTER TEMPLATE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .accessibilityAddTraits(.isHeader)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(LaTeXCatalog.templates) { template in
                                let isSelected = uiState.config.templateId == template.id
                                Button {
                                    uiState.config.templateId = template.id
                                    if template.id.contains("apa") {
                                        uiState.config.bibliographyStyle = .apa
                                        uiState.config.doubleSpacing = true
                                    } else if template.id.contains("ieee") {
                                        uiState.config.bibliographyStyle = .ieee
                                        uiState.config.doubleSpacing = false
                                    } else if template.id.contains("acm") {
                                        uiState.config.bibliographyStyle = .acm
                                        uiState.config.doubleSpacing = false
                                    } else if template.id.contains("mla") {
                                        uiState.config.bibliographyStyle = .mla
                                        uiState.config.doubleSpacing = true
                                    }
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: template.icon)
                                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                            .frame(width: 18)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(template.name)
                                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                                .lineLimit(2)
                                            Text(template.subtitle)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(template.name), \(template.subtitle)")
                                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 10)
                    }
                }
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 250)
                .background(Color(NSColor.controlBackgroundColor))

                // Right Configuration Form
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let template = selectedTemplate {
                            HStack(spacing: 8) {
                                Image(systemName: template.icon)
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(template.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(template.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // Metadata
                        VStack(alignment: .leading, spacing: 10) {
                            Text("DOCUMENT METADATA")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityAddTraits(.isHeader)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Document Title (Required)")
                                    .font(.caption.weight(.medium))
                                TextField("e.g. Neural Scaling Laws in Scientific Computing", text: $uiState.config.title)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: .titleField)
                                    .onChange(of: uiState.config.title) { _, _ in
                                        uiState.titleTouched = true
                                    }
                                    .accessibilityLabel("Document Title, required")
                                    .accessibilityValue(titleValidationError ?? uiState.config.title)

                                if let err = titleValidationError {
                                    Label(err, systemImage: "xmark.octagon.fill")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }

                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Author Name(s)")
                                        .font(.caption.weight(.medium))
                                    TextField("e.g. Jane Doe", text: $uiState.config.author)
                                        .textFieldStyle(.roundedBorder)
                                        .focused($focusedField, equals: .authorField)
                                        .disabled(uiState.config.anonymizedBlindReview)
                                        .accessibilityLabel("Author Names")
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Institution / University")
                                        .font(.caption.weight(.medium))
                                    TextField("e.g. MIT CSAIL", text: $uiState.config.institution)
                                        .textFieldStyle(.roundedBorder)
                                        .focused($focusedField, equals: .institutionField)
                                        .disabled(uiState.config.anonymizedBlindReview)
                                        .accessibilityLabel("Institution or University")
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Course / Venue / Conference")
                                    .font(.caption.weight(.medium))
                                TextField("e.g. CS 229 Final Project or NeurIPS 2026", text: $uiState.config.courseOrVenue)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: .courseField)
                                    .accessibilityLabel("Course or Venue")
                            }
                        }

                        Divider()

                        // Formatting & Citation Style
                        VStack(alignment: .leading, spacing: 10) {
                            Text("FORMATTING & CITATION STYLE")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityAddTraits(.isHeader)

                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Paper Size")
                                        .font(.caption.weight(.medium))
                                    Picker("Paper Size", selection: $uiState.config.paperSize) {
                                        ForEach(AcademicPaperSize.allCases) { size in
                                            Text(size.displayName).tag(size)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .labelsHidden()
                                    .accessibilityLabel("Paper size")
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Base Font Size")
                                        .font(.caption.weight(.medium))
                                    Picker("Font Size", selection: $uiState.config.baseFontSizePt) {
                                        Text("10 pt").tag(10)
                                        Text("11 pt").tag(11)
                                        Text("12 pt").tag(12)
                                    }
                                    .pickerStyle(.segmented)
                                    .labelsHidden()
                                    .accessibilityLabel("Base font size")
                                }
                            }

                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Citation & Bibliography Style")
                                        .font(.caption.weight(.medium))
                                    Picker("Citation Style", selection: $uiState.config.bibliographyStyle) {
                                        ForEach(BibliographyStylePreset.allCases) { preset in
                                            Text(preset.displayName).tag(preset)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 190)
                                    .accessibilityLabel("Bibliography style")
                                }

                                Toggle("Double Spacing (setspace)", isOn: $uiState.config.doubleSpacing)
                                    .padding(.top, 16)
                                    .accessibilityHint("Adds double-spaced body lines via setspace")
                            }
                        }

                        Divider()

                        // Review & Optional Rubric Targets
                        VStack(alignment: .leading, spacing: 10) {
                            Text("PEER REVIEW & BUDGET TARGETS")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityAddTraits(.isHeader)

                            Toggle(isOn: $uiState.config.anonymizedBlindReview) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Anonymized Blind Review")
                                        .font(.callout.weight(.medium))
                                    Text("Hides author/institution metadata and adds margin line numbers via lineno.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityHint("Replaces author names with Anonymous Author and enables line numbering")

                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Target Words (Optional)")
                                        .font(.caption.weight(.medium))
                                    TextField("e.g. 2500", text: $uiState.targetWordsText)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 130)
                                        .focused($focusedField, equals: .targetWordsField)
                                        .accessibilityLabel("Optional target word count")
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Max Pages (Optional)")
                                        .font(.caption.weight(.medium))
                                    TextField("e.g. 8", text: $uiState.maxPagesText)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 130)
                                        .focused($focusedField, equals: .maxPagesField)
                                        .accessibilityLabel("Optional maximum page count")
                                }
                            }
                        }
                    }
                    .padding(18)
                }
            }

            Divider()

            // Footer Bar
            HStack {
                Button("Cancel") {
                    closeSheet()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Create Document") {
                    uiState.titleTouched = true
                    guard !isCreateDisabled else {
                        focusedField = .titleField
                        return
                    }
                    if viewModel.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        commitWizard()
                    } else {
                        uiState.showReplaceConfirmation = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreateDisabled)
                .keyboardShortcut(.return, modifiers: [.command])
                .accessibilityLabel("Create Document")
                .accessibilityHint("Generates the configured LaTeX paper in the editor")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 660, height: 540)
        .onAppear {
            focusedField = .titleField
        }
        .alert("Replace current document with new paper?", isPresented: $uiState.showReplaceConfirmation) {
            Button("Create New", role: .destructive) {
                commitWizard()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Creating a new academic paper will replace the current LaTeX source in the editor. Make sure you have saved any work you want to keep.")
        }
        .accessibilityElement(children: .contain)
    }

    private func commitWizard() {
        var targets = viewModel.rubricTargets
        let trimmedWords = uiState.targetWordsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPages = uiState.maxPagesText.trimmingCharacters(in: .whitespacesAndNewlines)
        targets.targetProseWords = Int(trimmedWords).flatMap { $0 > 0 ? $0 : nil }
        targets.maxPageCount = Int(trimmedPages).flatMap { $0 > 0 ? $0 : nil }
        viewModel.updateRubricTargets(targets)

        viewModel.applyPaperSetupWizard(uiState.config)
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "Created new academic paper \(uiState.config.title)",
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
        closeSheet()
    }

    private func closeSheet() {
        viewModel.showPaperWizardSheet = false
        dismiss()
    }
}
