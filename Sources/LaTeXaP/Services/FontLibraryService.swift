import CoreText
import CryptoKit
import Foundation

public final class FontLibraryService: @unchecked Sendable {
    public static let maxImportFileSizeBytes: Int64 = 64 * 1024 * 1024

    public let fontsDirectory: URL
    public let manifestURL: URL

    private let lock = NSLock()

    public init(storageDirectory: URL? = nil) {
        let baseDir: URL
        if let storageDirectory {
            baseDir = storageDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            baseDir = appSupport
                .appendingPathComponent("LaTeXaP", isDirectory: true)
                .appendingPathComponent("Fonts", isDirectory: true)
        }
        self.fontsDirectory = baseDir.standardizedFileURL
        self.manifestURL = self.fontsDirectory.appendingPathComponent("fonts.json").standardizedFileURL
        try? FileManager.default.createDirectory(at: self.fontsDirectory, withIntermediateDirectories: true)
    }

    public func loadManifest() throws -> [CustomFontRecord] {
        lock.lock()
        defer { lock.unlock() }
        return try loadManifestUnlocked()
    }

    public func importFont(from sourceURL: URL, displayName: String? = nil) throws -> CustomFontRecord {
        guard sourceURL.isFileURL else {
            throw FontImportError.storageFailure("Only local file URLs can be imported.")
        }

        let standardizedSource = sourceURL.standardizedFileURL
        guard let format = FontFileFormat.from(url: standardizedSource) else {
            let ext = standardizedSource.pathExtension.isEmpty ? "unknown" : ".\(standardizedSource.pathExtension.lowercased())"
            throw FontImportError.unsupportedFormat(ext)
        }

        let sourceLinkValues = try? standardizedSource.resourceValues(forKeys: [.isSymbolicLinkKey])
        if sourceLinkValues?.isSymbolicLink == true {
            throw FontImportError.storageFailure("Font source '\(standardizedSource.lastPathComponent)' cannot be a symbolic link.")
        }

        let resolvedSource = standardizedSource.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedSource.path, isDirectory: &isDir), !isDir.boolValue else {
            throw FontImportError.fileNotFound(standardizedSource.lastPathComponent)
        }

        let resourceValues = try? resolvedSource.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard resourceValues?.isRegularFile == true, resourceValues?.isSymbolicLink != true else {
            throw FontImportError.storageFailure("Font source '\(standardizedSource.lastPathComponent)' must be a regular file.")
        }

        let preflightSize = Int64(resourceValues?.fileSize ?? 0)
        guard preflightSize > 0 else {
            throw FontImportError.invalidOrCorruptFont(standardizedSource.lastPathComponent)
        }
        guard preflightSize <= Self.maxImportFileSizeBytes else {
            throw FontImportError.storageFailure("Font file '\(standardizedSource.lastPathComponent)' exceeds the 64 MB maximum size limit.")
        }

        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(resolvedSource as CFURL) as? [CTFontDescriptor],
              let firstDescriptor = descriptors.first else {
            throw FontImportError.invalidOrCorruptFont(standardizedSource.lastPathComponent)
        }

