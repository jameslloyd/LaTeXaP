import AppKit
import SwiftUI
import UniformTypeIdentifiers

public enum FontManagerScope: String, CaseIterable, Identifiable {
    case document = "Document Fonts (fontspec)"
    case editor = "Editor Font"

    public var id: String { rawValue }
}

private enum FontSelection: Hashable {
    case custom(UUID)
    case ctan(String)
    case system(String)
}

private enum FontManagerFocusField: Hashable {
    case searchField
    case emptyChooseButton
    case renameField
    case macroNameField
    case sampleTextField
}

@MainActor
private final class FontManagerUIState: ObservableObject {
    @Published var scope: FontManagerScope = .document
    @Published var selectedItem: FontSelection?
    @Published var selectedRole: LaTeXFontRole = .main
    @Published var customMacroName: String = "customfont"

    @Published var sampleText: String = "The quick brown fox — \\LaTeX3 α + β = γ  0123456789"
    @Published var specimenSize: Double = 20
    @Published var previewLightSurface: Bool = true
    @Published var showProportionalInEditor: Bool = false

    @Published var isDropTargeted: Bool = false

    @Published var isRenaming: Bool = false
    @Published var renameDraft: String = ""
    @Published var renameValidationError: String?

    @Published var fontPendingDeletion: CustomFontRecord?
    @Published var deletionReferenceLine: Int?
    @Published var showDeleteConfirmation: Bool = false
}

public struct FontManagerView: View {
    private static let previewFontService = FontLibraryService()

    @ObservedObject var viewModel: DocumentViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiState = FontManagerUIState()

    @FocusState private var focusedField: FontManagerFocusField?

