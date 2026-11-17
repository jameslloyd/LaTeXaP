import Foundation

public enum GitAuthMethod: String, Codable, Sendable, CaseIterable, Identifiable {
    case personalAccessToken
    case sshKey
    case ghCLI

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .personalAccessToken:
            return "Personal Access Token (Keychain)"
        case .sshKey:
            return "SSH Key (~/.ssh)"
        case .ghCLI:
            return "GitHub CLI (gh)"
        }
    }
}

public struct GitHubRepoConnection: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var owner: String
    public var repoName: String
    public var remoteURLString: String
    public var branch: String
    public var authMethod: GitAuthMethod
    public var localFolderName: String
    public var autoPushOnSave: Bool
    public var includePDFsInCommits: Bool
    public var lastSyncedAt: Date?

    public var fullName: String {
        "\(owner)/\(repoName)"
    }

    public init(
        id: UUID = UUID(),
        owner: String,
        repoName: String,
        remoteURLString: String,
        branch: String = "main",
        authMethod: GitAuthMethod = .personalAccessToken,
        localFolderName: String,
        autoPushOnSave: Bool = true,
        includePDFsInCommits: Bool = false,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.owner = owner
        self.repoName = repoName
        self.remoteURLString = remoteURLString
        self.branch = branch
        self.authMethod = authMethod
        self.localFolderName = localFolderName
        self.autoPushOnSave = autoPushOnSave
        self.includePDFsInCommits = includePDFsInCommits
        self.lastSyncedAt = lastSyncedAt
    }
}

public struct GitHubWorkspaceManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var repoFullName: String
    public var defaultBranch: String
    public var projects: [AcademicProjectDescriptor]

    public init(
        schemaVersion: Int = 1,
        repoFullName: String,
        defaultBranch: String = "main",
        projects: [AcademicProjectDescriptor] = []
    ) {
        self.schemaVersion = schemaVersion
        self.repoFullName = repoFullName
        self.defaultBranch = defaultBranch
        self.projects = projects
    }
}

public struct AcademicProjectDescriptor: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var slug: String
    public var displayName: String
    public var relativePath: String
    public var mainTexFile: String
    public var bibFile: String
    public var templateId: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var rubricTargets: RubricTargetConfig?

    public init(
        id: UUID = UUID(),
        slug: String,
        displayName: String,
        relativePath: String? = nil,
        mainTexFile: String = "main.tex",
        bibFile: String = "references.bib",
        templateId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        rubricTargets: RubricTargetConfig? = nil
    ) {
        self.id = id
        self.slug = slug
        self.displayName = displayName
        self.relativePath = relativePath ?? "projects/\(slug)"
        self.mainTexFile = mainTexFile
        self.bibFile = bibFile
        self.templateId = templateId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rubricTargets = rubricTargets
    }
}

public struct GitFileChange: Identifiable, Equatable, Sendable {
    public var id: String { relativePath }
    public let relativePath: String
    public let status: String

    public var fileName: String {
        (relativePath as NSString).lastPathComponent
    }

    public var statusLabel: String {
        switch status {
        case "A", "??": return "Added"
        case "D": return "Deleted"
        case "R": return "Renamed"
        case "U": return "Conflict"
        default: return "Modified"
        }
    }

    public init(relativePath: String, status: String) {
        self.relativePath = relativePath
        self.status = status
    }
}

public struct GitCommitRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let shortHash: String
    public let message: String
    public let authorName: String
    public let date: Date
    public let changedFiles: [String]
    public let isPushed: Bool

    public init(
        id: String,
        shortHash: String,
        message: String,
        authorName: String,
        date: Date,
        changedFiles: [String] = [],
        isPushed: Bool = true
    ) {
        self.id = id
        self.shortHash = shortHash
        self.message = message
        self.authorName = authorName
        self.date = date
        self.changedFiles = changedFiles
        self.isPushed = isPushed
    }
}

public enum GitSyncState: Equatable, Sendable {
    case disconnected
    case idle(aheadCount: Int, behindCount: Int, lastSync: Date?)
    case committing
    case syncing(status: String)
    case offlinePendingPush(aheadCount: Int)
    case conflict(conflictedFiles: [String], message: String)
    case failed(message: String)

    public var isBusy: Bool {
        switch self {
        case .committing, .syncing:
            return true
        default:
            return false
        }
    }

    public var badgeTitle: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .idle(let ahead, let behind, _):
            if ahead > 0 && behind > 0 {
                return "\(ahead) Ahead • \(behind) Behind"
            } else if ahead > 0 {
                return "\(ahead) Ahead"
            } else if behind > 0 {
                return "\(behind) Behind"
            }
            return "Synced"
        case .committing:
            return "Committing..."
        case .syncing(let status):
            return status.isEmpty ? "Syncing..." : status
        case .offlinePendingPush(let ahead):
            return "\(max(1, ahead)) Local • Offline"
        case .conflict(let files, _):
            return "Conflict (\(max(1, files.count)))"
        case .failed:
            return "Sync Error"
        }
    }
}

