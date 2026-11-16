import Darwin
import Foundation

public struct BibEntry: Identifiable, Equatable, Sendable {
    public var id: String { key }
    public let key: String
    public let entryType: String
    public let title: String
    public let author: String
    public let year: String
    public let venue: String
    public let doi: String
    public let rawBibTeX: String

    public init(
        key: String,
        entryType: String,
        title: String,
        author: String,
        year: String,
        venue: String = "",
        doi: String = "",
        rawBibTeX: String = ""
    ) {
        self.key = key
        self.entryType = entryType
        self.title = title
        self.author = author
        self.year = year
        self.venue = venue
        self.doi = doi
        self.rawBibTeX = rawBibTeX
    }
}

public struct DocumentLabelItem: Identifiable, Equatable, Sendable {
    public var id: String { "\(label)-\(line)" }
    public let label: String
    public let line: Int
    public let contextPreview: String

    public init(label: String, line: Int, contextPreview: String) {
        self.label = label
        self.line = line
        self.contextPreview = contextPreview
    }
}

public struct DocumentCitationUse: Equatable, Sendable {
    public let key: String
    public let line: Int
}

public struct DocumentReferenceUse: Equatable, Sendable {
    public let label: String
    public let line: Int
}

public enum BibTeXError: LocalizedError, Sendable {
    case invalidFileURL(String)
    case fileTooLarge(Int64)
    case unreadableFile(String)
    case syntaxError(line: Int, message: String)
    case invalidNetworkURL
    case networkFailure(String)
    case noResultsFound

    public var errorDescription: String? {
        switch self {
        case .invalidFileURL(let msg):
            return msg
        case .fileTooLarge(let bytes):
            let mb = Double(bytes) / (1024 * 1024)
            return String(format: "BibTeX file is %.1f MB, exceeding the 10 MB safety limit.", mb)
        case .unreadableFile(let msg):
            return msg
        case .syntaxError(let line, let msg):
            return "Could not parse BibTeX on line \(line): \(msg)"
        case .invalidNetworkURL:
            return "Invalid or unsafe URL for citation lookup."
        case .networkFailure(let msg):
            return msg
        case .noResultsFound:
            return "No matching academic citations were found."
        }
    }
}

public enum BibliographyService {
    public static let maxBibFileSizeBytes: Int64 = 10 * 1024 * 1024
    public static let maxNetworkResponseBytes: Int = 2 * 1024 * 1024

    // MARK: - Extraction (TeX Source + .bib Content)

    /// Extracts citations from both inline `\bibitem{...}` in the TeX source and any `.bib` content.
    public static func extractEntries(fromSource source: String, bibFileContent: String = "") -> [BibEntry] {
        var entries: [BibEntry] = []
        var seenKeys = Set<String>()

        // 1. Parse standard BibTeX @article{key, ...} blocks from bibFileContent and source (balanced braces)
        let combinedBib = bibFileContent + "\n" + source
        if let parsedBib = try? parseBibContent(combinedBib, strict: false) {
            for entry in parsedBib {
                if seenKeys.insert(entry.key).inserted {
                    entries.append(entry)
                }
            }
        }

        // 2. Parse inline \bibitem{key} entries in the TeX source
        let lines = source.components(separatedBy: .newlines)
        if let bibitemRegex = try? NSRegularExpression(pattern: #"\\bibitem(?:\[[^\]]*\])?\{([^}]+)\}"#) {
            for (idx, line) in lines.enumerated() {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("%") { continue }
                let ns = line as NSString
                if let match = bibitemRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                   match.numberOfRanges >= 2 {
                    let key = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                    let nextLine = (idx + 1 < lines.count) ? lines[idx + 1].trimmingCharacters(in: .whitespaces) : ""
                    let cleanSummary = nextLine
                        .replacingOccurrences(of: "\\emph{", with: "")
                        .replacingOccurrences(of: "``", with: "\"")
                        .replacingOccurrences(of: "''", with: "\"")
                        .replacingOccurrences(of: "~", with: " ")
                        .replacingOccurrences(of: "}", with: "")
                    let yearMatch = cleanSummary.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression).map { String(cleanSummary[$0]) } ?? ""
                    if seenKeys.insert(key).inserted {
                        entries.append(
                            BibEntry(
                                key: key,
                                entryType: "bibitem",
                                title: cleanSummary.isEmpty ? key : cleanSummary,
                                author: "Inline Reference",
                                year: yearMatch,
                                rawBibTeX: "\\bibitem{\(key)}\n\(nextLine)"
                            )
                        )
                    }
                }
            }
        }