        let rawFamily = (CTFontDescriptorCopyAttribute(firstDescriptor, kCTFontFamilyNameAttribute) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawPostScript = (CTFontDescriptorCopyAttribute(firstDescriptor, kCTFontNameAttribute) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawStyle = (CTFontDescriptorCopyAttribute(firstDescriptor, kCTFontStyleNameAttribute) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard (rawFamily?.isEmpty == false) || (rawPostScript?.isEmpty == false) else {
            throw FontImportError.invalidOrCorruptFont(standardizedSource.lastPathComponent)
        }

        let fallbackBase = standardizedSource.deletingPathExtension().lastPathComponent
        let familyName = (rawFamily?.isEmpty == false ? rawFamily : nil) ?? fallbackBase
        let postScriptName = (rawPostScript?.isEmpty == false ? rawPostScript : nil) ?? familyName
        let styleName = (rawStyle?.isEmpty == false ? rawStyle : nil) ?? "Regular"

        let ctFont = CTFontCreateWithFontDescriptor(firstDescriptor, 12.0, nil)
        let symbolicTraits = CTFontGetSymbolicTraits(ctFont)
        let isMonospace = symbolicTraits.contains(.traitMonoSpace)

        let sourceData: Data
        do {
            sourceData = try Data(contentsOf: resolvedSource)
        } catch {
            throw FontImportError.storageFailure("Unable to read '\(standardizedSource.lastPathComponent)': \(error.localizedDescription)")
        }

        guard !sourceData.isEmpty else {
            throw FontImportError.invalidOrCorruptFont(standardizedSource.lastPathComponent)
        }
        guard Int64(sourceData.count) <= Self.maxImportFileSizeBytes else {
            throw FontImportError.storageFailure("Font file '\(standardizedSource.lastPathComponent)' exceeds the 64 MB maximum size limit.")
        }

        let fileSizeBytes = Int64(sourceData.count)
        let sourceDigest = SHA256.hash(data: sourceData)

        lock.lock()
        defer { lock.unlock() }

        try ensureFontsDirectoryExistsUnlocked()
        var records = try loadManifestUnlocked()

        // Duplicate detection: exact postScriptName + fileSizeBytes OR identical SHA-256 of stored binary
        for existing in records {
            if existing.postScriptName == postScriptName && existing.fileSizeBytes == fileSizeBytes {
                throw FontImportError.duplicateFont(existing.displayName)
            }
            if existing.fileSizeBytes == fileSizeBytes {
                let existingURL = safeFontFileURL(forFileName: existing.fileName)
                if let existingData = try? Data(contentsOf: existingURL),
                   SHA256.hash(data: existingData) == sourceDigest {
                    throw FontImportError.duplicateFont(existing.displayName)
                }
            }
        }

        // Safe filename sanitization (prevents path traversal and TeX-unsafe characters)
        let baseSanitized = Self.sanitizeBaseFileName(standardizedSource.deletingPathExtension().lastPathComponent)
        var candidateFileName = "\(baseSanitized).\(format.rawValue)"
        var destURL = safeFontFileURL(forFileName: candidateFileName)

        if FileManager.default.fileExists(atPath: destURL.path) || records.contains(where: { $0.fileName == candidateFileName }) {
            let shortSuffix = String(UUID().uuidString.prefix(8)).lowercased()
            candidateFileName = "\(baseSanitized)-\(shortSuffix).\(format.rawValue)"
            destURL = safeFontFileURL(forFileName: candidateFileName)
        }

        guard destURL.deletingLastPathComponent().standardizedFileURL == fontsDirectory else {
            throw FontImportError.storageFailure("Invalid destination path outside managed Fonts directory.")
        }

        do {
            try sourceData.write(to: destURL, options: [.atomic])
        } catch {
            throw FontImportError.storageFailure("Failed to copy font binary: \(error.localizedDescription)")
        }

        let resolvedDisplayName: String
        if let provided = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !provided.isEmpty {
            resolvedDisplayName = provided
        } else if styleName.caseInsensitiveCompare("Regular") == .orderedSame {
            resolvedDisplayName = familyName
        } else {
            resolvedDisplayName = "\(familyName) \(styleName)"
        }

        let record = CustomFontRecord(
            id: UUID(),
            displayName: resolvedDisplayName,
            familyName: familyName,
            postScriptName: postScriptName,
            styleName: styleName,
            fileName: candidateFileName,
            format: format,
            isMonospace: isMonospace,
            fileSizeBytes: fileSizeBytes,
            addedAt: Date()
        )

        records.append(record)
        do {
            try saveManifestUnlocked(records)
        } catch {
            try? FileManager.default.removeItem(at: destURL)
            throw error
        }

        _ = registerURLInProcess(destURL)
        return record
    }

    public func renameFont(id: UUID, newDisplayName: String) throws -> CustomFontRecord {
        let trimmed = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FontImportError.storageFailure("Font display name cannot be empty.")
        }

        lock.lock()
        defer { lock.unlock() }

        var records = try loadManifestUnlocked()
        guard let idx = records.firstIndex(where: { $0.id == id }) else {
            throw FontImportError.fileNotFound(id.uuidString)
        }

        records[idx].displayName = trimmed
        try saveManifestUnlocked(records)
        return records[idx]
    }

    public func deleteFont(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        var records = try loadManifestUnlocked()
        guard let idx = records.firstIndex(where: { $0.id == id }) else {
            throw FontImportError.fileNotFound(id.uuidString)
        }

        let record = records[idx]
        if let validLeaf = Self.validatedManifestFileName(record.fileName) {
            let fileURL = fontsDirectory.appendingPathComponent(validLeaf).standardizedFileURL
            let resolvedDir = fontsDirectory.resolvingSymlinksInPath()
            let resolvedFile = fileURL.resolvingSymlinksInPath()

            unregisterURLInProcess(fileURL)

            if resolvedFile.deletingLastPathComponent() == resolvedDir,
               fileURL != manifestURL,
               FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                } catch {
                    throw FontImportError.storageFailure("Failed to remove font file: \(error.localizedDescription)")
                }
            }
        }