public enum GitConflictResolutionChoice: String, Sendable {
    case keepLocal
    case useRemote
}

public struct GitHubRemoteRepository: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let owner: String
    public let name: String
    public let fullName: String
    public let cloneURL: String
    public let sshURL: String
    public let defaultBranch: String
    public let isPrivate: Bool
    public let updatedAt: Date?

    public init(
        id: Int,
        owner: String,
        name: String,
        fullName: String,
        cloneURL: String,
        sshURL: String,
        defaultBranch: String,
        isPrivate: Bool,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.owner = owner
        self.name = name
        self.fullName = fullName
        self.cloneURL = cloneURL
        self.sshURL = sshURL
        self.defaultBranch = defaultBranch
        self.isPrivate = isPrivate
        self.updatedAt = updatedAt
    }
}

public struct GitHubAuthenticatedUser: Codable, Equatable, Sendable {
    public let login: String
    public let name: String?

    public init(login: String, name: String? = nil) {
        self.login = login
        self.name = name
    }
}

public enum GitStorageError: LocalizedError, Equatable, Sendable {
    case invalidRemoteURL(String)
    case invalidProjectSlug(String)
    case duplicateProjectSlug(String)
    case authenticationFailed(String)
    case gitBinaryNotFound
    case commandFailed(String)
    case mergeConflict([String])
    case fileSizeExceedsGitHubLimit(String)
    case securityViolation(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRemoteURL(let msg):
            return msg
        case .invalidProjectSlug(let msg):
            return msg
        case .duplicateProjectSlug(let slug):
            return "A project with slug '\(slug)' already exists in this repository."
        case .authenticationFailed(let msg):
            return msg
        case .gitBinaryNotFound:
            return "Git command-line tools (/usr/bin/git) could not be found."
        case .commandFailed(let msg):
            return msg
        case .mergeConflict(let files):
            let list = files.isEmpty ? "project files" : files.joined(separator: ", ")
            return "Merge conflict detected in \(list)."
        case .fileSizeExceedsGitHubLimit(let msg):
            return msg
        case .securityViolation(let msg):
            return msg
        }
    }
}

public enum GitHubWorkspaceValidator {
    public static let maxGitHubTrackedFileBytes: Int64 = 50 * 1024 * 1024

    public static let standardLaTeXGitIgnore: String = """
    # LaTeX / Tectonic build artifacts
    *.aux
    *.bbl
    *.bcf
    *.blg
    *.fdb_latexmk
    *.fls
    *.idx
    *.ilg
    *.ind
    *.lof
    *.log
    *.lot
    *.out
    *.run.xml
    *.synctex.gz
    *.toc
    .DS_Store
    """

    public static func laTeXGitIgnore(includePDFs: Bool) -> String {
        if includePDFs {
            return standardLaTeXGitIgnore + "\n"
        }
        return standardLaTeXGitIgnore + "\n*.pdf\n"
    }

    public static func defaultCommitMessage(projectName: String, at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let cleanName = projectName
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let display = cleanName.isEmpty ? "Untitled Project" : cleanName
        return "Update \(display) — \(formatter.string(from: date))"
    }

    public static func isValidProjectSlug(_ slug: String) -> Bool {
        guard !slug.isEmpty, slug.count <= 64 else { return false }
        return slug.range(of: #"^[a-z0-9]+(-[a-z0-9]+)*$"#, options: .regularExpression) != nil
    }

    public static func validatedProjectRelativeFile(
        _ raw: String,
        allowedExtensions: Set<String>? = nil
    ) -> String? {
        guard let validRel = AcademicSanitizer.validatedRelativeAssetPath(raw) else {
            return nil
        }
        let components = validRel.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return nil }
        for part in components {
            if part == "." || part == ".." || part == ".git" || part.hasPrefix(".") {
                return nil
            }
        }
        if let allowedExtensions {
            let ext = (validRel as NSString).pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { return nil }
        }
        return validRel
    }

    public static func slugifyProjectName(_ rawName: String) -> String {
        let lower = rawName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var slug = ""
        var prevDash = false
        for scalar in lower.unicodeScalars {
            if (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57) {
                slug.unicodeScalars.append(scalar)
                prevDash = false
            } else if !prevDash && !slug.isEmpty {
                slug.append("-")
                prevDash = true
            }
        }
        while slug.hasSuffix("-") {
            slug.removeLast()
        }
        if slug.count > 64 {
            slug = String(slug.prefix(64))
            while slug.hasSuffix("-") {
                slug.removeLast()
            }
        }
        return isValidProjectSlug(slug) ? slug : "untitled-project"
    }

