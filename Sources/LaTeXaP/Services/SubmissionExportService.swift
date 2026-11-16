import Foundation

public enum SubmissionExportError: LocalizedError, Sendable {
    case invalidDestination(String)
    case emptySource
    case zipCreationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDestination(let msg):
            return msg
        case .emptySource:
            return "Cannot export an empty document."
        case .zipCreationFailed(let msg):
            return "Failed to package submission ZIP archive: \(msg)"
        }
    }
}

public enum SubmissionExportService {
    public static let maxAssetBytes: Int64 = 50 * 1024 * 1024

    public static func exportBundle(
        source: String,
        mainFileName: String = "main.tex",
        destinationZipURL: URL,
        managedBibContent: String = "",
        documentDirectory: URL? = nil,
        tempFiguresDirectory: URL? = nil,
        customFonts: [CustomFontRecord] = [],
        fontLibraryDirectory: URL? = nil,
        stripComments: Bool = false,
        anonymize: Bool = false,
        verifyCompileWithTectonic: Bool = true
    ) async throws -> SubmissionExportResult {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SubmissionExportError.emptySource
        }
        guard destinationZipURL.isFileURL else {
            throw SubmissionExportError.invalidDestination("Destination must be a local file URL.")
        }

        let standardizedDest = destinationZipURL.standardizedFileURL
        let destLinkValues = try? standardizedDest.resourceValues(forKeys: [.isSymbolicLinkKey])
        if destLinkValues?.isSymbolicLink == true {
            throw SubmissionExportError.invalidDestination("Destination ZIP path cannot be a symbolic link.")
        }

        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("LaTeXaPExport-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let safeBundleName = sanitizeBundleFolderName(standardizedDest.deletingPathExtension().lastPathComponent)
        let bundleDir = tempRoot.appendingPathComponent(safeBundleName, isDirectory: true)
        try fm.createDirectory(at: bundleDir, withIntermediateDirectories: true)

        var warnings: [String] = []
        var includedFiles: [String] = []

        // 1. Transform main TeX source (anonymization + comment stripping)
        var exportSource = source
        if anonymize {
            exportSource = applyBlindReviewTransform(to: exportSource)
        }
        if stripComments {
            exportSource = stripTeXComments(from: exportSource)
        }

        let safeMainName = sanitizeTeXLeafName(mainFileName, fallback: "main.tex")
        let mainDestURL = bundleDir.appendingPathComponent(safeMainName)
        try exportSource.write(to: mainDestURL, atomically: true, encoding: .utf8)
        includedFiles.append(safeMainName)

        // 2. Collect referenced \input{...} / \include{...} TeX subfiles safely
        if let docDir = documentDirectory {
            let resolvedDocDir = docDir.standardizedFileURL.resolvingSymlinksInPath()
            for relInput in extractIncludedTeXPaths(from: exportSource) {
                guard let validRel = AcademicSanitizer.validatedRelativeAssetPath(relInput) else {
                    warnings.append("Skipped unsafe \\input/\\include path '\(relInput)'.")
                    continue
                }
                let candidateNames = validRel.hasSuffix(".tex") ? [validRel] : [validRel + ".tex", validRel]
                for relCandidate in candidateNames {
                    if let srcURL = validatedContainedFile(relativePath: relCandidate, inside: resolvedDocDir) {
                        if try copyValidatedAsset(from: srcURL, toRelativePath: relCandidate, in: bundleDir) {
                            if !includedFiles.contains(relCandidate) {
                                includedFiles.append(relCandidate)
                            }
                        }
                        break
                    }
                }
            }
        }

        // 3. Stage references.bib / referenced .bib resources
        let referencedBibs = BibliographyService.extractReferencedBibFiles(from: exportSource)
        let trimmedManagedBib = managedBibContent.trimmingCharacters(in: .whitespacesAndNewlines)
        var stagedBibs = Set<String>()

        if !trimmedManagedBib.isEmpty {
            let targetName = "references.bib"
            let bibDest = bundleDir.appendingPathComponent(targetName)
            try (trimmedManagedBib + "\n").write(to: bibDest, atomically: true, encoding: .utf8)
            includedFiles.append(targetName)
            stagedBibs.insert(targetName)
        }

        if let docDir = documentDirectory {
            let resolvedDocDir = docDir.standardizedFileURL.resolvingSymlinksInPath()
            for bibName in referencedBibs where !stagedBibs.contains(bibName) {
                guard let validRel = AcademicSanitizer.validatedRelativeAssetPath(bibName) else {
                    warnings.append("Skipped unsafe bibliography path '\(bibName)'.")
                    continue
                }
                if let srcURL = validatedContainedFile(relativePath: validRel, inside: resolvedDocDir) {
                    if try copyValidatedAsset(from: srcURL, toRelativePath: validRel, in: bundleDir) {
                        includedFiles.append(validRel)
                        stagedBibs.insert(validRel)
                    }
                } else {
                    warnings.append("Missing bibliography resource '\(bibName)'.")
                }
            }
        }

        // 4. Collect referenced relative figures safely
        let figureRefs = AcademicPreflightService.extractFigurePaths(from: exportSource)
        var copiedFigures = Set<String>()
        for fig in figureRefs {
            guard let validRel = AcademicSanitizer.validatedRelativeAssetPath(fig.path) else {
                warnings.append("Non-portable figure path '\(fig.path)' (line \(fig.line)) was not bundled.")
                continue
            }
            if copiedFigures.contains(validRel) { continue }

            if let resolvedSrc = locateFigureAsset(
                relativePath: validRel,
                documentDirectory: documentDirectory,
                tempFiguresDirectory: tempFiguresDirectory
            ) {
                if try copyValidatedAsset(from: resolvedSrc.fileURL, toRelativePath: resolvedSrc.relativePath, in: bundleDir) {
                    includedFiles.append(resolvedSrc.relativePath)
                    copiedFigures.insert(validRel)
                }
            } else {
                warnings.append("Missing figure '\(fig.path)' referenced on line \(fig.line).")
            }
        }

        // 5. Collect referenced custom font binaries
        if let fontLibDir = fontLibraryDirectory {
            let resolvedFontDir = fontLibDir.standardizedFileURL.resolvingSymlinksInPath()
            for font in customFonts {
                let isReferenced = exportSource.contains(font.fileName) ||
                    exportSource.contains(font.familyName) ||
                    exportSource.contains(font.postScriptName)
                guard isReferenced,
                      let validFile = FontLibraryService.validatedManifestFileName(font.fileName),
                      let srcFontURL = validatedContainedFile(relativePath: validFile, inside: resolvedFontDir) else {
                    continue
                }
                if try copyValidatedAsset(from: srcFontURL, toRelativePath: validFile, in: bundleDir) {
                    includedFiles.append(validFile)
                }
            }
        }

        // 6. Optional clean compile verification before zipping
        var compiledCleanly = true
        if verifyCompileWithTectonic {
            let verifyDir = tempRoot.appendingPathComponent("VerifyBuild", isDirectory: true)
            let fontDirs = fontLibraryDirectory.map { [$0] } ?? []
            let verifyResult = await TectonicService(workspaceDirectory: verifyDir).compile(
                source: exportSource,
                documentDirectory: bundleDir,
                fontDirectories: fontDirs,
                additionalTextFiles: [:],
                assetSearchDirectories: [bundleDir]
            )
            compiledCleanly = verifyResult.success
            if !verifyResult.success {
                let errCount = verifyResult.diagnostics.filter { $0.severity == .error }.count
                warnings.append("Bundle verification compile reported \(max(1, errCount)) error(s).")
            }
        }

        // 7. Package bundleDir into ZIP using macOS `/usr/bin/ditto`
        let tempZipURL = tempRoot.appendingPathComponent("\(safeBundleName).zip")
        try runDittoZip(sourceDirectory: bundleDir, outputZipURL: tempZipURL)

        let parentDir = standardizedDest.deletingLastPathComponent()
        try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        if fm.fileExists(atPath: standardizedDest.path) {
            try fm.removeItem(at: standardizedDest)
        }
        try fm.moveItem(at: tempZipURL, to: standardizedDest)

        return SubmissionExportResult(
            zipURL: standardizedDest,
            includedFiles: includedFiles,
            preflightWarnings: warnings,
            compiledCleanly: compiledCleanly
        )
    }

