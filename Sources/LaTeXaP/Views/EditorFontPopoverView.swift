import AppKit
import SwiftUI

@MainActor
private final class EditorFontPopoverState: ObservableObject {
    @Published var showProportionalCustomFonts: Bool = false
    @Published var filterText: String = ""
}

public struct EditorFontPopoverView: View {
    @ObservedObject var viewModel: DocumentViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiState = EditorFontPopoverState()

    public init(viewModel: DocumentViewModel) {
        self.viewModel = viewModel
    }

    private var customMonospaceFonts: [CustomFontRecord] {
        viewModel.customFonts.filter { $0.isMonospace }
    }

    private var customProportionalFonts: [CustomFontRecord] {
        viewModel.customFonts.filter { !$0.isMonospace }
    }

    private var systemMonospaceFonts: [String] {
        let customPostScripts = Set(viewModel.customFonts.map(\.postScriptName))
        let customFamilies = Set(viewModel.customFonts.map(\.familyName))
        return viewModel.availableEditorFontNames.filter { name in
            !name.isEmpty && !customPostScripts.contains(name) && !customFamilies.contains(name)
        }
    }

    private var isDefaultConfig: Bool {
        viewModel.editorFontName.isEmpty && abs(viewModel.editorFontSize - 13.5) < 0.01
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Code Editor Typography", systemImage: "textformat.size")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Button("Reset") {
                    viewModel.resetEditorFontToDefault()
                }
                .controlSize(.small)
                .disabled(isDefaultConfig)
                .accessibilityLabel("Reset editor font to default")
                .accessibilityHint("Restores System Monospaced font at 13.5 points")
            }

            // Editing Pane Theme (Light / Dark)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Editing Pane Theme")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.useLightEditorBackground ? "Light" : "Dark")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Button {
                        viewModel.useLightEditorBackground = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(viewModel.useLightEditorBackground ? Color.orange : Color.secondary)
                            Text("Light Theme")
                                .font(.system(size: 11.5, weight: viewModel.useLightEditorBackground ? .semibold : .medium))
                                .foregroundStyle(viewModel.useLightEditorBackground ? Color.primary : Color.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    viewModel.useLightEditorBackground
                                        ? Color.accentColor.opacity(0.18)
                                        : Color(NSColor.textBackgroundColor).opacity(0.5)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    viewModel.useLightEditorBackground
                                        ? Color.accentColor.opacity(0.65)
                                        : Color.secondary.opacity(0.22),
                                    lineWidth: 1
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Light editing pane theme")
                    .accessibilityValue(viewModel.useLightEditorBackground ? "Selected" : "Not selected")

                    Button {
                        viewModel.useLightEditorBackground = false
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(!viewModel.useLightEditorBackground ? Color.cyan : Color.secondary)
                            Text("Dark Theme")
                                .font(.system(size: 11.5, weight: !viewModel.useLightEditorBackground ? .semibold : .medium))
                                .foregroundStyle(!viewModel.useLightEditorBackground ? Color.primary : Color.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    !viewModel.useLightEditorBackground
                                        ? Color.accentColor.opacity(0.18)
                                        : Color(NSColor.textBackgroundColor).opacity(0.5)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    !viewModel.useLightEditorBackground
                                        ? Color.accentColor.opacity(0.65)
                                        : Color.secondary.opacity(0.22),
                                    lineWidth: 1
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dark editing pane theme")
                    .accessibilityValue(!viewModel.useLightEditorBackground ? "Selected" : "Not selected")
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Font size controls
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Font Size")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f pt", viewModel.editorFontSize))
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                }

                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.editorFontSize) },
                            set: { viewModel.editorFontSize = CGFloat($0) }
                        ),
                        in: 10...24,
                        step: 0.5
                    )
                    .accessibilityLabel("Editor font size")
                    .accessibilityValue("\(String(format: "%.1f", viewModel.editorFontSize)) points")

                    Stepper(
                        "",
                        value: Binding(
                            get: { Double(viewModel.editorFontSize) },
                            set: { viewModel.editorFontSize = CGFloat(max(10, min(24, $0))) }
                        ),
                        in: 10...24,
                        step: 0.5
                    )
                    .labelsHidden()
                    .accessibilityLabel("Step editor font size")
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Mini live preview
            VStack(alignment: .leading, spacing: 4) {
                Text("PREVIEW")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("\\NewDocumentCommand{\\vec}{ m }{\\mathbf{#1}}")
                    .font(Font(LaTeXSyntaxHighlighter.resolveFont(
                        name: viewModel.editorFontName,
                        size: min(16, max(11, viewModel.editorFontSize)),
                        weight: .regular
                    )))
                    .foregroundStyle(
                        viewModel.useLightEditorBackground
                            ? Color(red: 0.06, green: 0.09, blue: 0.16)
                            : Color(red: 0.94, green: 0.96, blue: 0.99)
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        viewModel.useLightEditorBackground
                            ? Color.white
                            : Color(red: 0.05, green: 0.07, blue: 0.09)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Live editor font preview")
            .accessibilityValue(viewModel.editorFontName.isEmpty ? "System Monospaced" : viewModel.editorFontName)

            // Search filter
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter editor fonts...", text: $uiState.filterText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Filter editor fonts")
                if !uiState.filterText.isEmpty {
                    Button {
                        uiState.filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear font filter")
                }
            }
            .padding(7)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Font List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if uiState.filterText.isEmpty || "system monospaced default".localizedCaseInsensitiveContains(uiState.filterText) {
                        fontRow(
                            title: "System Monospaced",
                            subtitle: "Default macOS SF Mono",
                            badge: "Default",
                            isSelected: viewModel.editorFontName.isEmpty,
                            previewFontName: ""
                        ) {
                            viewModel.selectEditorFont("")
                        }
                    }

                    let filteredCustomMono = customMonospaceFonts.filter {
                        uiState.filterText.isEmpty ||
                        $0.displayName.localizedCaseInsensitiveContains(uiState.filterText) ||
                        $0.postScriptName.localizedCaseInsensitiveContains(uiState.filterText)
                    }
                    if !filteredCustomMono.isEmpty {
                        sectionHeader("CUSTOM MONOSPACE FONTS")
                        ForEach(filteredCustomMono) { font in
                            fontRow(
                                title: font.displayName,
                                subtitle: font.styleName,
                                badge: font.format.displayBadge,
                                isSelected: viewModel.editorFontName == font.postScriptName || viewModel.editorFontName == font.familyName,
                                previewFontName: font.postScriptName
                            ) {
                                viewModel.selectEditorFont(font.postScriptName)
                            }
                        }
                    }

                    if uiState.showProportionalCustomFonts {
                        let filteredProportional = customProportionalFonts.filter {
                            uiState.filterText.isEmpty ||
                            $0.displayName.localizedCaseInsensitiveContains(uiState.filterText) ||
                            $0.postScriptName.localizedCaseInsensitiveContains(uiState.filterText)
                        }
                        if !filteredProportional.isEmpty {
                            sectionHeader("CUSTOM PROPORTIONAL FONTS")
                            ForEach(filteredProportional) { font in
                                fontRow(
                                    title: font.displayName,
                                    subtitle: font.styleName,
                                    badge: font.format.displayBadge,
                                    isSelected: viewModel.editorFontName == font.postScriptName,
                                    previewFontName: font.postScriptName
                                ) {
                                    viewModel.selectEditorFont(font.postScriptName)
                                }
                            }
                        }
                    }

                    let filteredSysMono = systemMonospaceFonts.filter {
                        uiState.filterText.isEmpty || $0.localizedCaseInsensitiveContains(uiState.filterText)
                    }
                    if !filteredSysMono.isEmpty {
                        sectionHeader("SYSTEM MONOSPACE FONTS")
                        ForEach(filteredSysMono, id: \.self) { name in
                            fontRow(
                                title: name,
                                subtitle: nil,
                                badge: "System",
                                isSelected: viewModel.editorFontName == name,
                                previewFontName: name
                            ) {
                                viewModel.selectEditorFont(name)
                            }
                        }
                    }
                }
            }
            .frame(height: 190)

            if !customProportionalFonts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Show proportional custom fonts", isOn: $uiState.showProportionalCustomFonts)
                        .font(.caption)

                    if uiState.showProportionalCustomFonts {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Proportional fonts may misalign code columns and inline ghost completions.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Divider()

            HStack {
                Button {
                    dismiss()
                    viewModel.showFontManagerSheet = true
                } label: {
                    Label("Manage & Add Fonts...", systemImage: "textformat")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Manage and add fonts")
                .accessibilityHint("Opens the full Font Manager sheet")

                Spacer()

                Text("⇧⌘F")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 6)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func fontRow(
        title: String,
        subtitle: String?,
        badge: String,
        isSelected: Bool,
        previewFontName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                    .font(.system(size: 13))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Font(LaTeXSyntaxHighlighter.resolveFont(name: previewFontName, size: 12.5, weight: .regular)))
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(badge)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(badge)")
        .accessibilityValue(isSelected ? "Active editor font" : "")
        .accessibilityHint("Selects \(title) as the code editor font")
    }
}
