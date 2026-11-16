import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum CitationPickerFocusField: Hashable {
    case lookupField
    case libraryFilterField
    case pageLocatorField
}

@MainActor
private final class CitationPickerUIState: ObservableObject {
    @Published var libraryFilter: String = ""
    @Published var pageLocator: String = ""
    @Published var selectedEntryKey: String?
    @Published var isDropTargeted: Bool = false
    @Published var lastInsertedFeedback: String?
}

public struct CitationPickerPopoverView: View {
    @ObservedObject var viewModel: DocumentViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiState = CitationPickerUIState()
    @FocusState private var focusedField: CitationPickerFocusField?

    public init(viewModel: DocumentViewModel) {
        self.viewModel = viewModel
    }

    private var filteredEntries: [BibEntry] {
        let q = uiState.libraryFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return viewModel.bibEntries }
        return viewModel.bibEntries.filter {
            $0.key.localizedCaseInsensitiveContains(q)
                || $0.title.localizedCaseInsensitiveContains(q)
                || $0.author.localizedCaseInsensitiveContains(q)
                || $0.year.localizedCaseInsensitiveContains(q)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header + Bibliography Style + Import .bib
            HStack(spacing: 8) {
                Label("Citation Picker", systemImage: "quote.bubble")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Picker("Style", selection: Binding(
                    get: { viewModel.selectedBibliographyStyle },
                    set: { viewModel.applyBibliographyStyle($0) }
                )) {
                    ForEach(BibliographyStylePreset.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .labelsHidden()
                .frame(width: 95)
                .controlSize(.small)
                .accessibilityLabel("Bibliography style")

                Button {
                    viewModel.importBibFileViaPanel()
                } label: {
                    Label(".bib", systemImage: "doc.badge.plus")
                        .font(.caption)
                }
                .controlSize(.small)
                .accessibilityLabel("Import BibTeX file")
                .accessibilityHint("Imports entries from a .bib file")
            }

            // Smart Lookup Input
            HStack(spacing: 6) {
                TextField("DOI, arXiv ID, ISBN, or Paper Title...", text: $viewModel.bibLookupQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .lookupField)
                    .onSubmit {
                        viewModel.searchCrossRefCitations()
                    }
                    .accessibilityLabel("Search CrossRef, DOI, arXiv, or ISBN")

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
                    viewModel.bibLookupQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || viewModel.isSearchingCrossRef
                        || viewModel.isFetchingBib
                )
                .accessibilityLabel("Search citations")
            }

            if let err = viewModel.bibLookupError {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        viewModel.bibLookupError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss citation search error")
                }
                .padding(7)
                .background(Color.red.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onAppear {
                    postAnnouncement(err, highPriority: true)
                }
            }

            // Citation Command Style + Page Locator
            HStack(spacing: 8) {
                Picker("Cite Command", selection: $viewModel.selectedCitationStyle) {
                    ForEach(CitationCommandStyle.allCases) { style in
                        Text(style.command).tag(style)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                .controlSize(.small)
                .accessibilityLabel("Citation command format")

                TextField("Page (e.g. p. 12)", text: $uiState.pageLocator)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .focused($focusedField, equals: .pageLocatorField)
                    .accessibilityLabel("Optional page locator")

                Spacer()

                Text("⇧⌘K")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            // Library Filter
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                TextField("Filter saved citations...", text: $uiState.libraryFilter)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .libraryFilterField)
                    .accessibilityLabel("Filter saved bibliography entries")
                if !uiState.libraryFilter.isEmpty {
                    Button {
                        uiState.libraryFilter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear citation filter")
                }
            }
            .padding(6)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Results & Saved Entries
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if !viewModel.bibSearchResults.isEmpty {
                        Text("ONLINE SEARCH RESULTS (\(viewModel.bibSearchResults.count))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)

                        ForEach(viewModel.bibSearchResults) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(2)
                                    Text("\(entry.author)\(entry.year.isEmpty ? "" : " (\(entry.year))") • \(entry.key)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                VStack(spacing: 4) {
                                    Button("+ Add") {
                                        viewModel.importBibEntry(entry, intoBibFile: true)
                                        postAnnouncement("Added \(entry.key) to bibliography", highPriority: false)
                                    }
                                    .controlSize(.mini)

                                    Button("+ Cite") {
                                        viewModel.importBibEntry(entry, intoBibFile: true)
                                        insertAndDismiss(entry)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.mini)
                                }
                            }
                            .padding(8)
                            .background(Color.accentColor.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    Text("LIBRARY ENTRIES (\(filteredEntries.count))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, viewModel.bibSearchResults.isEmpty ? 0 : 4)
                        .accessibilityAddTraits(.isHeader)

                    if filteredEntries.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "books.vertical")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text(viewModel.bibEntries.isEmpty
                                 ? "No citations yet. Drop a .bib file or search by DOI, arXiv, ISBN, or title above."
                                 : "No citations match '\(uiState.libraryFilter)'.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        ForEach(filteredEntries) { entry in
                            let isUncited = viewModel.preflightReport.uncitedBibKeys.contains(entry.key)
                            let isSelected = uiState.selectedEntryKey == entry.key
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(entry.key)
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(.pink)
                                        if !entry.year.isEmpty {
                                            Text(entry.year)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        if isUncited {
                                            Label("Uncited", systemImage: "exclamationmark.circle.fill")
                                                .font(.system(size: 9.5, weight: .semibold))
                                                .foregroundStyle(.orange)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.orange.opacity(0.14))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    Text(entry.title)
                                        .font(.caption)
                                        .lineLimit(2)
                                    Text(entry.author)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button("Insert") {
                                    insertAndDismiss(entry)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding(8)
                            .background(isSelected ? Color.accentColor.opacity(0.14) : Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                uiState.selectedEntryKey = entry.key
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("\(entry.key), \(entry.title)\(isUncited ? ", currently uncited" : "")")
                            .accessibilityHint("Inserts formatted citation at editor cursor")
                            .accessibilityAction(named: "Insert Citation") {
                                insertAndDismiss(entry)
                            }
                        }
                    }
                }
            }
            .frame(height: 250)
            .onKeyPress(.upArrow) {
                moveSelection(delta: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                moveSelection(delta: 1)
                return .handled
            }
            .onKeyPress(.return) {
                if let key = uiState.selectedEntryKey,
                   let entry = filteredEntries.first(where: { $0.key == key }) {
                    insertAndDismiss(entry)
                    return .handled
                }
                return .ignored
            }
        }
        .padding(14)
        .frame(width: 400)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(uiState.isDropTargeted ? Color.accentColor : Color.clear, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        )
        .onDrop(of: [.fileURL], isTargeted: $uiState.isDropTargeted, perform: handleBibDrop(providers:))
        .onAppear {
            uiState.selectedEntryKey = filteredEntries.first?.key
            focusedField = .lookupField
        }
        .onChange(of: viewModel.bibSearchResults) { _, results in
            if !results.isEmpty {
                postAnnouncement("\(results.count) citation results found", highPriority: false)
            }
        }
        .onKeyPress(.escape) {
            dismissPopover()
            return .handled
        }
    }

    private func insertAndDismiss(_ entry: BibEntry) {
        let trimmedPage = uiState.pageLocator.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.insertFormattedCitation(
            entry,
            style: viewModel.selectedCitationStyle,
            pageLocator: trimmedPage.isEmpty ? nil : trimmedPage
        )
        postAnnouncement("Inserted citation \(entry.key)", highPriority: false)
        dismissPopover()
    }

    private func moveSelection(delta: Int) {
        let items = filteredEntries
        guard !items.isEmpty else { return }
        guard let currentKey = uiState.selectedEntryKey,
              let idx = items.firstIndex(where: { $0.key == currentKey }) else {
            uiState.selectedEntryKey = items.first?.key
            return
        }
        let nextIdx = max(0, min(items.count - 1, idx + delta))
        uiState.selectedEntryKey = items[nextIdx].key
    }

    private func dismissPopover() {
        viewModel.showCitationPickerPopover = false
        dismiss()
    }

    private func handleBibDrop(providers: [NSItemProvider]) -> Bool {
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
            for url in urls where url.pathExtension.lowercased() == "bib" {
                viewModel.handleDroppedBibFileURL(url)
            }
        }
        return true
    }

    private func postAnnouncement(_ message: String, highPriority: Bool) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: (highPriority ? NSAccessibilityPriorityLevel.high : NSAccessibilityPriorityLevel.medium).rawValue
            ]
        )
    }
}
