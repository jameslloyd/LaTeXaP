import Foundation

public enum DiagnosticSeverity: String, Codable, Sendable, CaseIterable {
    case error = "Error"
    case warning = "Warning"
    case info = "Info"
}

public struct LaTeXDiagnostic: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let line: Int?
    public let severity: DiagnosticSeverity
    public let message: String
    public let rawLine: String

    public init(id: UUID = UUID(), line: Int?, severity: DiagnosticSeverity, message: String, rawLine: String = "") {
        self.id = id
        self.line = line
        self.severity = severity
        self.message = message
        self.rawLine = rawLine
    }
}

public enum CompilationState: Equatable, Sendable {
    case idle
    case compiling(status: String)
    case success(durationMs: Int, pageCount: Int)
    case failed(errorCount: Int)
}

public struct DocumentOutlineItem: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let title: String
    public let level: Int // 1 = section, 2 = subsection, 3 = subsubsection, 4 = expl3 function
    public let line: Int
    public let badge: String
}

public enum OutlineParser {
    public static func parse(source: String) -> [DocumentOutlineItem] {
        var items: [DocumentOutlineItem] = []
        let lines = source.components(separatedBy: .newlines)

        let sectionRegex = try? NSRegularExpression(pattern: #"\\(part|chapter|section|subsection|subsubsection)\*?\{([^}]+)\}"#)
        let cmdRegex = try? NSRegularExpression(pattern: #"\\(NewDocumentCommand|ProvideDocumentCommand|DeclareDocumentCommand|NewExpandableDocumentCommand|cs_new(?:_protected)?:\w+)\s*\{?(\\[a-zA-Z0-9_:@]+)\}?"#)
        let envRegex = try? NSRegularExpression(pattern: #"\\(NewDocumentEnvironment|DeclareDocumentEnvironment)\s*\{([^}]+)\}"#)

        for (index, lineText) in lines.enumerated() {
            let lineNum = index + 1
            let trimmed = lineText.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("%") { continue }

            let nsLine = lineText as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)

            if let match = sectionRegex?.firstMatch(in: lineText, range: fullRange), match.numberOfRanges >= 3 {
                let kind = nsLine.substring(with: match.range(at: 1))
                let title = nsLine.substring(with: match.range(at: 2))
                let level: Int
                switch kind {
                case "part", "chapter", "section": level = 1
                case "subsection": level = 2
                default: level = 3
                }
                items.append(DocumentOutlineItem(title: title, level: level, line: lineNum, badge: kind))
            } else if let match = cmdRegex?.firstMatch(in: lineText, range: fullRange), match.numberOfRanges >= 3 {
                let defType = nsLine.substring(with: match.range(at: 1))
                let cmdName = nsLine.substring(with: match.range(at: 2))
                let badge = defType.hasPrefix("cs_") ? "expl3" : "xparse"
                items.append(DocumentOutlineItem(title: cmdName, level: 2, line: lineNum, badge: badge))
            } else if let match = envRegex?.firstMatch(in: lineText, range: fullRange), match.numberOfRanges >= 3 {
                let envName = nsLine.substring(with: match.range(at: 2))
                items.append(DocumentOutlineItem(title: "\\begin{\(envName)}", level: 2, line: lineNum, badge: "env"))
            }
        }
        return items
    }
}
