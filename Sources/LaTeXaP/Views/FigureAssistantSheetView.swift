import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum FigureAssistantFocusField: Hashable {
    case choosePrimaryButton
    case captionField
    case labelField
}

@MainActor
private final class FigureAssistantUIState: ObservableObject {
    @Published var primaryURL: URL?
    @Published var secondaryURL: URL?
    @Published var isSubfigureMode: Bool = false
    @Published var widthFraction: Double = 0.75
    @Published var placement: String = "htbp"
    @Published var caption: String = ""
    @Published var label: String = "fig:figure"
    @Published var primarySubcaption: String = "Condition A"
    @Published var secondarySubcaption: String = "Condition B"
    @Published var validationErrorMessage: String?

    private static let allowedExtensions: Set<String> = ["png", "jpg", "jpeg", "pdf", "tiff", "tif"]

    init(droppedURL: URL?) {
        if let droppedURL {
            switch Self.validateImageAssetURL(droppedURL) {
            case .success(let validated):
                self.primaryURL = validated
                let stem = validated.deletingPathExtension().lastPathComponent
                self.caption = "Figure showing \(stem.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " "))."
                self.label = Self.makeSafeLabel(from: stem)
            case .failure(let err):
                self.primaryURL = nil
                self.validationErrorMessage = err.localizedDescription
            }
        }
    }

    enum AssetValidationError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self {
            case .message(let text): return text
            }
        }
    }

    static func validateImageAssetURL(_ url: URL) -> Result<URL, AssetValidationError> {
        guard url.isFileURL else {
            return .failure(.message("Only local image files are supported."))
        }
        let ext = url.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            return .failure(.message("Unsupported image format '.\(ext)'. Use PNG, JPG, PDF, or TIFF."))
        }
        let standardized = url.standardizedFileURL
        let linkVals = try? standardized.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard linkVals?.isSymbolicLink != true else {
            return .failure(.message("Symbolic links cannot be imported as figure assets."))
        }
        let resolved = standardized.resolvingSymlinksInPath()
        let vals = try? resolved.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard vals?.isRegularFile == true, vals?.isSymbolicLink != true else {
            return .failure(.message("Selected figure path must be a regular non-symlink file."))
        }
        let fileSize = Int64(vals?.fileSize ?? 0)
        guard fileSize > 0 && fileSize <= SubmissionExportService.maxAssetBytes else {
            return .failure(.message("Figure file exceeds the 50 MB size safety limit or is empty."))
        }
        return .success(resolved)
    }

    static func makeSafeLabel(from stem: String) -> String {
        let lower = stem.lowercased()
        let allowed = lower.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII {
                return Character(scalar)
            }
            return "-"
        }
        let collapsed = String(allowed).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "fig:\(collapsed.isEmpty ? "figure" : collapsed)"
    }
}

public struct FigureAssistantSheetView: View {
    @ObservedObject var viewModel: DocumentViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiState: FigureAssistantUIState
    @FocusState private var focusedField: FigureAssistantFocusField?

    public init(viewModel: DocumentViewModel) {
        self.viewModel = viewModel
        self._uiState = StateObject(wrappedValue: FigureAssistantUIState(droppedURL: viewModel.pendingDroppedFigureURL))
    }

