import Foundation

public struct BibEntry: Identifiable, Equatable, Sendable {
    public var id: String { key }
    public let key: String
    public let entryType: String
    public let title: String
    public let author: String
    public let year: String
    public let rawBibTeX: String

    public init(key: String, entryType: String, title: String, author: String, year: String, rawBibTeX: String = "") {
        self.key = key
        self.entryType = entryType
        self.title = title
        self.author = author
        self.year = year
        self.rawBibTeX = rawBibTeX
    }
}

public struct DocumentLabelItem: Identifiable, Equatable, Sendable {
    public var id: String { "\(label)-\(line)" }
    public let label: String
    public let line: Int
    public let contextPreview: String
}

public enum BibliographyService {
    /// Extracts citations from both inline `\bibitem{...}` in the TeX source and any `.bib` content.
    public static func extractEntries(fromSource source: String, bibFileContent: String = "") -> [BibEntry] {
        var entries: [BibEntry] = []
        var seenKeys = Set<String>()

        // 1. Parse standard BibTeX @article{key, ...} blocks from bibFileContent or filecontents in source
        let combinedBib = bibFileContent + "\n" + source
        if let entryRegex = try? NSRegularExpression(
            pattern: #"@([a-zA-Z]+)\s*\{\s*([^,\s]+)\s*,([\s\S]*?)\n\}"#
        ) {
            let ns = combinedBib as NSString
            let matches = entryRegex.matches(in: combinedBib, range: NSRange(location: 0, length: ns.length))
            for m in matches where m.numberOfRanges >= 4 {
                let type = ns.substring(with: m.range(at: 1)).lowercased()
                if type == "comment" || type == "string" || type == "preamble" { continue }
                let key = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                let body = ns.substring(with: m.range(at: 3))
                let raw = ns.substring(with: m.range)

                let title = extractBibField("title", from: body) ?? "Untitled"
                let author = extractBibField("author", from: body) ?? "Unknown Author"
                let year = extractBibField("year", from: body) ?? ""

                if seenKeys.insert(key).inserted {
                    entries.append(BibEntry(key: key, entryType: type, title: title, author: author, year: year, rawBibTeX: raw))
                }
            }
        }

        // 2. Parse inline \bibitem{key} entries in the TeX source
        let lines = source.components(separatedBy: .newlines)
        if let bibitemRegex = try? NSRegularExpression(pattern: #"\\bibitem(?:\[[^\]]*\])?\{([^}]+)\}"#) {
            for (idx, line) in lines.enumerated() {
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

    private static func extractBibField(_ field: String, from body: String) -> String? {
        let pattern = "(?i)\\b\(field)\\s*=\\s*(?:\\{([^}]*)\\}|\"([^\"]*)\"|(\\d+))"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = body as NSString
        guard let m = regex.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)) else { return nil }
        for group in 1...3 where m.range(at: group).location != NSNotFound {
            return ns.substring(with: m.range(at: group))
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// Extracts all `\label{...}` declarations across the document with their line number and context.
    public static func extractLabels(from source: String) -> [DocumentLabelItem] {
        var results: [DocumentLabelItem] = []
        var seen = Set<String>()
        let lines = source.components(separatedBy: .newlines)
        guard let regex = try? NSRegularExpression(pattern: #"\\label\{([^}]+)\}"#) else { return [] }

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("%") { continue }
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

    /// Fetches a BibTeX entry from a DOI (e.g. `10.1145/3581784`) or an arXiv ID (e.g. `2305.12345`).
    public static func fetchBibTeX(identifier: String) async throws -> BibEntry {
        let cleaned = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://doi.org/", with: "")
            .replacingOccurrences(of: "https://arxiv.org/abs/", with: "")
            .replacingOccurrences(of: "arXiv:", with: "")

        if cleaned.hasPrefix("10.") {
            // DOI content negotiation for application/x-bibtex
            guard let url = URL(string: "https://doi.org/\(cleaned)") else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url)
            request.setValue("application/x-bibtex", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let bibStr = String(data: data, encoding: .utf8),
                  let parsed = extractEntries(fromSource: "", bibFileContent: bibStr).first
            else {
                throw URLError(.cannotParseResponse)
            }
            return parsed
        } else {
            // arXiv API lookup
            guard let url = URL(string: "https://export.arxiv.org/api/query?id_list=\(cleaned)") else {
                throw URLError(.badURL)
            }
            let (data, _) = try await URLSession.shared.data(from: url)
            let xml = String(data: data, encoding: .utf8) ?? ""
            let title = extractXMLTag("title", from: xml, skipFirst: true) ?? "arXiv:\(cleaned)"
            let author = extractXMLTag("name", from: xml, skipFirst: false) ?? "Author"
            let published = extractXMLTag("published", from: xml, skipFirst: false) ?? "2026"
            let year = String(published.prefix(4))
            let firstAuthorLast = author.split(separator: " ").last?.lowercased() ?? "arxiv"
            let key = "\(firstAuthorLast)\(year)arxiv"
            let raw = """
@article{\(key),
  author = {\(author)},
  title = {\(title)},
  journal = {arXiv preprint arXiv:\(cleaned)},
  year = {\(year)}
}
"""
            return BibEntry(key: key, entryType: "article", title: title, author: author, year: year, rawBibTeX: raw)
        }
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
