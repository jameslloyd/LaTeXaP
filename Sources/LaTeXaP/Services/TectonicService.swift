import Foundation

public struct CompilationResult: Sendable {
    public let success: Bool
    public let pdfURL: URL?
    public let synctexData: SyncTeXData?
    public let diagnostics: [LaTeXDiagnostic]
    public let logOutput: String
    public let durationMs: Int
}

public actor TectonicService {
    private let workspaceDir: URL
    private var currentProcess: Process?

    public init() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("LaTeXaPStudioBuild", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.workspaceDir = base
    }

    public static func locateTectonicBinary() -> String? {
        // 1. Check embedded app bundle Resources or MacOS directory
        if let bundled = Bundle.main.path(forResource: "tectonic", ofType: nil),
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let sibling = execDir.appendingPathComponent("tectonic").path
            if FileManager.default.isExecutableFile(atPath: sibling) {
                return sibling
            }
        }

        // 2. Check standard macOS Homebrew / Cargo / system paths
        let candidates = [
            "/opt/homebrew/bin/tectonic",
            "/usr/local/bin/tectonic",
            "\(NSHomeDirectory())/.cargo/bin/tectonic",
            "/usr/bin/tectonic"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    public func cancelRunningCompilation() {
        if let proc = currentProcess, proc.isRunning {
            proc.terminate()
        }
        currentProcess = nil
    }

    public func compile(
        source: String,
        documentDirectory: URL? = nil,
        fontDirectories: [URL] = []
    ) async -> CompilationResult {
        cancelRunningCompilation()
        let startTime = DispatchTime.now()

        guard let tectonicPath = Self.locateTectonicBinary() else {
            let diag = LaTeXDiagnostic(
                line: nil,
                severity: .error,
                message: "Tectonic engine binary not found. Install via `brew install tectonic` or bundle inside LaTeXaP.app."
            )
            return CompilationResult(
                success: false,
                pdfURL: nil,
                synctexData: nil,
                diagnostics: [diag],
                logOutput: diag.message,
                durationMs: 0
            )
        }

        let buildDir = workspaceDir
        try? FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)

        stageFontFiles(from: fontDirectories, into: buildDir)

        let texFileURL = buildDir.appendingPathComponent("document.tex")
        let pdfFileURL = buildDir.appendingPathComponent("document.pdf")
        let logFileURL = buildDir.appendingPathComponent("document.log")
        let synctexURL = buildDir.appendingPathComponent("document.synctex.gz")

        // Remove stale PDF only if needed; keeping previous files in buildDir allows faster incremental reruns
        do {
            try source.write(to: texFileURL, atomically: true, encoding: .utf8)
        } catch {
            let diag = LaTeXDiagnostic(
                line: nil,
                severity: .error,
                message: "Failed to write temporary TeX source: \(error.localizedDescription)"
            )
            return CompilationResult(
                success: false,
                pdfURL: nil,
                synctexData: nil,
                diagnostics: [diag],
                logOutput: diag.message,
                durationMs: 0
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tectonicPath)
        process.currentDirectoryURL = documentDirectory ?? buildDir
        process.arguments = [
            "-X",
            "--color", "never",
            "compile",
            "--synctex",
            "--keep-logs",
            "--outdir", buildDir.path,
            texFileURL.path
        ]

        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "\(extraPaths):\(env["PATH"] ?? "")"
        Self.injectFontEnvironment(fontDirectories: fontDirectories, into: &env)
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        self.currentProcess = process

        let exitCode: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }

        self.currentProcess = nil

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdOutStr = String(data: outData, encoding: .utf8) ?? ""
        let stdErrStr = String(data: errData, encoding: .utf8) ?? ""
        let texLogStr = (try? String(contentsOf: logFileURL, encoding: .utf8)) ?? ""

        let combinedConsole = [stdOutStr, stdErrStr, texLogStr]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n--- TeX Transcript (document.log) ---\n")

        let elapsedNs = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
        let durationMs = Int(elapsedNs / 1_000_000)

        let diagnostics = Self.parseDiagnostics(stderr: stdErrStr, stdout: stdOutStr, logFile: texLogStr)
        let pdfExists = exitCode == 0 && FileManager.default.fileExists(atPath: pdfFileURL.path)
        let synctexData = pdfExists ? SyncTeXParser.parse(synctexGzURL: synctexURL) : nil

        return CompilationResult(
            success: pdfExists,
            pdfURL: pdfExists ? pdfFileURL : nil,
            synctexData: synctexData,
            diagnostics: diagnostics,
            logOutput: combinedConsole,
            durationMs: durationMs
        )
    }

    private func stageFontFiles(from fontDirectories: [URL], into buildDir: URL) {
        let allowedExtensions: Set<String> = ["ttf", "otf", "ttc"]
        let fm = FileManager.default

        // Clean up previous font symlinks so deleted fonts do not remain staged
        if let existingItems = try? fm.contentsOfDirectory(
            at: buildDir,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) {
            for item in existingItems {
                let ext = item.pathExtension.lowercased()
                guard allowedExtensions.contains(ext) else { continue }
                let values = try? item.resourceValues(forKeys: [.isSymbolicLinkKey])
                if values?.isSymbolicLink == true {
                    try? fm.removeItem(at: item)
                }
            }
        }

        // Create fresh symlinks for each regular, non-symlink font binary in the provided directories
        for dir in fontDirectories where dir.isFileURL {
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for fontFile in files {
                let ext = fontFile.pathExtension.lowercased()
                guard allowedExtensions.contains(ext) else { continue }
                let values = try? fontFile.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
                let destLink = buildDir.appendingPathComponent(fontFile.lastPathComponent)
                if !fm.fileExists(atPath: destLink.path) {
                    try? fm.createSymbolicLink(at: destLink, withDestinationURL: fontFile)
                }
            }
        }
    }

    public static func injectFontEnvironment(fontDirectories: [URL], into env: inout [String: String]) {
        let searchEntries = fontDirectories.compactMap { dir -> String? in
            guard dir.isFileURL else { return nil }
            let path = dir.standardizedFileURL.path
            guard !path.isEmpty,
                  !path.contains(":"),
                  !path.contains("\r"),
                  !path.contains("\n"),
                  !path.contains("\0") else {
                return nil
            }
            return path
        }
        guard !searchEntries.isEmpty else { return }
        let prefix = searchEntries.joined(separator: ":")
        for key in ["OPENTYPEFONTS", "TTFONTS", "OSFONTDIR"] {
            if let existing = env[key], !existing.isEmpty {
                env[key] = "\(prefix):\(existing)"
            } else {
                env[key] = "\(prefix):"
            }
        }
    }

    public static func parseDiagnostics(stderr: String, stdout: String, logFile: String) -> [LaTeXDiagnostic] {
        var results: [LaTeXDiagnostic] = []
        var seenKeys = Set<String>()

        func appendUnique(line: Int?, severity: DiagnosticSeverity, message: String, raw: String) {
            let cleanMsg = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanMsg.isEmpty else { return }
            // Ignore generic boilerplate error wrapper from tectonic if we already have the specific error
            if cleanMsg == "something bad happened inside XeTeX; its output follows:" ||
               cleanMsg == "the XeTeX engine had an unrecoverable error" ||
               cleanMsg == "halted on potentially-recoverable error as specified" {
                return
            }
            let key = "\(severity.rawValue)-\(line ?? -1)-\(cleanMsg)"
            if seenKeys.insert(key).inserted {
                results.append(LaTeXDiagnostic(line: line, severity: severity, message: cleanMsg, rawLine: raw))
            }
        }

        // 1. Parse Tectonic stderr format:
        // error: document.tex:14: Undefined control sequence.
        // warning: document.tex:22: ...
        let tectonicRegex = try? NSRegularExpression(pattern: #"^(error|warning):\s*(?:[^:]+:(\d+):)?\s*(.+)$"#, options: [.anchorsMatchLines])
        let stderrNS = stderr as NSString
        if let matches = tectonicRegex?.matches(in: stderr, range: NSRange(location: 0, length: stderrNS.length)) {
            for match in matches {
                let kind = stderrNS.substring(with: match.range(at: 1)).lowercased()
                var lineNum: Int?
                if match.range(at: 2).location != NSNotFound {
                    lineNum = Int(stderrNS.substring(with: match.range(at: 2)))
                }
                let msg = stderrNS.substring(with: match.range(at: 3))
                let raw = stderrNS.substring(with: match.range)
                appendUnique(
                    line: lineNum,
                    severity: kind == "error" ? .error : .warning,
                    message: msg,
                    raw: raw
                )
            }
        }

        // 2. Parse TeX log file for `! ...` errors with subsequent `l.<number>` lines, and LaTeX/Package warnings
        let logLines = logFile.components(separatedBy: .newlines)
        var idx = 0
        while idx < logLines.count {
            let line = logLines[idx]
            if line.hasPrefix("! ") {
                let errorMsg = String(line.dropFirst(2))
                var foundLine: Int?
                // Look ahead up to 12 lines for `l.123 ...`
                for lookahead in (idx + 1)..<min(idx + 14, logLines.count) {
                    let candidate = logLines[lookahead]
                    if candidate.hasPrefix("l.") {
                        let digits = candidate.dropFirst(2).prefix { $0.isNumber }
                        if let parsed = Int(digits) {
                            foundLine = parsed
                            break
                        }
                    }
                }
                appendUnique(line: foundLine, severity: .error, message: errorMsg, raw: line)
            } else if line.contains("Warning:") || line.hasPrefix("Overfull \\hbox") || line.hasPrefix("Underfull \\hbox") {
                var lineNum: Int?
                if let range = line.range(of: #"on input line (\d+)"#, options: .regularExpression) {
                    let sub = line[range]
                    let digits = sub.filter { $0.isNumber }
                    lineNum = Int(digits)
                } else if let range = line.range(of: #"lines (\d+)--(\d+)"#, options: .regularExpression) {
                    let sub = line[range]
                    let firstDigits = sub.drop { !$0.isNumber }.prefix { $0.isNumber }
                    lineNum = Int(firstDigits)
                }
                let severity: DiagnosticSeverity = (line.hasPrefix("Overfull") || line.hasPrefix("Underfull")) ? .info : .warning
                appendUnique(line: lineNum, severity: severity, message: line, raw: line)
            } else if line.hasPrefix("note: downloading ") {
                appendUnique(line: nil, severity: .info, message: line, raw: line)
            }
            idx += 1
        }

        // Also capture package download notifications from stderr
        for raw in stderr.components(separatedBy: .newlines) where raw.hasPrefix("note: downloading ") {
            appendUnique(line: nil, severity: .info, message: String(raw.dropFirst("note: ".count)), raw: raw)
        }

        return results.sorted { a, b in
            let rankA = a.severity == .error ? 0 : (a.severity == .warning ? 1 : 2)
            let rankB = b.severity == .error ? 0 : (b.severity == .warning ? 1 : 2)
            if rankA != rankB { return rankA < rankB }
            return (a.line ?? Int.max) < (b.line ?? Int.max)
        }
    }
}