    private var labelValidationError: String? {
        let trimmed = uiState.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Label cannot be empty."
        }
        if trimmed.range(of: #"^[A-Za-z0-9:_-]+$"#, options: .regularExpression) == nil {
            return "Label may contain only letters, digits, ':', '_', or '-' (no spaces)."
        }
        return nil
    }

    private var isInsertDisabled: Bool {
        uiState.primaryURL == nil || labelValidationError != nil
    }

    private var previewLaTeX: String {
        let primaryName = uiState.primaryURL.map { "figures/\(AcademicSanitizer.sanitizeFigureFileName($0.lastPathComponent))" } ?? "figures/image.png"
        let secondaryName: String? = (uiState.isSubfigureMode && uiState.secondaryURL != nil)
            ? "figures/\(AcademicSanitizer.sanitizeFigureFileName(uiState.secondaryURL!.lastPathComponent))"
            : nil
        let config = FigureInsertConfig(
            primaryRelativePath: primaryName,
            secondaryRelativePath: secondaryName,
            widthFraction: uiState.widthFraction,
            placement: uiState.placement,
            caption: uiState.caption.isEmpty ? "Figure caption." : uiState.caption,
            label: uiState.label.trimmingCharacters(in: .whitespacesAndNewlines),
            primarySubcaption: uiState.primarySubcaption,
            secondarySubcaption: uiState.secondarySubcaption
        )
        return AcademicToolsGenerator.generateFigureSnippet(from: config)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Figure Assistant", systemImage: "photo.badge.plus")
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
                .accessibilityLabel("Close Figure Assistant")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let err = uiState.validationErrorMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button {
                                uiState.validationErrorMessage = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Dismiss validation error")
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if viewModel.currentFileURL == nil {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Document is unsaved — image will be staged in temporary figures/ for live preview and migrated into figures/ when you save your .tex file.")
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Primary Image Card + Preview
                    HStack(alignment: .top, spacing: 14) {
                        imageThumbnailView(url: uiState.primaryURL)
                            .frame(width: 130, height: 100)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                            )

                        VStack(alignment: .leading, spacing: 8) {
                            Text("PRIMARY FIGURE ASSET")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)

                            if let url = uiState.primaryURL {
                                Text(url.lastPathComponent)
                                    .font(.callout.weight(.semibold))
                                    .lineLimit(1)
                                Text(imageDimensionsText(for: url))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("No image selected yet")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            Button(uiState.primaryURL == nil ? "Choose Image..." : "Change Image...") {
                                pickImage { url in
                                    uiState.primaryURL = url
                                    let stem = url.deletingPathExtension().lastPathComponent
                                    if uiState.caption.isEmpty {
                                        uiState.caption = "Figure showing \(stem.replacingOccurrences(of: "_", with: " "))."
                                    }
                                    uiState.label = FigureAssistantUIState.makeSafeLabel(from: stem)
                                }
                            }
                            .controlSize(.small)
                            .focused($focusedField, equals: .choosePrimaryButton)
                            .accessibilityLabel("Choose primary figure image")
                        }
                        Spacer()
                    }

                    // Layout Mode
                    Picker("Layout Mode", selection: $uiState.isSubfigureMode) {
                        Text("Single Figure").tag(false)
                        Text("Side-by-Side (2 Subfigures)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Figure layout mode")

                    if uiState.isSubfigureMode {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Left Subcaption")
                                    .font(.caption.weight(.medium))
                                TextField("Condition A", text: $uiState.primarySubcaption)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Right Subfigure Image & Subcaption")
                                    .font(.caption.weight(.medium))
                                HStack(spacing: 6) {
                                    Button(uiState.secondaryURL?.lastPathComponent ?? "Choose Second Image...") {
                                        pickImage { url in
                                            uiState.secondaryURL = url
                                        }
                                    }
                                    .controlSize(.small)

                                    TextField("Condition B", text: $uiState.secondarySubcaption)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Width & Placement
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Width")
                                    .font(.caption.weight(.medium))
                                Spacer()
                                Text("\(Int(uiState.widthFraction * 100))% of \\textwidth")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $uiState.widthFraction, in: 0.25...1.0, step: 0.05)
                                .accessibilityLabel("Figure width percentage")
                                .accessibilityValue("\(Int(uiState.widthFraction * 100)) percent of text width")
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Placement")
                                .font(.caption.weight(.medium))
                            Picker("Placement", selection: $uiState.placement) {
                                Text("Here [htbp]").tag("htbp")
                                Text("Top [t]").tag("t")
                                Text("Bottom [b]").tag("b")
                                Text("Page [p]").tag("p")
                            }
                            .labelsHidden()
                            .frame(width: 130)
                        }
                    }

                    // Caption & Label
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Caption")
                                .font(.caption.weight(.medium))
                            TextField("Descriptive caption for your figure...", text: $uiState.caption)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .captionField)
                                .accessibilityLabel("Figure caption")
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cross-Reference Label")
                                .font(.caption.weight(.medium))
                            TextField("fig:my-figure", text: $uiState.label)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                                .focused($focusedField, equals: .labelField)
                                .accessibilityLabel("Figure label")
                                .accessibilityValue(labelValidationError ?? uiState.label)

                            if let err = labelValidationError {
                                Label(err, systemImage: "xmark.octagon.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    // Live LaTeX Preview
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GENERATED LATEX SNIPPET")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(previewLaTeX)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .textSelection(.enabled)
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Button("Cancel") {
                    closeSheet()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Insert Figure") {
                    guard let primaryURL = uiState.primaryURL, labelValidationError == nil else { return }
                    let relativePrimary = "figures/\(AcademicSanitizer.sanitizeFigureFileName(primaryURL.lastPathComponent))"
                    let relativeSecondary = (uiState.isSubfigureMode && uiState.secondaryURL != nil)
                        ? "figures/\(AcademicSanitizer.sanitizeFigureFileName(uiState.secondaryURL!.lastPathComponent))"
                        : nil
                    let config = FigureInsertConfig(
                        primaryRelativePath: relativePrimary,
                        secondaryRelativePath: relativeSecondary,
                        widthFraction: uiState.widthFraction,
                        placement: uiState.placement,
                        caption: uiState.caption.isEmpty ? "Figure caption." : uiState.caption,
                        label: uiState.label.trimmingCharacters(in: .whitespacesAndNewlines),
                        primarySubcaption: uiState.primarySubcaption,
                        secondarySubcaption: uiState.secondarySubcaption
                    )
                    viewModel.insertFigureWithConfig(
                        sourceURL: primaryURL,
                        secondaryURL: uiState.isSubfigureMode ? uiState.secondaryURL : nil,
                        config: config
                    )
                    closeSheet()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInsertDisabled)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 590, height: 520)
        .onAppear {
            focusedField = (uiState.primaryURL == nil) ? .choosePrimaryButton : .captionField
        }
    }

    @ViewBuilder
    private func imageThumbnailView(url: URL?) -> some View {
        if let url,
           case .success(let validURL) = FigureAssistantUIState.validateImageAssetURL(url),
           let image = NSImage(contentsOf: validURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(4)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Preview")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func imageDimensionsText(for url: URL) -> String {
        if case .success(let validURL) = FigureAssistantUIState.validateImageAssetURL(url),
           let rep = NSImageRep(contentsOf: validURL) {
            return "\(rep.pixelsWide) × \(rep.pixelsHigh) px • \(validURL.pathExtension.uppercased())"
        }
        return url.pathExtension.uppercased()
    }

    private func pickImage(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Select Figure Image or PDF"
        panel.allowedContentTypes = [.png, .jpeg, .pdf, .tiff]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            switch FigureAssistantUIState.validateImageAssetURL(url) {
            case .success(let validated):
                uiState.validationErrorMessage = nil
                completion(validated)
            case .failure(let err):
                uiState.validationErrorMessage = err.localizedDescription
            }
        }
    }

    private func closeSheet() {
        viewModel.pendingDroppedFigureURL = nil
        viewModel.showFigureAssistantSheet = false
        dismiss()
    }
}
