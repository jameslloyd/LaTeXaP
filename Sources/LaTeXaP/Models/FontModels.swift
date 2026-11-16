import Foundation

public enum FontFileFormat: String, Codable, Sendable, CaseIterable {
    case ttf
    case otf
    case ttc

    public static func from(url: URL) -> FontFileFormat? {
        FontFileFormat(rawValue: url.pathExtension.lowercased())
    }

    public var fontspecExtension: String {
        ".\(rawValue)"
    }

    public var displayBadge: String {
        rawValue.uppercased()
    }
}

public enum LaTeXFontRole: String, Codable, Sendable, CaseIterable, Identifiable {
    case main
    case sans
    case mono
    case customFamily

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .main: return "Main (Serif)"
        case .sans: return "Sans-Serif"
        case .mono: return "Monospace"
        case .customFamily: return "Custom Family"
        }
    }

    public var latexCommand: String {
        switch self {
        case .main: return "\\setmainfont"
        case .sans: return "\\setsansfont"
        case .mono: return "\\setmonofont"
        case .customFamily: return "\\newfontfamily"
        }
    }
}

public struct CustomFontRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var displayName: String
    public let familyName: String
    public let postScriptName: String
    public let styleName: String
    public let fileName: String
    public let format: FontFileFormat
    public let isMonospace: Bool
    public let fileSizeBytes: Int64
    public let addedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        familyName: String,
        postScriptName: String,
        styleName: String,
        fileName: String,
        format: FontFileFormat,
        isMonospace: Bool,
        fileSizeBytes: Int64,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.familyName = familyName
        self.postScriptName = postScriptName
        self.styleName = styleName
        self.fileName = fileName
        self.format = format
        self.isMonospace = isMonospace
        self.fileSizeBytes = fileSizeBytes
        self.addedAt = addedAt
    }
}

public struct FontLibraryManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var fonts: [CustomFontRecord]

    public init(schemaVersion: Int = 1, fonts: [CustomFontRecord] = []) {
        self.schemaVersion = schemaVersion
        self.fonts = fonts
    }
}

public struct CTANFontPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let packageName: String
    public let options: String
    public let classification: String
    public let description: String
    public let usepackageStatement: String

    public init(
        id: String,
        name: String,
        packageName: String,
        options: String = "",
        classification: String,
        description: String,
        usepackageStatement: String? = nil
    ) {
        self.id = id
        self.name = name
        self.packageName = packageName
        self.options = options
        self.classification = classification
        self.description = description
        if let usepackageStatement {
            self.usepackageStatement = usepackageStatement
        } else if options.isEmpty {
            self.usepackageStatement = "\\usepackage{\(packageName)}"
        } else {
            self.usepackageStatement = "\\usepackage[\(options)]{\(packageName)}"
        }
    }
}

public enum FontImportError: LocalizedError, Equatable, Sendable {
    case unsupportedFormat(String)
    case fileNotFound(String)
    case invalidOrCorruptFont(String)
    case duplicateFont(String)
    case storageFailure(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let extOrName):
            return "Unsupported font format (\(extOrName)). Tectonic (XeTeX) and macOS require .ttf, .otf, or .ttc font files."
        case .fileNotFound(let name):
            return "Font file not found: '\(name)'."
        case .invalidOrCorruptFont(let name):
            return "Could not load '\(name)'. The file appears corrupted, incomplete, or unreadable."
        case .duplicateFont(let name):
            return "Font '\(name)' is already in your custom font library."
        case .storageFailure(let detail):
            return "Storage error: \(detail)"
        }
    }
}