    // MARK: - Transformations

    public static func stripTeXComments(from source: String) -> String {
        let lines = source.components(separatedBy: .newlines)
        var output: [String] = []
        output.reserveCapacity(lines.count)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("%") {
                continue
            }
            if let commentRange = line.range(of: #"(?<!\\)%.*$"#, options: .regularExpression) {
                let stripped = String(line[..<commentRange.lowerBound]).replacingOccurrences(
                    of: #"[ \t]+$"#,
                    with: "",
                    options: .regularExpression
                )
                output.append(stripped)
            } else {
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }

    public static func applyBlindReviewTransform(to source: String) -> String {
        var result = source

        // Replace \author{...} (supports nested braces like \textbf{...})
        result = replaceCommandBraceArgument(in: result, command: "author", replacement: "Anonymous Author(s)")
        result = replaceCommandBraceArgument(in: result, command: "affiliation", replacement: "Anonymous Institution")
        result = replaceCommandBraceArgument(in: result, command: "institute", replacement: "Anonymous Institution")

        // Ensure lineno package and \linenumbers are present
        if result.range(of: #"\\usepackage(?:\[[^\]]*\])?\{[^}]*\blinenumber|lineno\b[^}]*\}"#, options: .regularExpression) == nil &&
           !result.contains("\\usepackage{lineno}") {
            if let docRange = result.range(of: #"(?m)^\\documentclass[^\n]*\n"#, options: .regularExpression) {
                result.insert(contentsOf: "\\usepackage{lineno}\n\\linenumbers\n", at: docRange.upperBound)
            }
        } else if !result.contains("\\linenumbers") {
            if let pkgRange = result.range(of: #"(?m)^\\usepackage(?:\[[^\]]*\])?\{lineno\}[^\n]*\n"#, options: .regularExpression) {
                result.insert(contentsOf: "\\linenumbers\n", at: pkgRange.upperBound)
            }
        }

        return result
    }

    private static func replaceCommandBraceArgument(in source: String, command: String, replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\\\\(command)\\s*\\{") else {
            return source
        }
        let ns = source as NSString
        guard let match = regex.firstMatch(in: source, range: NSRange(location: 0, length: ns.length)) else {
            return source
        }
        // Find matching brace using String.Index
        guard let startIdx = Range(NSRange(location: match.range.location, length: match.range.length), in: source)?.upperBound else {
            return source
        }
        var depth = 1
        var cursor = startIdx
        while cursor < source.endIndex && depth > 0 {
            let ch = source[cursor]
            if ch == "\\" {
                let next = source.index(after: cursor)
                if next < source.endIndex {
                    cursor = source.index(after: next)
                    continue
                }
            } else if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    break
                }
            }
            cursor = source.index(after: cursor)
        }
        guard depth == 0 else { return source }
        var updated = source
        updated.replaceSubrange(startIdx..<cursor, with: replacement)
        return updated
    }