    public init(viewModel: DocumentViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Filtered Collections

    private var searchQuery: String {
        viewModel.fontSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredCustomFonts: [CustomFontRecord] {
        viewModel.customFonts.filter { font in
            if uiState.scope == .editor && !uiState.showProportionalInEditor && !font.isMonospace {
                return false
            }
            if searchQuery.isEmpty { return true }
            return font.displayName.localizedCaseInsensitiveContains(searchQuery)
                || font.familyName.localizedCaseInsensitiveContains(searchQuery)
                || font.postScriptName.localizedCaseInsensitiveContains(searchQuery)
                || font.styleName.localizedCaseInsensitiveContains(searchQuery)
                || font.format.displayBadge.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    private var filteredCTANPresets: [CTANFontPreset] {
        guard uiState.scope == .document else { return [] }
        return LaTeXCatalog.ctanFontPresets.filter { preset in
            if searchQuery.isEmpty { return true }
            return preset.name.localizedCaseInsensitiveContains(searchQuery)
                || preset.packageName.localizedCaseInsensitiveContains(searchQuery)
                || preset.classification.localizedCaseInsensitiveContains(searchQuery)
                || preset.description.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    private var filteredSystemFonts: [String] {
        let baseList: [String]
        if uiState.scope == .editor && !uiState.showProportionalInEditor {
            let customNames = Set(viewModel.customFonts.flatMap { [$0.postScriptName, $0.familyName] })
            baseList = viewModel.availableEditorFontNames.filter { !$0.isEmpty && !customNames.contains($0) }
        } else {
            baseList = viewModel.availableSystemFontFamilies
        }
        return baseList.filter { family in
            searchQuery.isEmpty || family.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    private var orderedSelections: [FontSelection] {
        var list: [FontSelection] = []
        list.append(contentsOf: filteredCustomFonts.map { .custom($0.id) })
        list.append(contentsOf: filteredCTANPresets.map { .ctan($0.id) })
        list.append(contentsOf: filteredSystemFonts.map { .system($0) })
        return list
    }

    // MARK: - Validation Helpers

    private var cleanedMacroName: String {
        let trimmed = uiState.customMacroName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\\") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private var macroValidationError: String? {
        guard uiState.scope == .document && uiState.selectedRole == .customFamily else { return nil }
        let name = cleanedMacroName
        if name.isEmpty {
            return "Macro name cannot be empty."
        }
        let isValid = name.range(of: #"^[A-Za-z]+$"#, options: .regularExpression) != nil
        if !isValid {
            return "Macro name must start with a letter and contain only A–Z or a–z (e.g., headingfont)."
        }
        return nil
    }

    private var isPrimaryActionDisabled: Bool {
        if uiState.selectedItem == nil { return true }
        if macroValidationError != nil { return true }
        return false
    }

    // MARK: - Active Role Detection

    private func activeDocumentRoles(forIdentifiers identifiers: [String]) -> [String] {
        let lowerIds = Set(identifiers.filter { !$0.isEmpty }.map { $0.lowercased() })
        guard !lowerIds.isEmpty else { return [] }

        var roles: [String] = []
        let patterns: [(label: String, regex: String)] = [
            ("Main", #"\\setmainfont(?:\[[^\]]*\])?\{([^}]+)\}"#),
            ("Sans", #"\\setsansfont(?:\[[^\]]*\])?\{([^}]+)\}"#),
            ("Mono", #"\\setmonofont(?:\[[^\]]*\])?\{([^}]+)\}"#),
            ("Custom", #"\\newfontfamily\s*\{?\\[A-Za-z]+\}?(?:\[[^\]]*\])?\{([^}]+)\}"#)
        ]
        let nsSource = viewModel.sourceText as NSString
        let fullRange = NSRange(location: 0, length: nsSource.length)

        for (label, pattern) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: viewModel.sourceText, range: fullRange)
            for match in matches where match.numberOfRanges >= 2 {
                let target = nsSource.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if lowerIds.contains(target) && !roles.contains(label) {
                    roles.append(label)
                }
            }
        }
        return roles
    }

    private func isEditorActive(identifiers: [String]) -> Bool {
        let current = viewModel.editorFontName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return false }
        return identifiers.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame })
    }

    private func firstReferenceLine(for font: CustomFontRecord) -> Int? {
        let targets = [font.fileName, font.familyName, font.postScriptName]
            .filter { !$0.isEmpty }
        let lines = viewModel.sourceText.components(separatedBy: .newlines)
        for (idx, line) in lines.enumerated() {
            if targets.contains(where: { line.localizedCaseInsensitiveContains($0) }) {
                return idx + 1
            }
        }
        return nil
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            feedbackBannerArea

            HSplitView {
                masterListPane
                    .frame(minWidth: 240, idealWidth: 265, maxWidth: 320)

                detailPreviewPane
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 700, idealWidth: 780, minHeight: 500, idealHeight: 560)
        .onAppear {
            syncInitialSelection()
            if viewModel.customFonts.isEmpty {
                focusedField = .emptyChooseButton
            } else {
                focusedField = .searchField
            }
        }
        .onChange(of: viewModel.customFonts) { oldFonts, newFonts in
            if newFonts.count > oldFonts.count, let newest = newFonts.last {
                uiState.selectedItem = .custom(newest.id)
                uiState.isRenaming = false
            } else if case .custom(let id) = uiState.selectedItem, !newFonts.contains(where: { $0.id == id }) {
                selectFallbackAfterDeletion()
            }
        }
        .onChange(of: uiState.scope) { _, _ in
            uiState.isRenaming = false
            ensureValidSelection()
        }
        .onChange(of: viewModel.fontErrorMessage) { _, newError in
            if let err = newError, !err.isEmpty {
                postVoiceOverAnnouncement(err, highPriority: true)
            }
        }
        .onChange(of: viewModel.fontSuccessMessage) { _, newSuccess in
            if let msg = newSuccess, !msg.isEmpty {
                postVoiceOverAnnouncement(msg, highPriority: false)
            }
        }
        .onKeyPress(.escape) {
            if viewModel.fontErrorMessage != nil || viewModel.fontSuccessMessage != nil {
                viewModel.clearFontFeedback()
                return .handled
            }
            if uiState.isRenaming {
                uiState.isRenaming = false
                return .handled
            }
            dismissSheet()
            return .handled
        }
        .alert(
            "Remove Custom Font",
            isPresented: $uiState.showDeleteConfirmation,
            presenting: uiState.fontPendingDeletion
        ) { font in
            if uiState.deletionReferenceLine != nil {
                Button("Remove Font & Preamble Line", role: .destructive) {
                    removePreambleReferences(for: font)
                    performDeletion(font)
                }
                Button("Remove Font", role: .destructive) {
                    performDeletion(font)
                }
            } else {
                Button("Remove Font", role: .destructive) {
                    performDeletion(font)
                }
            }
            Button("Cancel", role: .cancel) {
                uiState.fontPendingDeletion = nil
                uiState.deletionReferenceLine = nil
            }
        } message: { font in
            if let line = uiState.deletionReferenceLine {
                Text("Remove '\(font.displayName)'? It is referenced on Line \(line) of your current document and removing the file will cause compilation to fail.")
            } else {
                Text("Remove '\(font.displayName)' from LaTeXaP's managed font library? The original file on your disk outside LaTeXaP will not be touched.")
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Label("Font Manager", systemImage: "textformat")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Picker("Font Scope", selection: $uiState.scope) {
                ForEach(FontManagerScope.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            .accessibilityLabel("Font assignment scope")
            .accessibilityHint("Switch between document fontspec typesetting and code editor font settings")

            Spacer()

            Button {
                dismissSheet()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Font Manager")
            .accessibilityHint("Closes the Font Manager sheet")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Feedback Banners

    @ViewBuilder
    private var feedbackBannerArea: some View {
        if viewModel.isImportingFont {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Validating and importing font...")
                    .font(.callout.weight(.medium))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.10))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Validating and importing font")
        }

        if let err = viewModel.fontErrorMessage {
            HStack(spacing: 8) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    viewModel.clearFontFeedback()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss error")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.12))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.red.opacity(0.35)), alignment: .bottom)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Error: \(err)")
        }

        if let success = viewModel.fontSuccessMessage {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(success)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    viewModel.clearFontFeedback()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss notification")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.12))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.green.opacity(0.35)), alignment: .bottom)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Success: \(success)")
        }
    }

    // MARK: - Left Master List

    private var masterListPane: some View {
        VStack(spacing: 0) {
            // Search & Add Toolbar
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter fonts by name or style...", text: $viewModel.fontSearchText)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .searchField)
                        .accessibilityLabel("Filter fonts")
                    if !viewModel.fontSearchText.isEmpty {
                        Button {
                            viewModel.fontSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear font search")
                    }
                }
                .padding(7)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )

                // Add Font button
                HStack(spacing: 8) {
                    Button {
                        viewModel.openImportFontPanel()
                    } label: {
                        Label("Add Font...", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel("Add custom font files")
                    .accessibilityHint("Opens file picker for TTF, OTF, or TTC fonts")
                }

                if uiState.scope == .editor {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Show proportional fonts", isOn: $uiState.showProportionalInEditor)
                            .font(.caption)
                            .accessibilityHint("Includes non-monospace fonts in the Editor Font list")

                        if uiState.showProportionalInEditor {
                            HStack(alignment: .top, spacing: 5) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                Text("Proportional fonts may misalign code columns and inline ghost completions.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)

            Divider()

            // List Content
            if filteredCustomFonts.isEmpty && filteredCTANPresets.isEmpty && filteredSystemFonts.isEmpty && !searchQuery.isEmpty {
                ContentUnavailableView {
                    Label("No Matching Fonts", systemImage: "magnifyingglass")
                } description: {
                    Text("No fonts match '\(viewModel.fontSearchText)'. Try clearing the filter or adding a custom font.")
                } actions: {
                    Button("Clear Filter") {
                        viewModel.fontSearchText = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        // Custom Fonts Section
                        sectionHeader("CUSTOM FONTS (\(filteredCustomFonts.count))")

                        if viewModel.customFonts.isEmpty && searchQuery.isEmpty {
                            emptyCustomFontsDropzone
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                        } else if filteredCustomFonts.isEmpty {
                            Text(uiState.scope == .editor && !uiState.showProportionalInEditor
                                 ? "No custom monospace fonts added."
                                 : "No matching custom fonts.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        } else {
                            ForEach(filteredCustomFonts) { font in
                                customFontRow(font)
                                    .padding(.horizontal, 6)
                            }
                        }

                        // CTAN Font Presets (Document Scope)
                        if !filteredCTANPresets.isEmpty {
                            sectionHeader("CTAN FONT PACKAGES (\(filteredCTANPresets.count))")
                                .padding(.top, 8)
                            ForEach(filteredCTANPresets) { preset in
                                ctanPresetRow(preset)
                                    .padding(.horizontal, 6)
                            }
                        }

                        // System Fonts Section
                        if !filteredSystemFonts.isEmpty {
                            sectionHeader("SYSTEM FONTS (\(filteredSystemFonts.count))")
                                .padding(.top, 8)
                            ForEach(filteredSystemFonts, id: \.self) { family in
                                systemFontRow(family)
                                    .padding(.horizontal, 6)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .focusable()
                .onKeyPress(.upArrow) {
                    moveSelection(delta: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveSelection(delta: 1)
                    return .handled
                }
                .onKeyPress(.return) {
                    applyCurrentSelection()
                    return .handled
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    uiState.isDropTargeted ? Color.accentColor : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
                .padding(4)
        )
        .onDrop(of: [.fileURL], isTargeted: $uiState.isDropTargeted, perform: handleDrop(providers:))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Font library list")
    }

    private var emptyCustomFontsDropzone: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.badge.plus")
                .font(.title2)
                .foregroundStyle(uiState.isDropTargeted ? Color.accentColor : Color.secondary)

            Text("No Custom Fonts Added")
                .font(.caption.weight(.semibold))

            Text("Drop .ttf, .otf, or .ttc font files here to use with XeTeX (fontspec) or the code editor.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Choose Font Files...") {
                viewModel.openImportFontPanel()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .focused($focusedField, equals: .emptyChooseButton)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(uiState.isDropTargeted ? Color.accentColor.opacity(0.10) : Color(NSColor.textBackgroundColor).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    uiState.isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Add custom font files")
        .accessibilityHint("Opens file picker or accepts dropped TTF, OTF, or TTC files")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .accessibilityAddTraits(.isHeader)
    }

    private func customFontRow(_ font: CustomFontRecord) -> some View {
        let selection = FontSelection.custom(font.id)
        let isSelected = uiState.selectedItem == selection
        let docRoles = activeDocumentRoles(forIdentifiers: [font.fileName, font.familyName, font.postScriptName])
        let editorActive = isEditorActive(identifiers: [font.postScriptName, font.familyName])

        return Button {
            uiState.selectedItem = selection
            uiState.isRenaming = false
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(font.displayName)
                        .font(Font(LaTeXSyntaxHighlighter.resolveFont(name: font.postScriptName, size: 13, weight: .regular)))
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

                HStack(spacing: 4) {
                    Text(font.styleName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if font.isMonospace {
                        rolePill("Mono", color: .teal)
                    }

                    ForEach(docRoles, id: \.self) { role in
                        rolePill(role, color: .indigo)
                    }

                    if editorActive {
                        rolePill("Editor", color: .green)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename...") {
                uiState.selectedItem = selection
                beginRename(for: font)
            }
            Divider()
            Button("Remove Font...", role: .destructive) {
                requestDelete(font)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription(for: font, docRoles: docRoles, editorActive: editorActive))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func ctanPresetRow(_ preset: CTANFontPreset) -> some View {
        let selection = FontSelection.ctan(preset.id)
        let isSelected = uiState.selectedItem == selection
        let isIncluded = viewModel.sourceText.contains("{\(preset.packageName)}")

        return Button {
            uiState.selectedItem = selection
            uiState.isRenaming = false
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(preset.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)

                    Spacer()

                    Text("CTAN")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.14))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }

                HStack(spacing: 4) {
                    Text(preset.classification)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if isIncluded {
                        rolePill("Added", color: .green)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(preset.name), CTAN \(preset.classification) package\(isIncluded ? ", added to document" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func systemFontRow(_ family: String) -> some View {
        let selection = FontSelection.system(family)
        let isSelected = uiState.selectedItem == selection
        let docRoles = activeDocumentRoles(forIdentifiers: [family])
        let editorActive = isEditorActive(identifiers: [family])

        return Button {
            uiState.selectedItem = selection
            uiState.isRenaming = false
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(family)
                        .font(.custom(family, size: 12.5))
                        .lineLimit(1)

                    Spacer()

                    Text("System")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                }

                if !docRoles.isEmpty || editorActive {
                    HStack(spacing: 4) {
                        ForEach(docRoles, id: \.self) { role in
                            rolePill(role, color: .indigo)
                        }
                        if editorActive {
                            rolePill("Editor", color: .green)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(family), macOS system font\(docRoles.isEmpty ? "" : ", active as Document \(docRoles.joined(separator: ", "))")\(editorActive ? ", active as Editor font" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func rolePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Right Detail & Preview Pane

    @ViewBuilder
    private var detailPreviewPane: some View {
        switch uiState.selectedItem {
        case .custom(let id):
            if let font = viewModel.customFonts.first(where: { $0.id == id }) {
                customFontDetailView(font)
            } else {
                emptyDetailPlaceholder
            }
        case .ctan(let id):
            if let preset = LaTeXCatalog.ctanFontPresets.first(where: { $0.id == id }) {
                ctanPresetDetailView(preset)
            } else {
                emptyDetailPlaceholder
            }
        case .system(let family):
            systemFontDetailView(family)
        case nil:
            emptyDetailPlaceholder
        }
    }

    private var emptyDetailPlaceholder: some View {
        ContentUnavailableView(
            "Select a Font to Preview",
            systemImage: "textformat",
            description: Text("Choose a custom font, CTAN package, or macOS system font from the list, or drop .ttf/.otf/.ttc files to add new fonts.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func customFontDetailView(_ font: CustomFontRecord) -> some View {
        let docRoles = activeDocumentRoles(forIdentifiers: [font.fileName, font.familyName, font.postScriptName])
        let editorActive = isEditorActive(identifiers: [font.postScriptName, font.familyName])

        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        if uiState.isRenaming {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    TextField("Font display name", text: $uiState.renameDraft)
                                        .textFieldStyle(.roundedBorder)
                                        .focused($focusedField, equals: .renameField)
                                        .onChange(of: uiState.renameDraft) { _, newValue in
                                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                            uiState.renameValidationError = trimmed.isEmpty ? "Font name cannot be empty." : nil
                                        }
                                        .onSubmit { commitRename(for: font) }
                                        .accessibilityLabel("Custom font display name")
                                        .accessibilityValue(uiState.renameValidationError ?? uiState.renameDraft)

                                    Button("Save") {
                                        commitRename(for: font)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(uiState.renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                    Button("Cancel") {
                                        uiState.isRenaming = false
                                        uiState.renameValidationError = nil
                                    }
                                    .controlSize(.small)
                                }
                                if let err = uiState.renameValidationError {
                                    Label(err, systemImage: "xmark.octagon.fill")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        } else {
                            HStack(alignment: .center, spacing: 8) {
                                Text(font.displayName)
                                    .font(.title2.weight(.semibold))
                                    .accessibilityAddTraits(.isHeader)

                                Button {
                                    beginRename(for: font)
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .accessibilityLabel("Rename \(font.displayName)")
                                .accessibilityHint("Edits the display name of this custom font")

                                Spacer()

                                Text(font.format.displayBadge)
                                    .font(.caption.weight(.bold).monospaced())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.14))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(Capsule())
                            }
                        }

                        HStack(spacing: 10) {
                            Text("PostScript: \(font.postScriptName)")
                            Text("•")
                            Text("Style: \(font.styleName)")
                            Text("•")
                            Text(ByteCountFormatter.string(fromByteCount: font.fileSizeBytes, countStyle: .file))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            rolePill(font.isMonospace ? "Monospace" : "Proportional", color: font.isMonospace ? .teal : .secondary)
                            ForEach(docRoles, id: \.self) { role in
                                rolePill("Document \(role)", color: .indigo)
                            }
                            if editorActive {
                                rolePill("Active Editor Font", color: .green)
                            }
                        }
                    }

                    // Live Specimen Preview
                    specimenPreviewCard(
                        font: Font(LaTeXSyntaxHighlighter.resolveFont(
                            name: font.postScriptName,
                            size: CGFloat(uiState.specimenSize),
                            weight: .regular
                        )),
                        boldFont: Font(LaTeXSyntaxHighlighter.resolveFont(
                            name: font.postScriptName,
                            size: CGFloat(min(18, uiState.specimenSize)),
                            weight: .bold
                        )),
                        familyLabel: font.familyName
                    )

                    // Scope Controls
                    if uiState.scope == .document {
                        documentRoleAssignmentSection(
                            customFont: font,
                            systemFamily: nil
                        )
                    } else {
                        editorScopeAssignmentSection(
                            fontName: font.postScriptName,
                            isMonospace: font.isMonospace
                        )
                    }
                }
                .padding(18)
            }

            Divider()

            // Footer Action Bar
            HStack {
                Button(role: .destructive) {
                    requestDelete(font)
                } label: {
                    Label("Remove Font", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .accessibilityLabel("Remove custom font \(font.displayName)")
                .accessibilityHint("Deletes this custom font from LaTeXaP")

                Spacer()

                if uiState.scope == .document {
                    let alreadyApplied = isRoleApplied(for: [font.fileName, font.familyName, font.postScriptName], role: uiState.selectedRole)
                    Button(alreadyApplied ? "Update Preamble" : "Insert into Preamble") {
                        viewModel.applyCustomFontToDocument(
                            font,
                            role: uiState.selectedRole,
                            customCommand: "\\\(cleanedMacroName)"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPrimaryActionDisabled)
                    .keyboardShortcut(.return, modifiers: [.command])
                } else {
                    Button("Apply Editor Font") {
                        viewModel.selectEditorFont(font.postScriptName)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Font preview and actions")
    }

    private func systemFontDetailView(_ family: String) -> some View {
        let docRoles = activeDocumentRoles(forIdentifiers: [family])
        let editorActive = isEditorActive(identifiers: [family])
        let resolved = LaTeXSyntaxHighlighter.resolveFont(name: family, size: CGFloat(uiState.specimenSize), weight: .regular)
        let isMono = resolved.isFixedPitch

        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(family)
                                .font(.title2.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)

                            Spacer()

                            Text("macOS System")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.14))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }

                        HStack(spacing: 6) {
                            rolePill(isMono ? "Monospace" : "Proportional", color: isMono ? .teal : .secondary)
                            ForEach(docRoles, id: \.self) { role in
                                rolePill("Document \(role)", color: .indigo)
                            }
                            if editorActive {
                                rolePill("Active Editor Font", color: .green)
                            }
                        }
                    }

                    specimenPreviewCard(
                        font: .custom(family, size: CGFloat(uiState.specimenSize)),
                        boldFont: .custom(family, size: CGFloat(min(18, uiState.specimenSize))).weight(.bold),
                        familyLabel: family
                    )

                    if uiState.scope == .document {
                        documentRoleAssignmentSection(
                            customFont: nil,
                            systemFamily: family
                        )
                    } else {
                        editorScopeAssignmentSection(
                            fontName: family,
                            isMonospace: isMono
                        )
                    }
                }
                .padding(18)
            }

            Divider()

            HStack {
                Button(role: .destructive) {} label: {
                    Label("Remove Font", systemImage: "trash")
                }
                .disabled(true)
                .help("macOS system fonts cannot be deleted from LaTeXaP.")
                .accessibilityHint("macOS system fonts cannot be deleted from LaTeXaP")

                Spacer()

                if uiState.scope == .document {
                    let alreadyApplied = isRoleApplied(for: [family], role: uiState.selectedRole)
                    Button(alreadyApplied ? "Update Preamble" : "Insert into Preamble") {
                        viewModel.applySystemFontToDocument(
                            familyName: family,
                            role: uiState.selectedRole,
                            customCommand: "\\\(cleanedMacroName)"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPrimaryActionDisabled)
                    .keyboardShortcut(.return, modifiers: [.command])
                } else {
                    Button("Apply Editor Font") {
                        viewModel.selectEditorFont(family)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Font preview and actions")
    }

    private func ctanPresetDetailView(_ preset: CTANFontPreset) -> some View {
        let isIncluded = viewModel.sourceText.contains("{\(preset.packageName)}")

        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.name)
                                .font(.title2.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                            Text("Package: \\usepackage\(preset.options.isEmpty ? "" : "[\(preset.options)]"){\(preset.packageName)}")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(preset.classification)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }

                    Text(preset.description)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("GENERATED PREAMBLE STATEMENT")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(preset.usepackageStatement)
                            .font(.system(size: 12.5, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                            .textSelection(.enabled)
                    }

                    Text("Tectonic automatically downloads CTAN font packages on first compilation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
            }

            Divider()

            HStack {
                Spacer()
                Button(isIncluded ? "Already in Preamble" : "Insert CTAN Package") {
                    viewModel.applyCTANFontPreset(preset)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isIncluded)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CTAN font preset details")
    }

    // MARK: - Specimen Preview & Role Assignment Subviews

    private func specimenPreviewCard(font: Font, boldFont: Font, familyLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LIVE SPECIMEN PREVIEW")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    Text("\(Int(uiState.specimenSize)) pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Slider(value: $uiState.specimenSize, in: 10...36, step: 1)
                        .frame(width: 110)
                        .accessibilityLabel("Specimen preview font size")
                        .accessibilityValue("\(Int(uiState.specimenSize)) points")

                    Button {
                        uiState.previewLightSurface.toggle()
                    } label: {
                        Label(
                            uiState.previewLightSurface ? "Light" : "Dark",
                            systemImage: uiState.previewLightSurface ? "sun.max.fill" : "moon.fill"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Toggle specimen preview background")
                    .accessibilityValue(uiState.previewLightSurface ? "Light surface" : "Dark surface")
                }
            }

            TextField("Preview sample text", text: $uiState.sampleText)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .sampleTextField)
                .accessibilityLabel("Specimen sample text")

            VStack(alignment: .leading, spacing: 10) {
                Text(uiState.sampleText.isEmpty ? "The quick brown fox jumps over the lazy dog 0123456789" : uiState.sampleText)
                    .font(font)
                    .foregroundStyle(uiState.previewLightSurface ? Color(red: 0.06, green: 0.09, blue: 0.16) : Color(red: 0.94, green: 0.96, blue: 0.99))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .opacity(0.4)

                HStack(spacing: 12) {
                    Text("Regular")
                        .font(font.weight(.regular))
                    Text("Bold")
                        .font(boldFont)
                    Text("Italic")
                        .font(font.italic())
                    Text("0123456789")
                        .font(font)
                }
                .font(.caption)
                .foregroundStyle(uiState.previewLightSurface ? Color(red: 0.24, green: 0.30, blue: 0.40) : Color(red: 0.72, green: 0.78, blue: 0.88))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(uiState.previewLightSurface ? Color.white : Color(red: 0.05, green: 0.07, blue: 0.09))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Specimen rendering for \(familyLabel) at \(Int(uiState.specimenSize)) points")
        }
    }

    private var isFontspecLoaded: Bool {
        let lines = viewModel.sourceText.components(separatedBy: .newlines)
        let preambleEnd = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("\\begin{document}")
        }) ?? lines.count
        let regex = try? NSRegularExpression(
            pattern: #"\\usepackage(?:\[[^\]]*\])?\{[^}]*\bfontspec\b[^}]*\}"#
        )
        for idx in 0..<preambleEnd {
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("%") { continue }
            let nsLine = lines[idx] as NSString
            if regex?.firstMatch(in: lines[idx], range: NSRange(location: 0, length: nsLine.length)) != nil {
                return true
            }
        }
        return false
    }

    private func documentRoleAssignmentSection(customFont: CustomFontRecord?, systemFamily: String?) -> some View {
        let needsFontspec = !isFontspecLoaded
        let commandLine: String = {
            let cmd = cleanedMacroName.isEmpty ? "customfont" : cleanedMacroName
            if let customFont {
                return Self.previewFontService.generateFontspecBlock(
                    for: customFont,
                    role: uiState.selectedRole,
                    customCommandName: cmd
                )
            } else if let systemFamily {
                return Self.previewFontService.generateSystemFontspecBlock(
                    familyName: systemFamily,
                    role: uiState.selectedRole,
                    customCommandName: cmd
                )
            }
            return ""
        }()
        let previewCode = (needsFontspec ? "\\usepackage{fontspec}\n" : "") + commandLine
        let isCustomFile = (customFont != nil)

        return VStack(alignment: .leading, spacing: 10) {
            Text("LATEX FONT ROLE (XETEX FONTSPEC)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Document Role", selection: $uiState.selectedRole) {
                ForEach(LaTeXFontRole.allCases) { role in
                    Text(role.displayName).tag(role)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("LaTeX document font role")

            if uiState.selectedRole == .customFamily {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Macro Name:")
                            .font(.callout)
                        TextField("e.g. headingfont", text: $uiState.customMacroName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .focused($focusedField, equals: .macroNameField)
                            .accessibilityLabel("Custom LaTeX font macro name")
                            .accessibilityValue(macroValidationError ?? uiState.customMacroName)
                    }

                    if let err = macroValidationError {
                        Label(err, systemImage: "xmark.octagon.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("Use \\\(cleanedMacroName){...} in your document body.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("PREAMBLE CODE PREVIEW")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(previewCode)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .textSelection(.enabled)
            }

            if !isCustomFile {
                Text("System fonts are resolved by XeTeX using their macOS family name.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func editorScopeAssignmentSection(fontName: String, isMonospace: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CODE EDITOR FONT")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if !isMonospace {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Proportional fonts may misalign code columns and inline ghost completions.")
                        .font(.callout)
                        .foregroundStyle(.primary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: 10) {
                Button("Reset to System Mono") {
                    viewModel.resetEditorFontToDefault()
                }
                .controlSize(.small)
                .disabled(viewModel.editorFontName.isEmpty)

                if isEditorActive(identifiers: [fontName]) {
                    Label("Currently active in code editor", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    // MARK: - Actions & Helpers

    private func isRoleApplied(for identifiers: [String], role: LaTeXFontRole) -> Bool {
        let active = activeDocumentRoles(forIdentifiers: identifiers)
        switch role {
        case .main: return active.contains("Main")
        case .sans: return active.contains("Sans")
        case .mono: return active.contains("Mono")
        case .customFamily: return active.contains("Custom")
        }
    }

    private func beginRename(for font: CustomFontRecord) {
        uiState.renameDraft = font.displayName
        uiState.renameValidationError = nil
        uiState.isRenaming = true
        focusedField = .renameField
    }

    private func commitRename(for font: CustomFontRecord) {
        let trimmed = uiState.renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            uiState.renameValidationError = "Font name cannot be empty."
            return
        }
        viewModel.renameCustomFont(font, to: trimmed)
        uiState.isRenaming = false
        uiState.renameValidationError = nil
    }

    private func requestDelete(_ font: CustomFontRecord) {
        uiState.fontPendingDeletion = font
        uiState.deletionReferenceLine = firstReferenceLine(for: font)
        uiState.showDeleteConfirmation = true
    }

    private func performDeletion(_ font: CustomFontRecord) {
        viewModel.deleteCustomFont(font)
        uiState.fontPendingDeletion = nil
        uiState.deletionReferenceLine = nil
    }

    private func removePreambleReferences(for font: CustomFontRecord) {
        let targets = [font.fileName, font.familyName, font.postScriptName]
            .filter { !$0.isEmpty }
        let lines = viewModel.sourceText.components(separatedBy: .newlines)
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isFontCommand = trimmed.hasPrefix("\\setmainfont")
                || trimmed.hasPrefix("\\setsansfont")
                || trimmed.hasPrefix("\\setmonofont")
                || trimmed.hasPrefix("\\newfontfamily")
            if isFontCommand && targets.contains(where: { line.localizedCaseInsensitiveContains($0) }) {
                return false
            }
            return true
        }
        viewModel.sourceText = filtered.joined(separator: "\n")
    }

    private func syncInitialSelection() {
        if uiState.selectedItem != nil { return }
        if let firstCustom = filteredCustomFonts.first {
            uiState.selectedItem = .custom(firstCustom.id)
        } else if let firstPreset = filteredCTANPresets.first {
            uiState.selectedItem = .ctan(firstPreset.id)
        } else if let firstSystem = filteredSystemFonts.first {
            uiState.selectedItem = .system(firstSystem)
        }
    }

    private func ensureValidSelection() {
        let all = orderedSelections
        if let current = uiState.selectedItem, all.contains(current) {
            return
        }
        uiState.selectedItem = all.first
    }

    private func selectFallbackAfterDeletion() {
        let all = orderedSelections
        uiState.selectedItem = all.first
        if viewModel.customFonts.isEmpty {
            focusedField = .emptyChooseButton
        }
    }

    private func moveSelection(delta: Int) {
        let all = orderedSelections
        guard !all.isEmpty else { return }
        guard let current = uiState.selectedItem, let idx = all.firstIndex(of: current) else {
            uiState.selectedItem = all.first
            return
        }
        let nextIdx = max(0, min(all.count - 1, idx + delta))
        uiState.selectedItem = all[nextIdx]
        uiState.isRenaming = false
    }

    private func applyCurrentSelection() {
        guard !isPrimaryActionDisabled, let selectedItem = uiState.selectedItem else { return }
        switch selectedItem {
        case .custom(let id):
            guard let font = viewModel.customFonts.first(where: { $0.id == id }) else { return }
            if uiState.scope == .document {
                viewModel.applyCustomFontToDocument(font, role: uiState.selectedRole, customCommand: "\\\(cleanedMacroName)")
            } else {
                viewModel.selectEditorFont(font.postScriptName)
            }
        case .ctan(let id):
            guard let preset = LaTeXCatalog.ctanFontPresets.first(where: { $0.id == id }) else { return }
            viewModel.applyCTANFontPreset(preset)
        case .system(let family):
            if uiState.scope == .document {
                viewModel.applySystemFontToDocument(familyName: family, role: uiState.selectedRole, customCommand: "\\\(cleanedMacroName)")
            } else {
                viewModel.selectEditorFont(family)
            }
        }
    }

    private func dismissSheet() {
        viewModel.showFontManagerSheet = false
        dismiss()
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let lock = NSLock()
        var collectedURLs: [URL] = []
        let group = DispatchGroup()

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   url.isFileURL {
                    lock.lock()
                    collectedURLs.append(url)
                    lock.unlock()
                } else if let url = item as? URL, url.isFileURL {
                    lock.lock()
                    collectedURLs.append(url)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            if !collectedURLs.isEmpty {
                viewModel.importCustomFonts(urls: collectedURLs)
            }
        }
        return true
    }

    private func accessibilityDescription(for font: CustomFontRecord, docRoles: [String], editorActive: Bool) -> String {
        var parts: [String] = [font.displayName, "\(font.format.displayBadge) custom font"]
        if font.isMonospace {
            parts.append("monospace")
        }
        if !docRoles.isEmpty {
            parts.append("active as Document \(docRoles.joined(separator: ", "))")
        }
        if editorActive {
            parts.append("active as Editor font")
        }
        return parts.joined(separator: ", ")
    }

    private func postVoiceOverAnnouncement(_ message: String, highPriority: Bool) {
        let priority = highPriority
            ? NSAccessibilityPriorityLevel.high.rawValue
            : NSAccessibilityPriorityLevel.medium.rawValue
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: priority
            ]
        )
    }
}