        records.remove(at: idx)
        try saveManifestUnlocked(records)
    }

    public func fontFileURL(for record: CustomFontRecord) -> URL {
        safeFontFileURL(forFileName: record.fileName)
    }

    @discardableResult
    public func registerInProcess(_ record: CustomFontRecord) -> Bool {
        let url = fontFileURL(for: record)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return registerURLInProcess(url)
    }

    public func unregisterInProcess(_ record: CustomFontRecord) {
        let url = fontFileURL(for: record)
        unregisterURLInProcess(url)
    }

    @discardableResult
    public func registerAllStoredFonts() -> [CustomFontRecord] {
        guard let records = try? loadManifest() else { return [] }
        for record in records {
            _ = registerInProcess(record)
        }
        return records
    }

    public func systemFontFamilies(monospaceOnly: Bool) -> [String] {
        let rawFamilies = (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
        let uniqueFamilies = Array(Set(rawFamilies.filter { !$0.hasPrefix(".") }))

        let filtered: [String]
        if monospaceOnly {
            filtered = uniqueFamilies.filter { family in
                let attrs: [CFString: Any] = [kCTFontFamilyNameAttribute: family]
                let descriptor = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
                let font = CTFontCreateWithFontDescriptor(descriptor, 12.0, nil)
                let resolvedFamily = CTFontCopyFamilyName(font) as String
                guard resolvedFamily.caseInsensitiveCompare(family) == .orderedSame else {
                    return false
                }
                return CTFontGetSymbolicTraits(font).contains(.traitMonoSpace)
            }
        } else {
            filtered = uniqueFamilies
        }

        return filtered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public func generateFontspecBlock(
        for record: CustomFontRecord,
        role: LaTeXFontRole,
        customCommandName: String? = nil
    ) -> String {
        let safeFile = Self.sanitizeTeXArgument((record.fileName as NSString).lastPathComponent)
        return Self.buildFontspecStatement(target: safeFile, role: role, customCommandName: customCommandName)
    }

    public func generateSystemFontspecBlock(
        familyName: String,
        role: LaTeXFontRole,
        customCommandName: String? = nil
    ) -> String {
        let safeFamily = Self.sanitizeTeXArgument(familyName)
        return Self.buildFontspecStatement(target: safeFamily, role: role, customCommandName: customCommandName)
    }

    // MARK: - Internal Helpers

    private func ensureFontsDirectoryExistsUnlocked() throws {
        do {
            try FileManager.default.createDirectory(at: fontsDirectory, withIntermediateDirectories: true)
        } catch {
            throw FontImportError.storageFailure("Could not create Fonts directory: \(error.localizedDescription)")
        }
    }

    private func loadManifestUnlocked() throws -> [CustomFontRecord] {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(FontLibraryManifest.self, from: data)
            let resolvedDir = fontsDirectory.resolvingSymlinksInPath()
            return manifest.fonts.filter { record in
                guard let validLeaf = Self.validatedManifestFileName(record.fileName) else {
                    return false
                }
                let resolvedFile = fontsDirectory.appendingPathComponent(validLeaf).resolvingSymlinksInPath()
                return resolvedFile.deletingLastPathComponent() == resolvedDir
            }
        } catch {
            throw FontImportError.storageFailure("Failed to read fonts.json manifest: \(error.localizedDescription)")
        }
    }

    private func saveManifestUnlocked(_ records: [CustomFontRecord]) throws {
        try ensureFontsDirectoryExistsUnlocked()
        let manifest = FontLibraryManifest(schemaVersion: 1, fonts: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: [.atomic])
        } catch {
            throw FontImportError.storageFailure("Failed to save fonts.json manifest: \(error.localizedDescription)")
        }
    }

    private func safeFontFileURL(forFileName fileName: String) -> URL {
        if let validLeaf = Self.validatedManifestFileName(fileName) {
            return fontsDirectory.appendingPathComponent(validLeaf).standardizedFileURL
        }
        return fontsDirectory.appendingPathComponent("invalid-font-entry.ttf").standardizedFileURL
    }

    public static func validatedManifestFileName(_ rawName: String) -> String? {
        guard !rawName.contains("/"), !rawName.contains("\\"), !rawName.contains("\0") else {
            return nil
        }
        let hasControl = rawName.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        guard !hasControl else { return nil }
        let leaf = (rawName as NSString).lastPathComponent
        guard !leaf.isEmpty, leaf != ".", leaf != "..", leaf.caseInsensitiveCompare("fonts.json") != .orderedSame else {
            return nil
        }
        let ext = URL(fileURLWithPath: leaf).pathExtension.lowercased()
        guard FontFileFormat(rawValue: ext) != nil else {
            return nil
        }
        return leaf
    }

    private func registerURLInProcess(_ url: URL) -> Bool {
        var cfError: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &cfError) {
            return true
        }
        if let err = cfError?.takeRetainedValue() {
            let code = CFErrorGetCode(err)
            if code == CTFontManagerError.alreadyRegistered.rawValue {
                return true
            }
        }
        return false
    }

    private func unregisterURLInProcess(_ url: URL) {
        var cfError: Unmanaged<CFError>?
        _ = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, &cfError)
        _ = cfError?.takeRetainedValue()
    }

    public static func sanitizeBaseFileName(_ rawName: String) -> String {
        let leaf = (rawName as NSString).lastPathComponent
        var result = ""
        for scalar in leaf.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII {
                result.unicodeScalars.append(scalar)
            } else if scalar == "-" {
                result.unicodeScalars.append(scalar)
            } else if scalar == " " || scalar == "." || scalar == "_" {
                result.append("-")
            }
        }
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        return result.isEmpty ? "CustomFont" : result
    }

    public static func sanitizeCustomCommandName(_ rawName: String?) -> String {
        let stripped = (rawName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let noSlash = stripped.hasPrefix("\\") ? String(stripped.dropFirst()) : stripped
        let lettersOnly = String(noSlash.unicodeScalars.filter {
            ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122)
        })
        return lettersOnly.isEmpty ? "customfont" : lettersOnly
    }

    public static func sanitizeTeXArgument(_ raw: String) -> String {
        var forbidden = CharacterSet(charactersIn: "{}\\%$\r\n#&~^_[]\t\0")
        forbidden.formUnion(.controlCharacters)
        return String(raw.unicodeScalars.filter { !forbidden.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func buildFontspecStatement(
        target: String,
        role: LaTeXFontRole,
        customCommandName: String?
    ) -> String {
        guard !target.isEmpty else { return "" }
        switch role {
        case .main:
            return "\\setmainfont{\(target)}"
        case .sans:
            return "\\setsansfont{\(target)}"
        case .mono:
            return "\\setmonofont{\(target)}"
        case .customFamily:
            let cmd = sanitizeCustomCommandName(customCommandName)
            return "\\newfontfamily\\\(cmd){\(target)}"
        }
    }
}