    // MARK: - Staging & Security Helpers

    private static func extractIncludedTeXPaths(from source: String) -> [String] {
        var paths: [String] = []
        guard let regex = try? NSRegularExpression(pattern: #"\\(?:input|include)\{([^}]+)\}"#) else {
            return paths
        }
        let stripped = stripTeXComments(from: source)
        let ns = stripped as NSString
        for m in regex.matches(in: stripped, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges >= 2 {
            let rel = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rel.isEmpty && !paths.contains(rel) {
                paths.append(rel)
            }
        }
        return paths
    }

    private static func locateFigureAsset(
        relativePath: String,
        documentDirectory: URL?,
        tempFiguresDirectory: URL?
    ) -> (fileURL: URL, relativePath: String)? {
        let candidateExtensions = ["", ".png", ".jpg", ".jpeg", ".pdf", ".tiff", ".eps"]

        if let docDir = documentDirectory {
            let resolvedDoc = docDir.standardizedFileURL.resolvingSymlinksInPath()
            for ext in candidateExtensions {
                let relCandidate = (ext.isEmpty || !(relativePath as NSString).pathExtension.isEmpty) ? relativePath : relativePath + ext
                if let url = validatedContainedFile(relativePath: relCandidate, inside: resolvedDoc) {
                    return (url, relCandidate)
                }
            }
        }

        if let tempDir = tempFiguresDirectory, relativePath.hasPrefix("figures/") {
            let resolvedTemp = tempDir.standardizedFileURL.resolvingSymlinksInPath()
            let leaf = String(relativePath.dropFirst("figures/".count))
            for ext in candidateExtensions {
                let leafCandidate = (ext.isEmpty || !(leaf as NSString).pathExtension.isEmpty) ? leaf : leaf + ext
                if let url = validatedContainedFile(relativePath: leafCandidate, inside: resolvedTemp) {
                    return (url, "figures/\(leafCandidate)")
                }
            }
        }

        return nil
    }

    private static func validatedContainedFile(relativePath: String, inside resolvedRootDir: URL) -> URL? {
        guard let validRel = AcademicSanitizer.validatedRelativeAssetPath(relativePath) else {
            return nil
        }
        let candidate = resolvedRootDir.appendingPathComponent(validRel).standardizedFileURL
        let linkVals = try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard linkVals?.isSymbolicLink != true else {
            return nil
        }
        let resolvedCandidate = candidate.resolvingSymlinksInPath()
        let rootPrefix = resolvedRootDir.path.hasSuffix("/") ? resolvedRootDir.path : resolvedRootDir.path + "/"
        guard resolvedCandidate.path.hasPrefix(rootPrefix) else {
            return nil
        }
        let fileVals = try? resolvedCandidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard fileVals?.isRegularFile == true, fileVals?.isSymbolicLink != true else {
            return nil
        }
        let size = Int64(fileVals?.fileSize ?? 0)
        guard size <= maxAssetBytes else {
            return nil
        }
        return resolvedCandidate
    }

    private static func copyValidatedAsset(from sourceURL: URL, toRelativePath relativePath: String, in bundleDir: URL) throws -> Bool {
        guard let validRel = AcademicSanitizer.validatedRelativeAssetPath(relativePath) else {
            return false
        }
        let destURL = bundleDir.appendingPathComponent(validRel).standardizedFileURL
        let bundlePrefix = bundleDir.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let destParentResolved = destURL.deletingLastPathComponent().resolvingSymlinksInPath().path
        let bundleResolved = bundleDir.standardizedFileURL.resolvingSymlinksInPath().path
        guard destParentResolved == bundleResolved || destParentResolved.hasPrefix(bundlePrefix) else {
            return false
        }
        let fm = FileManager.default
        try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        try fm.copyItem(at: sourceURL, to: destURL)
        return true
    }

    private static func runDittoZip(sourceDirectory: URL, outputZipURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c", "-k",
            "--sequesterRsrc",
            "--keepParent",
            sourceDirectory.path,
            outputZipURL.path
        ]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "ditto exit status \(process.terminationStatus)"
            throw SubmissionExportError.zipCreationFailed(errMsg)
        }
    }

    private static func sanitizeBundleFolderName(_ raw: String) -> String {
        let cleaned = AcademicSanitizer.sanitizeIdentifier(raw, fallback: "LaTeXaP-Submission")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return cleaned.isEmpty ? "LaTeXaP-Submission" : cleaned
    }

    private static func sanitizeTeXLeafName(_ raw: String, fallback: String) -> String {
        let leaf = (raw as NSString).lastPathComponent
        let base = URL(fileURLWithPath: leaf).deletingPathExtension().lastPathComponent
        let safeBase = FontLibraryService.sanitizeBaseFileName(base)
        return "\(safeBase).tex"
    }
}