        return entries
    }

    /// Extracts all `\cite`, `\parencite`, `\textcite`, `\autocite`, `\footcite`, `\citep`, `\citet` citation uses.
    public static func extractCitations(from source: String) -> [DocumentCitationUse] {
        var uses: [DocumentCitationUse] = []
        let lines = source.components(separatedBy: .newlines)
        guard let regex = try? NSRegularExpression(
            pattern: #"\\(?:cite|parencite|textcite|autocite|footcite|citep|citet|citealp|citealt|nocite)\*?(?:\[[^\]]*\])*\{([^}]+)\}"#
        ) else {
            return uses
        }

        for (idx, rawLine) in lines.enumerated() {
            let line = stripTrailingComment(rawLine)
            let ns = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
            for m in matches where m.numberOfRanges >= 2 {
                let rawArg = ns.substring(with: m.range(at: 1))
                for part in rawArg.split(separator: ",") {
                    let key = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !key.isEmpty {
                        uses.append(DocumentCitationUse(key: key, line: idx + 1))
                    }
                }
            }
        }
        return uses
    }

    /// Extracts all `\ref`, `\eqref`, `\cref`, `\Cref`, `\autoref`, `\pageref` cross-reference uses.
    public static func extractReferences(from source: String) -> [DocumentReferenceUse] {
        var uses: [DocumentReferenceUse] = []
        let lines = source.components(separatedBy: .newlines)
        guard let regex = try? NSRegularExpression(
            pattern: #"\\(?:ref|eqref|cref|Cref|autoref|pageref|vref)\*?\{([^}]+)\}"#
        ) else {
            return uses
        }

        for (idx, rawLine) in lines.enumerated() {
            let line = stripTrailingComment(rawLine)
            let ns = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
            for m in matches where m.numberOfRanges >= 2 {
                let rawArg = ns.substring(with: m.range(at: 1))
                for part in rawArg.split(separator: ",") {
                    let label = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !label.isEmpty {
                        uses.append(DocumentReferenceUse(label: label, line: idx + 1))
                    }
                }
            }
        }
        return uses
    }

    /// Extracts all `\label{...}` declarations across the document with their line number and context.
    public static func extractLabels(from source: String) -> [DocumentLabelItem] {
        var results: [DocumentLabelItem] = []
        var seen = Set<String>()
        let lines = source.components(separatedBy: .newlines)
        guard let regex = try? NSRegularExpression(pattern: #"\\label\{([^}]+)\}"#) else { return [] }

        for (idx, rawLine) in lines.enumerated() {
            let line = stripTrailingComment(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let ns = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
            for m in matches where m.numberOfRanges >= 2 {
                let label = ns.substring(with: m.range(at: 1))
                if seen.insert(label).inserted {
                    let context = trimmed.replacingOccurrences(of: "\\label{\(label)}", with: "").trimmingCharacters(in: .whitespaces)
                    results.append(
                        DocumentLabelItem(
                            label: label,
                            line: idx + 1,
                            contextPreview: context.isEmpty ? "Line \(idx + 1)" : context
                        )
                    )
                }
            }
        }
        return results
    }

    /// Extracts referenced `.bib` filenames from `\addbibresource{...}` or `\bibliography{...}`.
    public static func extractReferencedBibFiles(from source: String) -> [String] {
        var files: [String] = []
        let lines = source.components(separatedBy: .newlines)
        guard let regex = try? NSRegularExpression(
            pattern: #"\\(?:addbibresource|bibliography)(?:\[[^\]]*\])?\{([^}]+)\}"#
        ) else {
            return files
        }
        for rawLine in lines {
            let line = stripTrailingComment(rawLine)
            let ns = line as NSString
            for m in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges >= 2 {
                let rawArg = ns.substring(with: m.range(at: 1))
                for part in rawArg.split(separator: ",") {
                    var name = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { continue }
                    if !name.lowercased().hasSuffix(".bib") {
                        name += ".bib"
                    }
                    if !files.contains(name) {
                        files.append(name)
                    }
                }
            }
        }
        return files
    }

    // MARK: - Safe .bib File Parsing & Merging

    public static func parseBibFile(at url: URL) throws -> [BibEntry] {
        guard url.isFileURL else {
            throw BibTeXError.invalidFileURL("Only local .bib files can be imported.")
        }
        let standardized = url.standardizedFileURL
        let linkValues = try? standardized.resourceValues(forKeys: [.isSymbolicLinkKey])
        if linkValues?.isSymbolicLink == true {
            throw BibTeXError.invalidFileURL("BibTeX file '\(standardized.lastPathComponent)' cannot be a symbolic link.")
        }
        let resolved = standardized.resolvingSymlinksInPath()
        let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
            throw BibTeXError.invalidFileURL("BibTeX source '\(standardized.lastPathComponent)' must be a regular file.")
        }
        let size = Int64(values?.fileSize ?? 0)
        if size > maxBibFileSizeBytes {
            throw BibTeXError.fileTooLarge(size)
        }
        let data: Data
        do {
            data = try Data(contentsOf: resolved)
        } catch {
            throw BibTeXError.unreadableFile("Unable to read '\(standardized.lastPathComponent)': \(error.localizedDescription)")
        }
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw BibTeXError.unreadableFile("'\(standardized.lastPathComponent)' is not a valid UTF-8 or Latin-1 BibTeX file.")
        }
        return try parseBibContent(content, strict: true)
    }

    /// Balanced-brace BibTeX parser that preserves nested `{...}` and reports exact line numbers on syntax errors.
    public static func parseBibContent(_ content: String, strict: Bool = true) throws -> [BibEntry] {
        var entries: [BibEntry] = []
        let chars = Array(content)
        let n = chars.count
        var i = 0
        var line = 1

        while i < n {
            let ch = chars[i]
            if ch == "\n" {
                line += 1
                i += 1
                continue
            }
            if ch == "%" {
                while i < n && chars[i] != "\n" { i += 1 }
                continue
            }
            guard ch == "@" else {
                i += 1
                continue
            }

            let entryStartIdx = i
            let entryStartLine = line
            i += 1

            // Read entry type
            var typeStr = ""
            while i < n && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                typeStr.append(chars[i])
                i += 1
            }
            let lowerType = typeStr.lowercased()
            guard !lowerType.isEmpty else {
                if strict {
                    throw BibTeXError.syntaxError(line: entryStartLine, message: "Expected entry type after '@'.")
                }
                continue
            }

            // Skip whitespace before opening { or (
            while i < n && (chars[i] == " " || chars[i] == "\t" || chars[i] == "\r" || chars[i] == "\n") {
                if chars[i] == "\n" { line += 1 }
                i += 1
            }
            guard i < n, chars[i] == "{" || chars[i] == "(" else {
                if strict {
                    throw BibTeXError.syntaxError(line: entryStartLine, message: "Expected '{' after '@\(typeStr)'.")
                }
                continue
            }

            let openDelim = chars[i]
            let closeDelim: Character = (openDelim == "{") ? "}" : ")"
            var depth = 1
            var inQuotes = false
            i += 1
            let bodyStart = i

            while i < n && depth > 0 {
                let c = chars[i]
                if c == "\n" { line += 1 }
                if c == "\\" && i + 1 < n {
                    if chars[i + 1] == "\n" { line += 1 }
                    i += 2
                    continue
                }
                if c == "\"" && depth == 1 {
                    inQuotes.toggle()
                } else if !inQuotes {
                    if c == openDelim {
                        depth += 1
                    } else if c == closeDelim {
                        depth -= 1
                        if depth == 0 {
                            break
                        }
                    }
                }
                i += 1
            }

            guard depth == 0 else {
                if strict {
                    throw BibTeXError.syntaxError(line: entryStartLine, message: "Unclosed '@\(typeStr)' entry (missing '\(closeDelim)').")
                }
                break
            }

            let bodyEnd = i
            let raw = String(chars[entryStartIdx...bodyEnd])
            i += 1

            if lowerType == "comment" || lowerType == "string" || lowerType == "preamble" {
                continue
            }

            let inner = String(chars[bodyStart..<bodyEnd])
            guard let commaIdx = inner.firstIndex(of: ",") else {
                if strict {
                    throw BibTeXError.syntaxError(line: entryStartLine, message: "Missing comma after citation key in '@\(typeStr)'.")
                }
                continue
            }

            let rawKey = String(inner[..<commaIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = AcademicSanitizer.sanitizeIdentifier(rawKey, fallback: "")
            guard !key.isEmpty else {
                if strict {
                    throw BibTeXError.syntaxError(line: entryStartLine, message: "Empty citation key in '@\(typeStr)'.")
                }
                continue
            }

            let fieldsBody = String(inner[inner.index(after: commaIdx)...])
            let fields = parseBibFields(fieldsBody)

            let title = cleanBibFieldValue(fields["title"]) ?? "Untitled"
            let author = cleanBibFieldValue(fields["author"] ?? fields["editor"]) ?? "Unknown Author"
            let year = cleanBibFieldValue(fields["year"] ?? fields["date"])?.prefix(4).description ?? ""
            let venue = cleanBibFieldValue(fields["journal"] ?? fields["booktitle"] ?? fields["publisher"]) ?? ""
            let doi = cleanBibFieldValue(fields["doi"]) ?? ""

            entries.append(
                BibEntry(
                    key: key,
                    entryType: lowerType,
                    title: title,
                    author: author,
                    year: year,
                    venue: venue,
                    doi: doi,
                    rawBibTeX: raw
                )
            )
        }

        return entries
    }

    public static func formatBibTeX(entry: BibEntry) -> String {
        let safeKey = AcademicSanitizer.sanitizeIdentifier(entry.key, fallback: "ref")
        let safeType = AcademicSanitizer.sanitizeIdentifier(entry.entryType.lowercased(), fallback: "article")
        if !entry.rawBibTeX.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
           entry.rawBibTeX.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@") {
            return entry.rawBibTeX.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var lines = ["@\(safeType){\(safeKey),"]
        lines.append("  author = {\(AcademicSanitizer.sanitizeExternalMetadata(entry.author, fallback: "Unknown Author"))},")
        lines.append("  title = {\(AcademicSanitizer.sanitizeExternalMetadata(entry.title, fallback: "Untitled"))},")
        if !entry.venue.isEmpty {
            let fieldName = (safeType == "inproceedings") ? "booktitle" : "journal"
            lines.append("  \(fieldName) = {\(AcademicSanitizer.sanitizeExternalMetadata(entry.venue))},")
        }
        if !entry.year.isEmpty {
            lines.append("  year = {\(AcademicSanitizer.sanitizeIdentifier(entry.year, fallback: "2026"))},")
        }
        if !entry.doi.isEmpty {
            lines.append("  doi = {\(AcademicSanitizer.sanitizeCitationLocator(entry.doi))},")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    public static func uniqueCitationKey(base rawBase: String, existingKeys: Set<String>) -> String {
        let base = AcademicSanitizer.sanitizeIdentifier(rawBase, fallback: "ref")
        if !existingKeys.contains(base) {
            return base
        }
        var suffix = 2
        while existingKeys.contains("\(base)\(suffix)") {
            suffix += 1
        }
        return "\(base)\(suffix)"
    }

    /// Merges new entries into a `.bib` file string with deduplication and key-collision safety.
    public static func mergeEntries(
        _ newEntries: [BibEntry],
        intoExistingBibContent existingContent: String,
        replaceDuplicates: Bool = false
    ) -> (mergedContent: String, addedKeys: [String], duplicateKeys: [String]) {
        var existingEntries = (try? parseBibContent(existingContent, strict: false)) ?? []
        var existingKeys = Set(existingEntries.map(\.key))
        var addedKeys: [String] = []
        var duplicateKeys: [String] = []

        for entry in newEntries {
            let safeKey = AcademicSanitizer.sanitizeIdentifier(entry.key, fallback: "ref")
            if existingKeys.contains(safeKey) {
                duplicateKeys.append(safeKey)
                if replaceDuplicates, let idx = existingEntries.firstIndex(where: { $0.key == safeKey }) {
                    existingEntries[idx] = entry
                } else if !replaceDuplicates {
                    // Rename with deterministic unique suffix if keeping both
                    let newKey = uniqueCitationKey(base: safeKey, existingKeys: existingKeys)
                    existingKeys.insert(newKey)
                    let updatedRaw = rewriteBibKey(in: formatBibTeX(entry: entry), to: newKey)
                    let renamed = BibEntry(
                        key: newKey,
                        entryType: entry.entryType,
                        title: entry.title,
                        author: entry.author,
                        year: entry.year,
                        venue: entry.venue,
                        doi: entry.doi,
                        rawBibTeX: updatedRaw
                    )
                    existingEntries.append(renamed)
                    addedKeys.append(newKey)
                }
            } else {
                existingKeys.insert(safeKey)
                let formattedEntry = entry.rawBibTeX.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@")
                    ? entry
                    : BibEntry(
                        key: safeKey,
                        entryType: entry.entryType,
                        title: entry.title,
                        author: entry.author,
                        year: entry.year,
                        venue: entry.venue,
                        doi: entry.doi,
                        rawBibTeX: formatBibTeX(entry: entry)
                    )
                existingEntries.append(formattedEntry)
                addedKeys.append(safeKey)
            }
        }

        let merged = existingEntries
            .map { formatBibTeX(entry: $0) }
            .joined(separator: "\n\n")
        return (mergedContent: merged.isEmpty ? "" : merged + "\n", addedKeys: addedKeys, duplicateKeys: duplicateKeys)
    }

    // MARK: - Network Lookup (Smart Query, CrossRef, DOI, arXiv, ISBN, URL)

    /// Unified academic citation lookup: detects DOI, arXiv ID, ISBN, URL, or CrossRef keyword/title search.
    public static func smartLookup(query rawQuery: String) async throws -> [BibEntry] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        // 1. Direct DOI
        if isDOIQuery(query) {
            let entry = try await fetchBibTeX(identifier: query)
            return [entry]
        }

        // 2. Direct arXiv ID or arXiv URL
        if isArXivQuery(query) {
            let entry = try await fetchBibTeX(identifier: query)
            return [entry]
        }

        // 3. Direct ISBN-10 / ISBN-13
        if let cleanISBN = extractValidISBN(from: query) {
            let entry = try await fetchByISBN(cleanISBN)
            return [entry]
        }

        // 4. Web URL
        if query.lowercased().hasPrefix("http://") || query.lowercased().hasPrefix("https://") {
            let entry = try await fetchByURL(query)
            return [entry]
        }

        // 5. CrossRef keyword / title search (up to 5 matches)
        return try await searchCrossRef(query: query, rows: 5)
    }

    /// Searches CrossRef Works API by paper title, author, or keywords.
    public static func searchCrossRef(query: String, rows: Int = 5) async throws -> [BibEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let clampedRows = min(max(rows, 1), 10)
        var components = URLComponents(string: "https://api.crossref.org/works")!
        components.queryItems = [
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "rows", value: String(clampedRows))
        ]
        guard let url = components.url else {
            throw BibTeXError.invalidNetworkURL
        }

        var request = URLRequest(url: url)
        request.setValue("LaTeXaP/0.2.0 (mailto:support@latexap.app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        let (data, response) = try await fetchBoundedData(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw BibTeXError.networkFailure("CrossRef returned HTTP \(http.statusCode).")
        }

        let decoded = try parseCrossRefWorksJSON(data)
        if decoded.isEmpty {
            throw BibTeXError.noResultsFound
        }
        return decoded
    }

    /// Parses CrossRef `/works` JSON payload into sanitized `BibEntry` records (exposed for unit testing).
    public static func parseCrossRefWorksJSON(_ data: Data) throws -> [BibEntry] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any],
              let items = message["items"] as? [[String: Any]] else {
            return []
        }

        var entries: [BibEntry] = []
        var usedKeys = Set<String>()

        for item in items {
            let rawTitle = (item["title"] as? [String])?.first ?? "Untitled"
            let cleanTitle = AcademicSanitizer.sanitizeExternalMetadata(rawTitle, fallback: "Untitled")

            let authorsArray = item["author"] as? [[String: Any]] ?? []
            let authorNames: [String] = authorsArray.compactMap { author in
                let given = (author["given"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let family = (author["family"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let combined = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
                return combined.isEmpty ? nil : AcademicSanitizer.sanitizeExternalMetadata(combined)
            }
            let authorText = authorNames.isEmpty ? "Unknown Author" : authorNames.joined(separator: " and ")

            let firstFamily = (authorsArray.first?["family"] as? String) ?? "ref"
            let year = extractCrossRefYear(from: item) ?? "2026"
            let rawVenue = (item["container-title"] as? [String])?.first ?? (item["publisher"] as? String) ?? ""
            let cleanVenue = AcademicSanitizer.sanitizeExternalMetadata(rawVenue)
            let rawDOI = (item["DOI"] as? String) ?? ""
            let cleanDOI = AcademicSanitizer.sanitizeCitationLocator(rawDOI)

            let crType = (item["type"] as? String) ?? "journal-article"
            let bibType: String
            switch crType {
            case "proceedings-article": bibType = "inproceedings"
            case "book", "monograph": bibType = "book"
            case "book-chapter": bibType = "incollection"
            case "posted-content": bibType = "misc"
            default: bibType = "article"
            }

            let titleToken = cleanTitle
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .first { $0.count >= 4 } ?? "paper"
            let baseKey = AcademicSanitizer.sanitizeIdentifier("\(firstFamily.lowercased())\(year)\(titleToken)", fallback: "ref\(year)")
            let uniqueKey = uniqueCitationKey(base: baseKey, existingKeys: usedKeys)
            usedKeys.insert(uniqueKey)

            var rawLines = ["@\(bibType){\(uniqueKey),"]
            rawLines.append("  author = {\(authorText)},")
            rawLines.append("  title = {\(cleanTitle)},")
            if !cleanVenue.isEmpty {
                let venueField = (bibType == "inproceedings") ? "booktitle" : "journal"
                rawLines.append("  \(venueField) = {\(cleanVenue)},")
            }
            rawLines.append("  year = {\(AcademicSanitizer.sanitizeIdentifier(year, fallback: "2026"))},")
            if !cleanDOI.isEmpty {
                rawLines.append("  doi = {\(cleanDOI)},")
            }
            rawLines.append("}")

            entries.append(
                BibEntry(
                    key: uniqueKey,
                    entryType: bibType,
                    title: cleanTitle,
                    author: authorText,
                    year: year,
                    venue: cleanVenue,
                    doi: cleanDOI,
                    rawBibTeX: rawLines.joined(separator: "\n")
                )
            )
        }
        return entries
    }

    public static func fetchByISBN(_ rawISBN: String) async throws -> BibEntry {
        guard let isbn = extractValidISBN(from: rawISBN) else {
            throw BibTeXError.invalidNetworkURL
        }
        var components = URLComponents(string: "https://openlibrary.org/api/books")!
        components.queryItems = [
            URLQueryItem(name: "bibkeys", value: "ISBN:\(isbn)"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "jscmd", value: "data")
        ]
        guard let url = components.url else { throw BibTeXError.invalidNetworkURL }

        var request = URLRequest(url: url)
        request.setValue("LaTeXaP/0.2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, _) = try await fetchBoundedData(for: request)
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let book = root["ISBN:\(isbn)"] as? [String: Any] {
            let rawTitle = (book["title"] as? String) ?? "Book (\(isbn))"
            let title = AcademicSanitizer.sanitizeExternalMetadata(rawTitle, fallback: "Book")
            let authorList = (book["authors"] as? [[String: Any]] ?? [])
                .compactMap { $0["name"] as? String }
                .map { AcademicSanitizer.sanitizeExternalMetadata($0) }
                .filter { !$0.isEmpty }
            let author = authorList.isEmpty ? "Unknown Author" : authorList.joined(separator: " and ")
            let publishDate = (book["publish_date"] as? String) ?? ""
            let year = publishDate.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression)
                .map { String(publishDate[$0]) } ?? "2026"
            let publisher = ((book["publishers"] as? [[String: Any]])?.first?["name"] as? String) ?? ""
            let cleanPublisher = AcademicSanitizer.sanitizeExternalMetadata(publisher)

            let firstLast = (authorList.first?.split(separator: " ").last.map(String.init) ?? "book").lowercased()
            let key = AcademicSanitizer.sanitizeIdentifier("\(firstLast)\(year)isbn", fallback: "book\(year)")
            var lines = [
                "@book{\(key),",
                "  author = {\(author)},",
                "  title = {\(title)},",
                "  year = {\(year)},"
            ]
            if !cleanPublisher.isEmpty {
                lines.append("  publisher = {\(cleanPublisher)},")
            }
            lines.append("  isbn = {\(isbn)},")
            lines.append("}")

            return BibEntry(
                key: key,
                entryType: "book",
                title: title,
                author: author,
                year: year,
                venue: cleanPublisher,
                rawBibTeX: lines.joined(separator: "\n")
            )
        }

        // Fallback: query CrossRef by ISBN if OpenLibrary lacked metadata
        if let crHit = try? await searchCrossRef(query: isbn, rows: 1).first {
            return crHit
        }
        throw BibTeXError.noResultsFound
    }

    public static func fetchByURL(_ urlString: String) async throws -> BibEntry {
        guard let url = validatedExternalWebURL(urlString) else {
            throw BibTeXError.invalidNetworkURL
        }
        var request = URLRequest(url: url)
        request.setValue("LaTeXaP/0.2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, _) = try await fetchBoundedData(for: request)
        let html = String(data: data.prefix(256 * 1024), encoding: .utf8) ?? ""
        var extractedTitle = url.host ?? "Web Resource"
        if let regex = try? NSRegularExpression(pattern: #"(?is)<title[^>]*>(.*?)</title>"#),
           let m = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)),
           m.numberOfRanges >= 2 {
            let raw = (html as NSString).substring(with: m.range(at: 1))
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                extractedTitle = trimmed
            }
        }
        let cleanTitle = AcademicSanitizer.sanitizeExternalMetadata(extractedTitle, fallback: "Web Resource")
        let cleanHost = AcademicSanitizer.sanitizeExternalMetadata(url.host ?? "Online Source")
        let year = String(Calendar.current.component(.year, from: Date()))
        let key = AcademicSanitizer.sanitizeIdentifier("\((url.host ?? "web").replacingOccurrences(of: ".", with: "_"))\(year)", fallback: "web\(year)")
        let safeURL = AcademicSanitizer.sanitizeCitationLocator(url.absoluteString)
        let raw = """
@misc{\(key),
  author = {{\(cleanHost)}},
  title = {\(cleanTitle)},
  year = {\(year)},
  howpublished = {\\url{\(safeURL)}}
}
"""
        return BibEntry(key: key, entryType: "misc", title: cleanTitle, author: cleanHost, year: year, venue: url.host ?? "", rawBibTeX: raw)
    }

    /// Reconstructs a `BibEntry` retrieved from an external network source with every field and
    /// `rawBibTeX` sanitized via `AcademicSanitizer` (never passing raw untrusted `.bib` verbatim).
    public static func sanitizeNetworkEntry(_ entry: BibEntry) -> BibEntry {
        let safeKey = AcademicSanitizer.sanitizeIdentifier(entry.key, fallback: "ref")
        let safeType = AcademicSanitizer.sanitizeIdentifier(entry.entryType.lowercased(), fallback: "article")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let allowedTypes: Set<String> = ["article", "inproceedings", "book", "incollection", "misc", "phdthesis", "mastersthesis", "techreport"]
        let finalType = allowedTypes.contains(safeType) ? safeType : "article"

        let safeTitle = AcademicSanitizer.sanitizeExternalMetadata(entry.title, fallback: "Untitled")
        let safeAuthor = AcademicSanitizer.sanitizeExternalMetadata(entry.author, fallback: "Unknown Author")
        let safeYear = AcademicSanitizer.sanitizeIdentifier(String(entry.year.prefix(4)), fallback: "2026")
        let safeVenue = AcademicSanitizer.sanitizeExternalMetadata(entry.venue)
        let safeDOI = AcademicSanitizer.sanitizeCitationLocator(entry.doi)

        let base = BibEntry(
            key: safeKey,
            entryType: finalType,
            title: safeTitle,
            author: safeAuthor,
            year: safeYear,
            venue: safeVenue,
            doi: safeDOI,
            rawBibTeX: ""
        )
        let reconstructedRaw = formatBibTeX(entry: base)
        return BibEntry(
            key: safeKey,
            entryType: finalType,
            title: safeTitle,
            author: safeAuthor,
            year: safeYear,
            venue: safeVenue,
            doi: safeDOI,
            rawBibTeX: reconstructedRaw
        )
    }

    /// Fetches a BibTeX entry from a DOI (e.g. `10.1145/3581784`) or an arXiv ID (e.g. `2305.12345`).
    public static func fetchBibTeX(identifier: String) async throws -> BibEntry {
        let cleaned = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://doi.org/", with: "")
            .replacingOccurrences(of: "http://doi.org/", with: "")
            .replacingOccurrences(of: "doi:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "https://arxiv.org/abs/", with: "")
            .replacingOccurrences(of: "https://arxiv.org/pdf/", with: "")
            .replacingOccurrences(of: ".pdf", with: "")
            .replacingOccurrences(of: "arXiv:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.hasPrefix("10.") {
            guard cleaned.range(of: #"^10\.\d{4,9}/[^\s\r\n?#]+$"#, options: .regularExpression) != nil,
                  !cleaned.contains("..") else {
                throw BibTeXError.invalidNetworkURL
            }
            var components = URLComponents()
            components.scheme = "https"
            components.host = "doi.org"
            components.path = "/" + cleaned
            guard let url = components.url else {
                throw BibTeXError.invalidNetworkURL
            }
            var request = URLRequest(url: url)
            request.setValue("application/x-bibtex", forHTTPHeaderField: "Accept")
            request.setValue("LaTeXaP/0.2.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10
            let (data, _) = try await fetchBoundedData(for: request)
            guard let bibStr = String(data: data, encoding: .utf8),
                  let parsed = extractEntries(fromSource: "", bibFileContent: bibStr).first
            else {
                throw URLError(.cannotParseResponse)
            }
            return sanitizeNetworkEntry(parsed)
        } else {
            guard cleaned.range(of: #"^(?:\d{4}\.\d{4,5}|[a-zA-Z\-]+(?:\.[a-zA-Z\-]+)?/\d{7})(?:v\d+)?$"#, options: .regularExpression) != nil else {
                throw BibTeXError.invalidNetworkURL
            }
            var components = URLComponents()
            components.scheme = "https"
            components.host = "export.arxiv.org"
            components.path = "/api/query"
            components.queryItems = [URLQueryItem(name: "id_list", value: cleaned)]
            guard let url = components.url else {
                throw BibTeXError.invalidNetworkURL
            }
            var request = URLRequest(url: url)
            request.setValue("LaTeXaP/0.2.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10
            let (data, _) = try await fetchBoundedData(for: request)
            let xml = String(data: data, encoding: .utf8) ?? ""
            let rawTitle = extractXMLTag("title", from: xml, skipFirst: true) ?? "arXiv:\(cleaned)"
            let rawAuthor = extractXMLTag("name", from: xml, skipFirst: false) ?? "Author"
            let title = AcademicSanitizer.sanitizeExternalMetadata(rawTitle, fallback: "arXiv Paper")
            let author = AcademicSanitizer.sanitizeExternalMetadata(rawAuthor, fallback: "Author")
            let published = extractXMLTag("published", from: xml, skipFirst: false) ?? "2026"
            let year = AcademicSanitizer.sanitizeIdentifier(String(published.prefix(4)), fallback: "2026")
            let firstAuthorLast = author.split(separator: " ").last.map(String.init)?.lowercased() ?? "arxiv"
            let key = AcademicSanitizer.sanitizeIdentifier("\(firstAuthorLast)\(year)arxiv", fallback: "arxiv\(year)")
            let safeArxivID = AcademicSanitizer.sanitizeIdentifier(cleaned, fallback: "unknown")
            let raw = """
@article{\(key),
  author = {\(author)},
  title = {\(title)},
  journal = {arXiv preprint arXiv:\(safeArxivID)},
  year = {\(year)}
}
"""
            return BibEntry(key: key, entryType: "article", title: title, author: author, year: year, venue: "arXiv:\(safeArxivID)", rawBibTeX: raw)
        }
    }

    // MARK: - Private Helpers

    private static func stripTrailingComment(_ rawLine: String) -> String {
        if let commentRange = rawLine.range(of: #"(?<!\\)%.*$"#, options: .regularExpression) {
            return String(rawLine[..<commentRange.lowerBound])
        }
        return rawLine
    }

    private static func parseBibFields(_ body: String) -> [String: String] {
        var fields: [String: String] = [:]
        let chars = Array(body)
        let n = chars.count
        var i = 0

        while i < n {
            while i < n && (chars[i].isWhitespace || chars[i] == ",") { i += 1 }
            guard i < n else { break }

            // Field name
            var name = ""
            while i < n && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_" || chars[i] == "-") {
                name.append(chars[i])
                i += 1
            }
            let lowerName = name.lowercased()
            while i < n && chars[i].isWhitespace { i += 1 }
            guard i < n, chars[i] == "=" else {
                while i < n && chars[i] != "," && chars[i] != "\n" { i += 1 }
                continue
            }
            i += 1 // skip '='
            while i < n && chars[i].isWhitespace { i += 1 }
            guard i < n else { break }

            var value = ""
            if chars[i] == "{" {
                var depth = 1
                i += 1
                while i < n && depth > 0 {
                    let c = chars[i]
                    if c == "\\" && i + 1 < n {
                        value.append(c)
                        value.append(chars[i + 1])
                        i += 2
                        continue
                    }
                    if c == "{" { depth += 1 }
                    else if c == "}" {
                        depth -= 1
                        if depth == 0 {
                            i += 1
                            break
                        }
                    }
                    value.append(c)
                    i += 1
                }
            } else if chars[i] == "\"" {
                var braceDepth = 0
                i += 1
                while i < n {
                    let c = chars[i]
                    if c == "\\" && i + 1 < n {
                        value.append(c)
                        value.append(chars[i + 1])
                        i += 2
                        continue
                    }
                    if c == "{" { braceDepth += 1 }
                    else if c == "}" && braceDepth > 0 { braceDepth -= 1 }
                    else if c == "\"" && braceDepth == 0 {
                        i += 1
                        break
                    }
                    value.append(c)
                    i += 1
                }
            } else {
                while i < n && chars[i] != "," && chars[i] != "\n" {
                    value.append(chars[i])
                    i += 1
                }
            }

            if !lowerName.isEmpty {
                fields[lowerName] = value
            }
        }
        return fields
    }

    private static func cleanBibFieldValue(_ raw: String?) -> String? {
        guard var s = raw?.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else {
            return nil
        }
        // Collapse repeated spaces and outer protective braces while keeping valid text
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        if s.hasPrefix("{") && s.hasSuffix("}") && s.count >= 2 {
            s = String(s.dropFirst().dropLast())
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rewriteBibKey(in rawBib: String, to newKey: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"^(@[a-zA-Z]+\s*\{\s*)([^,\s]+)(\s*,)"#) else {
            return rawBib
        }
        let ns = rawBib as NSString
        return regex.stringByReplacingMatches(
            in: rawBib,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: "$1\(newKey)$3"
        )
    }

    private static func extractCrossRefYear(from item: [String: Any]) -> String? {
        for field in ["published-print", "published-online", "published", "issued", "created"] {
            if let dict = item[field] as? [String: Any],
               let dateParts = dict["date-parts"] as? [[Int]],
               let firstYear = dateParts.first?.first {
                return String(firstYear)
            }
        }
        return nil
    }

    private static func isDOIQuery(_ query: String) -> Bool {
        let lower = query.lowercased()
        if lower.hasPrefix("10.") && query.contains("/") && !query.contains(" ") {
            return true
        }
        if (lower.hasPrefix("https://doi.org/") || lower.hasPrefix("http://doi.org/") || lower.hasPrefix("doi:10.")) && !query.contains(" ") {
            return true
        }
        return false
    }

    private static func isArXivQuery(_ query: String) -> Bool {
        let lower = query.lowercased()
        if lower.hasPrefix("arxiv:") || lower.contains("arxiv.org/abs/") || lower.contains("arxiv.org/pdf/") {
            return true
        }
        return query.range(of: #"^\d{4}\.\d{4,5}(?:v\d+)?$"#, options: .regularExpression) != nil
    }

    public static func extractValidISBN(from raw: String) -> String? {
        var working = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = working.lowercased()
        let explicitPrefix = lower.hasPrefix("isbn")
        if explicitPrefix {
            working = working
                .replacingOccurrences(of: "isbn:", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "isbn", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let compact = working.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        guard compact.range(of: #"^(?:\d{9}[\dXx]|\d{13})$"#, options: .regularExpression) != nil else {
            return nil
        }
        if compact.count == 13 && !compact.hasPrefix("978") && !compact.hasPrefix("979") && !explicitPrefix {
            return nil
        }
        return compact.uppercased()
    }

    private final class RedirectValidatingSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            if let nextURL = request.url,
               BibliographyService.validatedExternalWebURL(nextURL.absoluteString) != nil {
                completionHandler(request)
            } else {
                completionHandler(nil)
            }
        }
    }

    private static func fetchBoundedData(
        for request: URLRequest,
        maxBytes: Int = maxNetworkResponseBytes
    ) async throws -> (Data, URLResponse) {
        guard let reqURL = request.url,
              validatedExternalWebURL(reqURL.absoluteString) != nil else {
            throw BibTeXError.invalidNetworkURL
        }

        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let delegate = RedirectValidatingSessionDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (bytes, response) = try await session.bytes(for: request)
        if let finalURL = response.url,
           validatedExternalWebURL(finalURL.absoluteString) == nil {
            throw BibTeXError.invalidNetworkURL
        }

        let expectedLength = response.expectedContentLength
        if expectedLength > Int64(maxBytes) {
            throw BibTeXError.networkFailure("Network response exceeds the \(maxBytes / (1024 * 1024)) MB safety limit.")
        }

        var data = Data()
        if expectedLength > 0 {
            data.reserveCapacity(min(Int(expectedLength), 256 * 1024))
        }
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxBytes {
                throw BibTeXError.networkFailure("Network response exceeded the \(maxBytes / (1024 * 1024)) MB safety limit.")
            }
        }
        return (data, response)
    }

    public static func validatedExternalWebURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.user == nil,
              url.password == nil,
              let rawHost = url.host?.lowercased(),
              !rawHost.isEmpty else {
            return nil
        }

        if let port = url.port, port != 80 && port != 443 {
            return nil
        }

        var host = rawHost
        if host.hasPrefix("[") && host.hasSuffix("]") && host.count >= 2 {
            host = String(host.dropFirst().dropLast())
        }
        if let zoneIdx = host.firstIndex(of: "%") {
            host = String(host[..<zoneIdx])
        }
        while host.hasSuffix(".") {
            host.removeLast()
        }
        guard !host.isEmpty else { return nil }

        // Reject localhost and reserved internal/local TLDs
        if host == "localhost" ||
           host.hasSuffix(".localhost") ||
           host.hasSuffix(".local") ||
           host.hasSuffix(".internal") ||
           host.hasSuffix(".arpa") ||
           host.hasSuffix(".localdomain") {
            return nil
        }

        // Check IPv4 literals via inet_pton (rejects loopback, RFC1918, CGNAT, link-local, multicast, unspecified)
        var addr4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &addr4) }) == 1 {
            let ip = UInt32(bigEndian: addr4.s_addr)
            return isDisallowedIPv4(ip) ? nil : url
        }

        // Check IPv6 literals via inet_pton (rejects ::, ::1, fe80::/10, fec0::/10, fc00::/7, ff00::/8, ::ffff:...)
        var addr6 = in6_addr()
        if host.withCString({ inet_pton(AF_INET6, $0, &addr6) }) == 1 {
            let bytes = withUnsafeBytes(of: addr6.__u6_addr.__u6_addr8) { Array($0) }
            guard bytes.count == 16 else { return nil }

            let isAllZero = bytes.allSatisfy { $0 == 0 }
            let isLoopback = bytes[0..<15].allSatisfy { $0 == 0 } && bytes[15] == 1
            let isLinkLocal = bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 // fe80::/10
            let isSiteLocal = bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0xC0 // fec0::/10
            let isULA = (bytes[0] & 0xFE) == 0xFC                            // fc00::/7
            let isMulticast = bytes[0] == 0xFF                               // ff00::/8

            if isAllZero || isLoopback || isLinkLocal || isSiteLocal || isULA || isMulticast {
                return nil
            }

            // ::ffff:0:0/96 (IPv4-mapped IPv6) or ::0:0/96 (IPv4-compatible IPv6)
            let isIPv4Mapped = bytes[0..<10].allSatisfy { $0 == 0 } && bytes[10] == 0xFF && bytes[11] == 0xFF
            let isIPv4Compat = bytes[0..<12].allSatisfy { $0 == 0 }
            if isIPv4Mapped || isIPv4Compat {
                let mappedIP = (UInt32(bytes[12]) << 24) |
                               (UInt32(bytes[13]) << 16) |
                               (UInt32(bytes[14]) << 8) |
                               UInt32(bytes[15])
                if isDisallowedIPv4(mappedIP) {
                    return nil
                }
            }

            return url
        }

        // For non-IP DNS hostnames, require at least one dot (reject single-label internal hostnames and integer IPs)
        guard host.contains(".") else {
            return nil
        }

        return url
    }

    private static func isDisallowedIPv4(_ ip: UInt32) -> Bool {
        if (ip & 0xFF00_0000) == 0x0000_0000 { return true } // 0.0.0.0/8 ("this network")
        if (ip & 0xFF00_0000) == 0x0A00_0000 { return true } // 10.0.0.0/8 (RFC 1918)
        if (ip & 0xFFC0_0000) == 0x6440_0000 { return true } // 100.64.0.0/10 (CGNAT)
        if (ip & 0xFF00_0000) == 0x7F00_0000 { return true } // 127.0.0.0/8 (loopback)
        if (ip & 0xFFFF_0000) == 0xA9FE_0000 { return true } // 169.254.0.0/16 (link-local / cloud metadata)
        if (ip & 0xFFF0_0000) == 0xAC10_0000 { return true } // 172.16.0.0/12 (RFC 1918)
        if (ip & 0xFFFF_0000) == 0xC0A8_0000 { return true } // 192.168.0.0/16 (RFC 1918)
        if (ip & 0xFFFE_0000) == 0xC612_0000 { return true } // 198.18.0.0/15 (benchmarking)
        if ip >= 0xE000_0000 { return true }                 // 224.0.0.0/4 multicast + 240.0.0.0/4 reserved + broadcast
        return false
    }

    private static func extractXMLTag(_ tag: String, from xml: String, skipFirst: Bool) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<\(tag)>([\\s\\S]*?)</\(tag)>") else { return nil }
        let ns = xml as NSString
        let matches = regex.matches(in: xml, range: NSRange(location: 0, length: ns.length))
        let targetIndex = skipFirst ? 1 : 0
        guard matches.count > targetIndex, matches[targetIndex].numberOfRanges >= 2 else { return nil }
        return ns.substring(with: matches[targetIndex].range(at: 1))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