    public static func validatedBranchName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 128,
              !trimmed.hasPrefix("-"),
              !trimmed.hasPrefix("/"),
              !trimmed.hasSuffix("/"),
              !trimmed.hasSuffix(".lock"),
              !trimmed.contains(".."),
              !trimmed.contains("@{"),
              !trimmed.contains("\\"),
              !trimmed.contains(":"),
              !trimmed.contains("~"),
              !trimmed.contains("^"),
              !trimmed.contains(" "),
              !trimmed.contains("\0") else {
            return nil
        }
        guard trimmed.range(of: #"^[A-Za-z0-9][A-Za-z0-9._/-]*$"#, options: .regularExpression) != nil else {
            return nil
        }
        return trimmed
    }

    public static func validatedCommitSHA(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^[0-9a-fA-F]{7,40}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return trimmed
    }

    public static func parseAndValidateRemoteURL(
        _ raw: String,
        allowLocalBareTestPath: Bool = false
    ) -> (owner: String, repo: String, normalizedURL: String, suggestedAuth: GitAuthMethod)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("\0"),
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }

        // Explicitly block dangerous git protocols in production
        let lower = trimmed.lowercased()
        if lower.hasPrefix("ext::") || lower.hasPrefix("fd::") || lower.hasPrefix("http://") {
            return nil
        }

        if allowLocalBareTestPath {
            let localURL: URL?
            if lower.hasPrefix("file://") {
                localURL = URL(string: trimmed)
            } else if trimmed.hasPrefix("/") {
                localURL = URL(fileURLWithPath: trimmed)
            } else {
                localURL = nil
            }
            if let localURL, localURL.isFileURL {
                let name = localURL.deletingPathExtension().lastPathComponent
                let safeRepo = name.isEmpty ? "local-repo" : name
                return ("local", safeRepo, localURL.path, .sshKey)
            }
        }

        if lower.hasPrefix("file://") {
            return nil
        }

        // 1. SSH format: git@github.com:owner/repo(.git)
        if trimmed.hasPrefix("git@github.com:") {
            let suffix = String(trimmed.dropFirst("git@github.com:".count))
            let parts = suffix.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else { return nil }
            let owner = parts[0]
            var repo = parts[1]
            if repo.hasSuffix(".git") {
                repo = String(repo.dropLast(4))
            }
            guard isValidGitHubOwner(owner), isValidGitHubRepoName(repo) else { return nil }
            return (owner, repo, "git@github.com:\(owner)/\(repo).git", .sshKey)
        }

        // 2. HTTPS format: https://github.com/owner/repo(.git)
        if lower.hasPrefix("https://") {
            guard let url = URL(string: trimmed),
                  url.scheme?.lowercased() == "https",
                  url.host?.lowercased() == "github.com",
                  (url.port == nil || url.port == 443),
                  url.user == nil,
                  url.password == nil,
                  url.query == nil,
                  url.fragment == nil else {
                return nil
            }
            let pathComponents = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard pathComponents.count == 2 else { return nil }
            let owner = pathComponents[0]
            var repo = pathComponents[1]
            if repo.hasSuffix(".git") {
                repo = String(repo.dropLast(4))
            }
            guard isValidGitHubOwner(owner), isValidGitHubRepoName(repo) else { return nil }
            return (owner, repo, "https://github.com/\(owner)/\(repo).git", .personalAccessToken)
        }

        // 3. Shorthand owner/repo
        if !trimmed.contains(":"), !trimmed.contains(" ") {
            let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if parts.count == 2 {
                let owner = parts[0]
                var repo = parts[1]
                if repo.hasSuffix(".git") {
                    repo = String(repo.dropLast(4))
                }
                guard isValidGitHubOwner(owner), isValidGitHubRepoName(repo) else { return nil }
                return (owner, repo, "https://github.com/\(owner)/\(repo).git", .personalAccessToken)
            }
        }

        return nil
    }

    public static func isValidGitHubOwner(_ owner: String) -> Bool {
        owner.range(of: #"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$"#, options: .regularExpression) != nil
    }

    public static func isValidGitHubRepoName(_ repo: String) -> Bool {
        guard repo != ".", repo != "..", !repo.contains("..") else { return false }
        return repo.range(of: #"^[A-Za-z0-9._-]{1,100}$"#, options: .regularExpression) != nil
    }

    public static func redactSensitiveToken(_ text: String, token: String?) -> String {
        var sanitized = text
        if let token, !token.isEmpty {
            sanitized = sanitized.replacingOccurrences(of: token, with: "[REDACTED]")
        }
        if let regex = try? NSRegularExpression(pattern: #"https://[^@\s]+@github\.com"#) {
            let ns = sanitized as NSString
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                range: NSRange(location: 0, length: ns.length),
                withTemplate: "https://[REDACTED]@github.com"
            )
        }
        return sanitized
    }
}
