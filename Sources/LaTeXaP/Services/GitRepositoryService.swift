import Foundation

public actor GitRepositoryService {
    public let repositoriesRootDirectory: URL
    private let credentialStore: any GitCredentialStore
    private let allowLocalTestBareRemotes: Bool

    public init(
        repositoriesRootDirectory: URL? = nil,
        credentialStore: any GitCredentialStore = GitKeychainService.shared
    ) {
        self.init(
            repositoriesRootDirectory: repositoriesRootDirectory,
            credentialStore: credentialStore,
            allowLocalTestBareRemotes: false
        )
    }

    init(
        repositoriesRootDirectory: URL? = nil,
        credentialStore: any GitCredentialStore = GitKeychainService.shared,
        allowLocalTestBareRemotes: Bool
    ) {
        if let repositoriesRootDirectory {
            self.repositoriesRootDirectory = repositoriesRootDirectory.standardizedFileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            self.repositoriesRootDirectory = appSupport
                .appendingPathComponent("LaTeXaP", isDirectory: true)
                .appendingPathComponent("Repositories", isDirectory: true)
                .standardizedFileURL
        }
        self.credentialStore = credentialStore
        self.allowLocalTestBareRemotes = allowLocalTestBareRemotes
        try? FileManager.default.createDirectory(at: self.repositoriesRootDirectory, withIntermediateDirectories: true)
    }

    public static func locateGitBinary() -> String? {
        let candidates = [
            "/usr/bin/git",
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func parseRemoteURL(_ raw: String) -> (owner: String, repo: String, normalizedURL: String, suggestedAuth: GitAuthMethod)? {
        GitHubWorkspaceValidator.parseAndValidateRemoteURL(raw, allowLocalBareTestPath: allowLocalTestBareRemotes)
    }

    public func localRepositoryURL(for connection: GitHubRepoConnection) throws -> URL {
        let safeFolder = sanitizedFolderName(connection.localFolderName)
        let repoURL = repositoriesRootDirectory.appendingPathComponent(safeFolder, isDirectory: true).standardizedFileURL
        try assertContained(repoURL, inside: repositoriesRootDirectory)
        return repoURL
    }

    // MARK: - Clone, Open & Discovery

    public func cloneOrOpenRepository(
        connection: GitHubRepoConnection,
        token: String?
    ) async throws -> (repoURL: URL, manifest: GitHubWorkspaceManifest, looseTeXPaths: [String], syncState: GitSyncState) {
        guard let parsedRemote = GitHubWorkspaceValidator.parseAndValidateRemoteURL(
            connection.remoteURLString,
            allowLocalBareTestPath: allowLocalTestBareRemotes
        ) else {
            throw GitStorageError.invalidRemoteURL("Only valid GitHub HTTPS or SSH repository URLs are permitted.")
        }
        guard let branch = GitHubWorkspaceValidator.validatedBranchName(connection.branch) else {
            throw GitStorageError.invalidRemoteURL("Invalid branch name '\(connection.branch)'.")
        }

        try FileManager.default.createDirectory(at: repositoriesRootDirectory, withIntermediateDirectories: true)
        let repoURL = try localRepositoryURL(for: connection)
        let fm = FileManager.default
        let resolvedToken = effectiveToken(explicit: token, connection: connection)

        let gitFolder = repoURL.appendingPathComponent(".git", isDirectory: true)
        var initialSyncState: GitSyncState = .idle(aheadCount: 0, behindCount: 0, lastSync: Date())

        if fm.fileExists(atPath: gitFolder.path) {
            guard !isSymbolicLink(repoURL) else {
                throw GitStorageError.securityViolation("Repository path cannot be a symbolic link.")
            }
            // Refresh remote and pull non-destructively if online
            _ = try? await runGit(
                arguments: ["remote", "set-url", "origin", "--", parsedRemote.normalizedURL],
                in: repoURL,
                authMethod: connection.authMethod,
                token: resolvedToken,
                allowNonZeroExit: true
            )
            initialSyncState = await syncRepository(
                in: repoURL,
                branch: branch,
                token: resolvedToken,
                authMethod: connection.authMethod
            )
        } else {
            if fm.fileExists(atPath: repoURL.path) {
                try? fm.removeItem(at: repoURL)
            }
            let cloneResult = try await runGit(
                arguments: ["clone", "--branch", branch, "--", parsedRemote.normalizedURL, repoURL.path],
                in: repositoriesRootDirectory,
                authMethod: connection.authMethod,
                token: resolvedToken,
                allowNonZeroExit: true
            )
            if cloneResult.exitCode != 0 {
                // Retry generic clone in case target branch doesn't exist yet on an empty repo
                try? fm.removeItem(at: repoURL)
                let fallbackClone = try await runGit(
                    arguments: ["clone", "--", parsedRemote.normalizedURL, repoURL.path],
                    in: repositoriesRootDirectory,
                    authMethod: connection.authMethod,
                    token: resolvedToken,
                    allowNonZeroExit: true
                )
                if fallbackClone.exitCode != 0 {
                    let msg = fallbackClone.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    if isAuthenticationError(msg) {
                        throw GitStorageError.authenticationFailed(msg.isEmpty ? "Authentication failed for \(parsedRemote.normalizedURL)." : msg)
                    }
                    throw GitStorageError.commandFailed(msg.isEmpty ? "Failed to clone \(parsedRemote.normalizedURL)." : msg)
                }
                _ = try? await runGit(
                    arguments: ["checkout", "-B", branch],
                    in: repoURL,
                    authMethod: connection.authMethod,
                    token: resolvedToken,
                    allowNonZeroExit: true
                )
            }
        }

        try ensureStandardWorkspaceFilesIfMissing(in: repoURL, connection: connection)
        let discovery = try discoverProjects(in: repoURL, defaultBranch: branch, repoFullName: connection.fullName)
        return (repoURL, discovery.manifest, discovery.looseTeXPaths, initialSyncState)
    }

    public func discoverProjects(
        in repoURL: URL,
        defaultBranch: String = "main",
        repoFullName: String = ""
    ) throws -> (manifest: GitHubWorkspaceManifest, looseTeXPaths: [String]) {
        guard !isSymbolicLink(repoURL) else {
            throw GitStorageError.securityViolation("Repository root cannot be a symbolic link.")
        }
        let fm = FileManager.default
        let manifestURL = repoURL.appendingPathComponent(".latexap-workspace.json")
        var manifest = GitHubWorkspaceManifest(
            schemaVersion: 1,
            repoFullName: repoFullName,
            defaultBranch: defaultBranch,
            projects: []
        )

        let projectsRoot = repoURL.appendingPathComponent("projects", isDirectory: true)
        if fm.fileExists(atPath: projectsRoot.path), isSymbolicLink(projectsRoot) {
            throw GitStorageError.securityViolation("Repository 'projects' directory cannot be a symbolic link.")
        }
        if fm.fileExists(atPath: projectsRoot.path) {
            try assertContained(projectsRoot, inside: repoURL)
        }

        if fm.fileExists(atPath: manifestURL.path), !isSymbolicLink(manifestURL),
           let data = try? Data(contentsOf: manifestURL),
           let decoded = try? makeJSONDecoder().decode(GitHubWorkspaceManifest.self, from: data) {
            manifest = decoded
            manifest.projects = decoded.projects.filter { proj in
                isValidProjectDescriptor(proj, in: repoURL)
            }
        }

        // Auto-discover any projects/<slug>/project.json not yet in the manifest
        var seenSlugs = Set(manifest.projects.map(\.slug))
        if fm.fileExists(atPath: projectsRoot.path), !isSymbolicLink(projectsRoot),
           let entries = try? fm.contentsOfDirectory(at: projectsRoot, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
            for folder in entries {
                let vals = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard vals?.isDirectory == true, vals?.isSymbolicLink != true else { continue }
                let slug = folder.lastPathComponent
                guard GitHubWorkspaceValidator.isValidProjectSlug(slug), !seenSlugs.contains(slug) else { continue }
                guard (try? assertContained(folder, inside: projectsRoot)) != nil else { continue }

                let projJSON = folder.appendingPathComponent("project.json")
                if fm.fileExists(atPath: projJSON.path), !isSymbolicLink(projJSON),
                   let data = try? Data(contentsOf: projJSON),
                   let desc = try? makeJSONDecoder().decode(AcademicProjectDescriptor.self, from: data) {
                    var normalized = desc
                    normalized.slug = slug
                    normalized.relativePath = "projects/\(slug)"
                    if isValidProjectDescriptor(normalized, in: repoURL) {
                        manifest.projects.append(normalized)
                        seenSlugs.insert(slug)
                    }
                } else {
                    // Folder under projects/ containing .tex files without project.json
                    let mainCandidate = folder.appendingPathComponent("main.tex")
                    if fm.fileExists(atPath: mainCandidate.path), !isSymbolicLink(mainCandidate) {
                        let desc = AcademicProjectDescriptor(
                            slug: slug,
                            displayName: slug.replacingOccurrences(of: "-", with: " ").capitalized
                        )
                        if isValidProjectDescriptor(desc, in: repoURL) {
                            manifest.projects.append(desc)
                            seenSlugs.insert(slug)
                        }
                    }
                }
            }
        }

        manifest.projects.sort { $0.updatedAt > $1.updatedAt }

        // Scan outside projects/ (up to depth 2) for existing .tex files in non-LaTeXaP repos
        var looseTeX: [String] = []
        if let enumerator = fm.enumerator(
            at: repoURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) {
            let repoResolved = repoURL.standardizedFileURL.resolvingSymlinksInPath().path
            let prefix = repoResolved.hasSuffix("/") ? repoResolved : repoResolved + "/"
            while let item = enumerator.nextObject() as? URL {
                let name = item.lastPathComponent
                if name == ".git" || name == "projects" {
                    enumerator.skipDescendants()
                    continue
                }
                let vals = try? item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard vals?.isRegularFile == true,
                      vals?.isSymbolicLink != true,
                      item.pathExtension.lowercased() == "tex" else {
                    continue
                }
                let itemResolved = item.standardizedFileURL.resolvingSymlinksInPath().path
                if itemResolved.hasPrefix(prefix) {
                    let rel = String(itemResolved.dropFirst(prefix.count))
                    if rel.split(separator: "/").count <= 3 {
                        looseTeX.append(rel)
                    }
                }
            }
        }
        looseTeX.sort()
        return (manifest, looseTeX)
    }

    // MARK: - Project Lifecycle

    public func createProject(
        in repoURL: URL,
        connection: GitHubRepoConnection,
        displayName: String,
        customSlug: String? = nil,
        mainContent: String,
        bibContent: String = "",
        templateId: String? = nil,
        rubricTargets: RubricTargetConfig? = nil,
        copyFiguresFrom tempFiguresDir: URL? = nil,
        token: String?
    ) async throws -> (manifest: GitHubWorkspaceManifest, project: AcademicProjectDescriptor, syncState: GitSyncState) {
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            throw GitStorageError.invalidProjectSlug("Project name cannot be empty.")
        }

        let candidateSlug = (customSlug?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? GitHubWorkspaceValidator.slugifyProjectName(cleanName)
        guard GitHubWorkspaceValidator.isValidProjectSlug(candidateSlug) else {
            throw GitStorageError.invalidProjectSlug("Project folder slug '\(candidateSlug)' must use lowercase letters, numbers, and hyphens only.")
        }

        var discovery = try discoverProjects(in: repoURL, defaultBranch: connection.branch, repoFullName: connection.fullName)
        if discovery.manifest.projects.contains(where: { $0.slug == candidateSlug }) {
            throw GitStorageError.duplicateProjectSlug(candidateSlug)
        }

        let projectDir = repoURL.appendingPathComponent("projects/\(candidateSlug)", isDirectory: true).standardizedFileURL
        try assertContained(projectDir, inside: repoURL)
        let figuresDir = projectDir.appendingPathComponent("figures", isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: projectDir.path) {
            throw GitStorageError.duplicateProjectSlug(candidateSlug)
        }

        try fm.createDirectory(at: figuresDir, withIntermediateDirectories: true)

        let now = Date()
        let project = AcademicProjectDescriptor(
            slug: candidateSlug,
            displayName: cleanName,
            relativePath: "projects/\(candidateSlug)",
            mainTexFile: "main.tex",
            bibFile: "references.bib",
            templateId: templateId,
            createdAt: now,
            updatedAt: now,
            rubricTargets: rubricTargets
        )

        let mainURL = projectDir.appendingPathComponent("main.tex")
        try mainContent.write(to: mainURL, atomically: true, encoding: .utf8)

        let trimmedBib = bibContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let bibURL = projectDir.appendingPathComponent("references.bib")
        try (trimmedBib.isEmpty ? "" : trimmedBib + "\n").write(to: bibURL, atomically: true, encoding: .utf8)

        if let tempFiguresDir, fm.fileExists(atPath: tempFiguresDir.path), !isSymbolicLink(tempFiguresDir) {
            let resolvedTempFigs = tempFiguresDir.standardizedFileURL.resolvingSymlinksInPath().path
            let tempFigsPrefix = resolvedTempFigs.hasSuffix("/") ? resolvedTempFigs : resolvedTempFigs + "/"
            let refs = AcademicPreflightService.extractFigurePaths(from: mainContent)
            for ref in refs where ref.path.hasPrefix("figures/") {
                let leaf = String(ref.path.dropFirst("figures/".count))
                guard let validLeaf = AcademicSanitizer.validatedRelativeAssetPath(leaf),
                      !hasSymlinkAlongPath(relativePath: validLeaf, inside: tempFiguresDir) else { continue }
                let src = tempFiguresDir.appendingPathComponent(validLeaf).standardizedFileURL
                let resolvedSrc = src.resolvingSymlinksInPath()
                guard resolvedSrc.path.hasPrefix(tempFigsPrefix) else { continue }
                let srcVals = try? resolvedSrc.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard srcVals?.isRegularFile == true,
                      srcVals?.isSymbolicLink != true,
                      Int64(srcVals?.fileSize ?? 0) <= GitHubWorkspaceValidator.maxGitHubTrackedFileBytes else {
                    continue
                }
                let dest = figuresDir.appendingPathComponent(validLeaf).standardizedFileURL
                guard !isSymbolicLink(dest),
                      (try? assertContained(dest, inside: figuresDir)) != nil else { continue }
                try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard !hasSymlinkAlongPath(relativePath: validLeaf, inside: figuresDir) else { continue }
                try? fm.copyItem(at: resolvedSrc, to: dest)
            }
        }

        try writeProjectDescriptor(project, to: projectDir)
        discovery.manifest.projects.insert(project, at: 0)
        try writeWorkspaceManifest(discovery.manifest, to: repoURL)
        try ensureStandardWorkspaceFilesIfMissing(in: repoURL, connection: connection)

        let commitRes = try await commitProjectChanges(
            in: repoURL,
            connection: connection,
            project: project,
            message: "Initialize \(cleanName)",
            pushAfterCommit: connection.autoPushOnSave,
            token: token
        )

        return (discovery.manifest, project, commitRes.syncState)
    }

    public func importLooseTeXFileIntoProject(
        in repoURL: URL,
        connection: GitHubRepoConnection,
        relativeTeXPath: String,
        displayName: String,
        token: String?
    ) async throws -> (manifest: GitHubWorkspaceManifest, project: AcademicProjectDescriptor, syncState: GitSyncState) {
        guard let validRel = AcademicSanitizer.validatedRelativeAssetPath(relativeTeXPath) else {
            throw GitStorageError.securityViolation("Invalid relative TeX path '\(relativeTeXPath)'.")
        }
        let sourceFile = repoURL.appendingPathComponent(validRel).standardizedFileURL
        try assertContained(sourceFile, inside: repoURL)
        guard !isSymbolicLink(sourceFile) else {
            throw GitStorageError.securityViolation("Cannot import symbolic link file.")
        }
        let content = try String(contentsOf: sourceFile, encoding: .utf8)
        let siblingBib = sourceFile.deletingLastPathComponent().appendingPathComponent("references.bib")
        let bibContent = (!isSymbolicLink(siblingBib) ? (try? String(contentsOf: siblingBib, encoding: .utf8)) : nil) ?? ""

        return try await createProject(
            in: repoURL,
            connection: connection,
            displayName: displayName,
            customSlug: nil,
            mainContent: content,
            bibContent: bibContent,
            templateId: nil,
            rubricTargets: nil,
            copyFiguresFrom: sourceFile.deletingLastPathComponent().appendingPathComponent("figures"),
            token: token
        )
    }

    public func deleteProject(
        in repoURL: URL,
        connection: GitHubRepoConnection,
        project: AcademicProjectDescriptor,
        commitMessage: String? = nil,
        token: String?
    ) async throws -> (manifest: GitHubWorkspaceManifest, syncState: GitSyncState) {
        guard GitHubWorkspaceValidator.isValidProjectSlug(project.slug) else {
            throw GitStorageError.invalidProjectSlug("Invalid project slug '\(project.slug)'.")
        }
        let projectDir = repoURL.appendingPathComponent("projects/\(project.slug)", isDirectory: true).standardizedFileURL
        try assertContained(projectDir, inside: repoURL)

        var discovery = try discoverProjects(in: repoURL, defaultBranch: connection.branch, repoFullName: connection.fullName)
        discovery.manifest.projects.removeAll { $0.slug == project.slug }
        try writeWorkspaceManifest(discovery.manifest, to: repoURL)

        let fm = FileManager.default
        if fm.fileExists(atPath: projectDir.path) {
            try fm.removeItem(at: projectDir)
        }

        let resolvedToken = effectiveToken(explicit: token, connection: connection)
        guard let branch = GitHubWorkspaceValidator.validatedBranchName(connection.branch) else {
            throw GitStorageError.invalidRemoteURL("Invalid branch '\(connection.branch)'.")
        }

        _ = try await runGit(
            arguments: ["add", "-A", "--", "projects/\(project.slug)", ".latexap-workspace.json"],
            in: repoURL,
            authMethod: connection.authMethod,
            token: resolvedToken
        )

        let msg = (commitMessage?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Remove project \(project.displayName)"

        _ = try await runGitCommit(message: msg, in: repoURL)

        let syncState: GitSyncState
        if connection.autoPushOnSave {
            syncState = await pushWithRebaseRecovery(
                in: repoURL,
                branch: branch,
                token: resolvedToken,
                authMethod: connection.authMethod
            )
        } else {
            let counts = await aheadBehindCounts(in: repoURL, branch: branch)
            syncState = .idle(aheadCount: counts.ahead, behindCount: counts.behind, lastSync: connection.lastSyncedAt)
        }
        return (discovery.manifest, syncState)
    }

    // MARK: - Save, Stage, Commit & Sync

    public func updateGitIgnore(in repoURL: URL, includePDFs: Bool) throws {
        let gitIgnoreURL = repoURL.appendingPathComponent(".gitignore")
        guard !isSymbolicLink(gitIgnoreURL) else {
            throw GitStorageError.securityViolation(".gitignore cannot be a symbolic link.")
        }
        try GitHubWorkspaceValidator.laTeXGitIgnore(includePDFs: includePDFs)
            .write(to: gitIgnoreURL, atomically: true, encoding: .utf8)
    }

    public func changedFiles(
        in repoURL: URL,
        projectRelativePath: String?
    ) async throws -> [GitFileChange] {
        var args = ["status", "--porcelain=v1", "-uall"]
        if let projectRelativePath, !projectRelativePath.isEmpty {
            args.append("--")
            args.append(projectRelativePath)
        }
        let result = try await runGit(
            arguments: args,
            in: repoURL,
            authMethod: .sshKey,
            token: nil
        )
        return Self.parsePorcelainStatus(result.stdout)
    }

    public func commitProjectChanges(
        in repoURL: URL,
        connection: GitHubRepoConnection,
        project: AcademicProjectDescriptor,
        message: String,
        pushAfterCommit: Bool,
        token: String?
    ) async throws -> (committed: Bool, sha: String?, syncState: GitSyncState) {
        guard GitHubWorkspaceValidator.isValidProjectSlug(project.slug) else {
            throw GitStorageError.invalidProjectSlug("Invalid project slug '\(project.slug)'.")
        }
        guard let branch = GitHubWorkspaceValidator.validatedBranchName(connection.branch) else {
            throw GitStorageError.invalidRemoteURL("Invalid branch name '\(connection.branch)'.")
        }

        let relProjectDir = "projects/\(project.slug)"
        let projectsRoot = repoURL.appendingPathComponent("projects", isDirectory: true).standardizedFileURL
        guard !isSymbolicLink(projectsRoot) else {
            throw GitStorageError.securityViolation("Repository 'projects' directory cannot be a symbolic link.")
        }
        let projectDir = repoURL.appendingPathComponent(relProjectDir, isDirectory: true).standardizedFileURL
        try assertContained(projectDir, inside: repoURL)
        try checkStagingSizeAndSymlinks(in: projectDir)

        let resolvedToken = effectiveToken(explicit: token, connection: connection)

        // Check whether any real file or untracked metadata changed BEFORE bumping updatedAt timestamps
        let workingTreeStatus = try await runGit(
            arguments: ["status", "--porcelain=v1", "-uall", "--", relProjectDir, ".latexap-workspace.json", ".gitignore"],
            in: repoURL,
            authMethod: connection.authMethod,
            token: resolvedToken
        )
        if workingTreeStatus.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let counts = await aheadBehindCounts(in: repoURL, branch: branch)
            return (false, nil, .idle(aheadCount: counts.ahead, behindCount: counts.behind, lastSync: connection.lastSyncedAt))
        }

        var updatedProject = project
        updatedProject.updatedAt = Date()
        try writeProjectDescriptor(updatedProject, to: projectDir)

        var discovery = try discoverProjects(in: repoURL, defaultBranch: branch, repoFullName: connection.fullName)
        if let idx = discovery.manifest.projects.firstIndex(where: { $0.slug == project.slug }) {
            discovery.manifest.projects[idx] = updatedProject
        } else {
            discovery.manifest.projects.insert(updatedProject, at: 0)
        }
        try writeWorkspaceManifest(discovery.manifest, to: repoURL)

        _ = try await runGit(
            arguments: ["add", "-A", "--", relProjectDir, ".latexap-workspace.json", ".gitignore"],
            in: repoURL,
            authMethod: connection.authMethod,
            token: resolvedToken
        )

        let stagedCheck = try await runGit(
            arguments: ["diff", "--cached", "--name-only", "--", relProjectDir, ".latexap-workspace.json", ".gitignore"],
            in: repoURL,
            authMethod: connection.authMethod,
            token: resolvedToken
        )
        let stagedFiles = stagedCheck.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if stagedFiles.isEmpty {
            let counts = await aheadBehindCounts(in: repoURL, branch: branch)
            return (false, nil, .idle(aheadCount: counts.ahead, behindCount: counts.behind, lastSync: connection.lastSyncedAt))
        }

        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalMessage = cleanMessage.isEmpty
            ? GitHubWorkspaceValidator.defaultCommitMessage(projectName: project.displayName)
            : cleanMessage

        try await runGitCommit(message: finalMessage, in: repoURL)
        let shaResult = try await runGit(arguments: ["rev-parse", "HEAD"], in: repoURL, authMethod: .sshKey, token: nil)
        let sha = shaResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        let syncState: GitSyncState
        if pushAfterCommit {
            syncState = await pushWithRebaseRecovery(
                in: repoURL,
                branch: branch,
                token: resolvedToken,
                authMethod: connection.authMethod
            )
        } else {
            let counts = await aheadBehindCounts(in: repoURL, branch: branch)
            syncState = .idle(aheadCount: counts.ahead, behindCount: counts.behind, lastSync: connection.lastSyncedAt)
        }

        return (true, sha, syncState)
    }

    public func syncRepository(
        in repoURL: URL,
        branch: String,
        token: String?,
        authMethod: GitAuthMethod
    ) async -> GitSyncState {
        guard let validBranch = GitHubWorkspaceValidator.validatedBranchName(branch) else {
            return .failed(message: "Invalid branch name '\(branch)'.")
        }

        do {
            let fetchRes = try await runGit(
                arguments: ["fetch", "origin", "--", validBranch],
                in: repoURL,
                authMethod: authMethod,
                token: token,
                allowNonZeroExit: true
            )
            if fetchRes.exitCode != 0 {
                let err = fetchRes.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if isOfflineNetworkError(err) {
                    let counts = await aheadBehindCounts(in: repoURL, branch: validBranch)
                    return .offlinePendingPush(aheadCount: counts.ahead)
                }
                if isAuthenticationError(err) {
                    return .failed(message: "Authentication failed for GitHub. Update your token or sign in with gh CLI.")
                }
                // Empty remote branch without commits yet is non-fatal
                if !err.localizedCaseInsensitiveContains("couldn't find remote ref") {
                    return .failed(message: err.isEmpty ? "Fetch failed." : err)
                }
            }

            let countsBefore = await aheadBehindCounts(in: repoURL, branch: validBranch)
            if countsBefore.behind > 0 {
                let pullRes = try await runGit(
                    arguments: ["pull", "--rebase", "--autostash", "origin", validBranch],
                    in: repoURL,
                    authMethod: authMethod,
                    token: token,
                    allowNonZeroExit: true
                )
                if pullRes.exitCode != 0 {
                    let conflicts = await currentConflictedFiles(in: repoURL)
                    _ = try? await runGit(arguments: ["rebase", "--abort"], in: repoURL, authMethod: .sshKey, token: nil, allowNonZeroExit: true)
                    if !conflicts.isEmpty {
                        return .conflict(
                            conflictedFiles: conflicts,
                            message: "GitHub has conflicting edits in \(conflicts.count) file(s)."
                        )
                    }
                    let err = pullRes.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    if isOfflineNetworkError(err) {
                        return .offlinePendingPush(aheadCount: countsBefore.ahead)
                    }
                    return .failed(message: err.isEmpty ? "Pull failed." : err)
                }
            }

            let countsAfterPull = await aheadBehindCounts(in: repoURL, branch: validBranch)
            if countsAfterPull.ahead > 0 {
                return await pushWithRebaseRecovery(
                    in: repoURL,
                    branch: validBranch,
                    token: token,
                    authMethod: authMethod
                )
            }

            return .idle(aheadCount: 0, behindCount: 0, lastSync: Date())
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Conflict Resolution

    public func resolveConflict(
        in repoURL: URL,
        connection: GitHubRepoConnection,
        project: AcademicProjectDescriptor,
        choices: [String: GitConflictResolutionChoice],
        keepBothCopies: Bool,
        token: String?
    ) async throws -> GitSyncState {
        guard let branch = GitHubWorkspaceValidator.validatedBranchName(connection.branch) else {
            throw GitStorageError.invalidRemoteURL("Invalid branch '\(connection.branch)'.")
        }
        let resolvedToken = effectiveToken(explicit: token, connection: connection)

        // Ensure no lingering merge/rebase state exists
        _ = try? await runGit(arguments: ["rebase", "--abort"], in: repoURL, authMethod: .sshKey, token: nil, allowNonZeroExit: true)
        _ = try? await runGit(arguments: ["merge", "--abort"], in: repoURL, authMethod: .sshKey, token: nil, allowNonZeroExit: true)

        // Commit any dirty local project edits before starting merge so working tree stays safe
        let relProjectDir = "projects/\(project.slug)"
        _ = try await runGit(
            arguments: ["add", "-A", "--", relProjectDir, ".latexap-workspace.json", ".gitignore"],
            in: repoURL,
            authMethod: connection.authMethod,
            token: resolvedToken
        )
        let preMergeStaged = try await runGit(
            arguments: ["diff", "--cached", "--name-only"],
            in: repoURL,
            authMethod: .sshKey,
            token: nil
        )
        if !preMergeStaged.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try await runGitCommit(
                message: "Save local edits before resolving conflict for \(project.displayName)",
                in: repoURL
            )
        }

        _ = try await runGit(
            arguments: ["fetch", "origin", "--", branch],
            in: repoURL,
            authMethod: connection.authMethod,
            token: resolvedToken
        )

        // Merge with --no-commit --no-ff: in git merge, --ours is ALWAYS local HEAD and --theirs is ALWAYS origin/<branch>
        let mergeRes = try await runGit(
            arguments: ["merge", "--no-commit", "--no-ff", "origin/\(branch)"],
            in: repoURL,
            authMethod: .sshKey,
            token: nil,
            allowNonZeroExit: true
        )

        let unmergedPaths = await currentConflictedFiles(in: repoURL)
        let allCandidatePaths = Set(unmergedPaths).union(choices.keys)

        for relPath in allCandidatePaths {
            if relPath == ".latexap-workspace.json" {
                try await mergeWorkspaceManifestConflict(in: repoURL, branch: branch)
                continue
            }

            guard let validRel = AcademicSanitizer.validatedRelativeAssetPath(relPath) else {
                continue
            }

            if validRel.hasPrefix("\(relProjectDir)/") {
                if keepBothCopies {
                    _ = try? await runGit(arguments: ["checkout", "--ours", "--", validRel], in: repoURL, authMethod: .sshKey, token: nil, allowNonZeroExit: true)
                    _ = try? await runGit(arguments: ["add", "--", validRel], in: repoURL, authMethod: .sshKey, token: nil, allowNonZeroExit: true)

                    let remoteShow = try await runGitRaw(
                        arguments: ["show", "origin/\(branch):\(validRel)"],
                        in: repoURL,
                        authMethod: .sshKey,
                        token: nil,
                        allowNonZeroExit: true
                    )
                    if remoteShow.exitCode == 0 {
                        let targetURL = repoURL.appendingPathComponent(validRel).standardizedFileURL
                        let stem = targetURL.deletingPathExtension().lastPathComponent
                        let ext = targetURL.pathExtension
                        let backupLeaf = ext.isEmpty ? "\(stem)-remote" : "\(stem)-remote.\(ext)"
                        let backupURL = targetURL.deletingLastPathComponent().appendingPathComponent(backupLeaf).standardizedFileURL
                        try assertContained(backupURL, inside: repoURL)
                        guard !isSymbolicLink(backupURL) else {
                            throw GitStorageError.securityViolation("Cannot write conflict backup to a symbolic link.")
                        }
                        try remoteShow.stdoutData.write(to: backupURL, options: .atomic)
                        let parentRel = (validRel as NSString).deletingLastPathComponent
                        let backupRel = parentRel.isEmpty ? backupLeaf : "\(parentRel)/\(backupLeaf)"
                        _ = try? await runGit(arguments: ["add", "--", backupRel], in: repoURL, authMethod: .sshKey, token: nil, allowNonZeroExit: true)
                    }
                } else if choices[relPath] == .useRemote {
                    let checkoutRemote = try await runGit(
                        arguments: ["checkout", "--theirs", "--", validRel],
                        in: repoURL,
                        authMethod: .sshKey,
                        token: nil,
                        allowNonZeroExit: true
                    )
                    if checkoutRemote.exitCode != 0 {
                        let remoteShow = try await runGitRaw(
                            arguments: ["show", "origin/\(branch):\(validRel)"],
                            in: repoURL,
                            authMethod: .sshKey,
                            token: nil,
                            allowNonZeroExit: true
                        )
                        if remoteShow.exitCode == 0 {
                            let destURL = repoURL.appendingPathComponent(validRel).standardizedFileURL
                            try assertContained(destURL, inside: repoURL)
                            guard !isSymbolicLink(destURL) else { continue }
                            try remoteShow.stdoutData.write(to: destURL, options: .atomic)
                        }
                    }
                    _ = try await runGit(arguments: ["add", "--", validRel], in: repoURL, authMethod: .sshKey, token: nil)
                } else {
                    _ = try? await runGit(arguments: ["checkout", "--ours", "--", validRel], in: repoURL, authMethod: .sshKey, token: nil, allowNonZeroExit: true)
                    _ = try await runGit(arguments: ["add", "--", validRel], in: repoURL, authMethod: .sshKey, token: nil)
                }
            } else if unmergedPaths.contains(relPath) {
                _ = try? await runGit(arguments: ["checkout", "--ours", "--", validRel], in: repoURL, authMethod: .sshKey, token: nil, allowNonZeroExit: true)
                _ = try? await runGit(arguments: ["add", "--", validRel], in: repoURL, authMethod: .sshKey, token: nil, allowNonZeroExit: true)
            }
        }

        let remainingConflicts = await currentConflictedFiles(in: repoURL)
        if !remainingConflicts.isEmpty {
            _ = try? await runGit(arguments: ["merge", "--abort"], in: repoURL, authMethod: .sshKey, token: nil, allowNonZeroExit: true)
            return .conflict(conflictedFiles: remainingConflicts, message: "Unresolved merge conflicts remain in \(remainingConflicts.joined(separator: ", ")).")
        }

        let mergeHeadExists = FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(".git/MERGE_HEAD").path)
        let stagedAfterMerge = try await runGit(
            arguments: ["diff", "--cached", "--name-only"],
            in: repoURL,
            authMethod: .sshKey,
            token: nil
        )
        if mergeHeadExists || mergeRes.exitCode != 0 || !stagedAfterMerge.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try await runGitCommit(
                message: keepBothCopies
                    ? "Resolve conflict (keep both versions) for \(project.displayName)"
                    : "Resolve conflict for \(project.displayName)",
                in: repoURL
            )
        }

        return await pushWithRebaseRecovery(
            in: repoURL,
            branch: branch,
            token: resolvedToken,
            authMethod: connection.authMethod
        )
    }

    private func mergeWorkspaceManifestConflict(in repoURL: URL, branch: String) async throws {
        let localShow = try await runGit(arguments: ["show", "HEAD:.latexap-workspace.json"], in: repoURL, authMethod: .sshKey, token: nil, allowNonZeroExit: true)
        let remoteShow = try await runGit(arguments: ["show", "origin/\(branch):.latexap-workspace.json"], in: repoURL, authMethod: .sshKey, token: nil, allowNonZeroExit: true)

        let decoder = makeJSONDecoder()
        let localManifest = localShow.exitCode == 0 ? (try? decoder.decode(GitHubWorkspaceManifest.self, from: Data(localShow.stdout.utf8))) : nil
        let remoteManifest = remoteShow.exitCode == 0 ? (try? decoder.decode(GitHubWorkspaceManifest.self, from: Data(remoteShow.stdout.utf8))) : nil

        if var merged = localManifest ?? remoteManifest {
            var bySlug: [String: AcademicProjectDescriptor] = [:]
            for p in remoteManifest?.projects ?? [] {
                bySlug[p.slug] = p
            }
            for p in localManifest?.projects ?? [] {
                if let existing = bySlug[p.slug] {
                    bySlug[p.slug] = p.updatedAt >= existing.updatedAt ? p : existing
                } else {
                    bySlug[p.slug] = p
                }
            }
            merged.projects = bySlug.values.sorted { $0.updatedAt > $1.updatedAt }
            try writeWorkspaceManifest(merged, to: repoURL)
        } else {
            _ = try? await runGit(arguments: ["checkout", "--ours", "--", ".latexap-workspace.json"], in: repoURL, authMethod: .sshKey, token: nil, allowNonZeroExit: true)
        }
        _ = try await runGit(arguments: ["add", "--", ".latexap-workspace.json"], in: repoURL, authMethod: .sshKey, token: nil)
    }

    // MARK: - History, Diff & Non-Destructive Restore

    public func projectHistory(
        in repoURL: URL,
        projectRelativePath: String,
        limit: Int = 50
    ) async throws -> [GitCommitRecord] {
        guard let validRel = AcademicSanitizer.validatedRelativeAssetPath(projectRelativePath) else {
            throw GitStorageError.securityViolation("Invalid project path '\(projectRelativePath)'.")
        }
        let clampedLimit = min(max(limit, 1), 200)

        let unpushedRes = try await runGit(
            arguments: ["rev-list", "@{upstream}..HEAD"],
            in: repoURL,
            authMethod: .sshKey,
            token: nil,
            allowNonZeroExit: true
        )
        let unpushedSHAs: Set<String>
        if unpushedRes.exitCode == 0 {
            unpushedSHAs = Set(unpushedRes.stdout.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        } else {
            let allLocalRes = try? await runGit(
                arguments: ["rev-list", "HEAD"],
                in: repoURL,
                authMethod: .sshKey,
                token: nil,
                allowNonZeroExit: true
            )
            unpushedSHAs = Set((allLocalRes?.stdout ?? "").components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        }

        let logRes = try await runGit(
            arguments: [
                "log",
                "-n", String(clampedLimit),
                "--date=unix",
                "--pretty=format:%x1e%H%x1f%h%x1f%an%x1f%at%x1f%s",
                "--name-only",
                "--",
                validRel
            ],
            in: repoURL,
            authMethod: .sshKey,
            token: nil,
            allowNonZeroExit: true
        )
        if logRes.exitCode != 0 {
            // Repository with no commits yet
            return []
        }

        return Self.parseGitLogOutput(logRes.stdout, unpushedSHAs: unpushedSHAs)
    }

    public func fileContentAtCommit(
        in repoURL: URL,
        commitSHA: String,
        relativeFilePath: String
    ) async throws -> String {
        guard let validSHA = GitHubWorkspaceValidator.validatedCommitSHA(commitSHA) else {
            throw GitStorageError.securityViolation("Invalid commit SHA '\(commitSHA)'.")
        }
        guard let validRel = AcademicSanitizer.validatedRelativeAssetPath(relativeFilePath) else {
            throw GitStorageError.securityViolation("Invalid relative file path '\(relativeFilePath)'.")
        }
        let res = try await runGit(
            arguments: ["show", "\(validSHA):\(validRel)"],
            in: repoURL,
            authMethod: .sshKey,
            token: nil
        )
        return res.stdout
    }

    public func commitDiff(
        in repoURL: URL,
        commitSHA: String,
        projectRelativePath: String
    ) async throws -> String {
        guard let validSHA = GitHubWorkspaceValidator.validatedCommitSHA(commitSHA) else {
            throw GitStorageError.securityViolation("Invalid commit SHA '\(commitSHA)'.")
        }
        guard let validRel = AcademicSanitizer.validatedRelativeAssetPath(projectRelativePath) else {
            throw GitStorageError.securityViolation("Invalid relative project path '\(projectRelativePath)'.")
        }
        let res = try await runGit(
            arguments: ["show", "--stat", "--patch", validSHA, "--", validRel],
            in: repoURL,
            authMethod: .sshKey,
            token: nil
        )
        return res.stdout
    }

    public func restoreProjectToCommit(
        in repoURL: URL,
        connection: GitHubRepoConnection,
        project: AcademicProjectDescriptor,
        commit: GitCommitRecord,
        pushAfterRestore: Bool,
        token: String?
    ) async throws -> GitSyncState {
        guard let validSHA = GitHubWorkspaceValidator.validatedCommitSHA(commit.id) else {
            throw GitStorageError.securityViolation("Invalid commit SHA '\(commit.id)'.")
        }
        guard GitHubWorkspaceValidator.isValidProjectSlug(project.slug) else {
            throw GitStorageError.invalidProjectSlug("Invalid project slug '\(project.slug)'.")
        }

        let relProjectDir = "projects/\(project.slug)"
        let projectDir = repoURL.appendingPathComponent(relProjectDir, isDirectory: true).standardizedFileURL
        try assertContained(projectDir, inside: repoURL)

        _ = try await runGit(
            arguments: ["checkout", validSHA, "--", relProjectDir],
            in: repoURL,
            authMethod: .sshKey,
            token: nil
        )

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let restoreMessage = "Restore \(project.displayName) to version from \(formatter.string(from: commit.date)) (\(commit.shortHash))"

        let res = try await commitProjectChanges(
            in: repoURL,
            connection: connection,
            project: project,
            message: restoreMessage,
            pushAfterCommit: pushAfterRestore,
            token: token
        )
        return res.syncState
    }

    // MARK: - Static Parsing Helpers (Tested Directly)

    public static func parsePorcelainStatus(_ output: String) -> [GitFileChange] {
        var changes: [GitFileChange] = []
        for rawLine in output.components(separatedBy: .newlines) {
            guard rawLine.count >= 4 else { continue }
            let statusPart = String(rawLine.prefix(2)).trimmingCharacters(in: .whitespaces)
            var pathPart = String(rawLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if let arrowRange = pathPart.range(of: " -> ") {
                pathPart = String(pathPart[arrowRange.upperBound...])
            }
            if pathPart.hasPrefix("\""), pathPart.hasSuffix("\""), pathPart.count >= 2 {
                pathPart = String(pathPart.dropFirst().dropLast())
            }
            let normalizedStatus: String
            if statusPart.contains("U") || statusPart == "AA" || statusPart == "DD" {
                normalizedStatus = "U"
            } else if statusPart.contains("?") || statusPart.contains("A") {
                normalizedStatus = "A"
            } else if statusPart.contains("D") {
                normalizedStatus = "D"
            } else if statusPart.contains("R") {
                normalizedStatus = "R"
            } else {
                normalizedStatus = "M"
            }
            if !pathPart.isEmpty {
                changes.append(GitFileChange(relativePath: pathPart, status: normalizedStatus))
            }
        }
        return changes
    }

    public static func parseGitLogOutput(_ output: String, unpushedSHAs: Set<String> = []) -> [GitCommitRecord] {
        var records: [GitCommitRecord] = []
        let chunks = output.split(separator: "\u{1e}", omittingEmptySubsequences: true)
        for chunk in chunks {
            let lines = String(chunk).components(separatedBy: .newlines)
            guard let header = lines.first else { continue }
            let fields = header.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5 else { continue }
            let sha = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let shortHash = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let author = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let ts = TimeInterval(fields[3].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let message = fields[4].trimmingCharacters(in: .whitespacesAndNewlines)
            let files = lines.dropFirst()
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !sha.isEmpty else { continue }
            records.append(
                GitCommitRecord(
                    id: sha,
                    shortHash: shortHash.isEmpty ? String(sha.prefix(7)) : shortHash,
                    message: message,
                    authorName: author.isEmpty ? "Author" : author,
                    date: Date(timeIntervalSince1970: ts),
                    changedFiles: files,
                    isPushed: !unpushedSHAs.contains(sha)
                )
            )
        }
        return records
    }

    // MARK: - Private Helpers

    private func ensureStandardWorkspaceFilesIfMissing(in repoURL: URL, connection: GitHubRepoConnection) throws {
        let fm = FileManager.default
        let gitIgnoreURL = repoURL.appendingPathComponent(".gitignore")
        if !fm.fileExists(atPath: gitIgnoreURL.path) && !isSymbolicLink(gitIgnoreURL) {
            try GitHubWorkspaceValidator.laTeXGitIgnore(includePDFs: connection.includePDFsInCommits)
                .write(to: gitIgnoreURL, atomically: true, encoding: .utf8)
        }
        let manifestURL = repoURL.appendingPathComponent(".latexap-workspace.json")
        if !fm.fileExists(atPath: manifestURL.path) && !isSymbolicLink(manifestURL) {
            let discovered = try discoverProjects(in: repoURL, defaultBranch: connection.branch, repoFullName: connection.fullName)
            try writeWorkspaceManifest(discovered.manifest, to: repoURL)
        }
    }

    private func writeWorkspaceManifest(_ manifest: GitHubWorkspaceManifest, to repoURL: URL) throws {
        let manifestURL = repoURL.appendingPathComponent(".latexap-workspace.json").standardizedFileURL
        try assertContained(manifestURL, inside: repoURL)
        guard !isSymbolicLink(manifestURL) else {
            throw GitStorageError.securityViolation(".latexap-workspace.json cannot be a symbolic link.")
        }
        let data = try makeJSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    private func writeProjectDescriptor(_ project: AcademicProjectDescriptor, to projectDir: URL) throws {
        let projectJSON = projectDir.appendingPathComponent("project.json").standardizedFileURL
        guard !isSymbolicLink(projectJSON) else {
            throw GitStorageError.securityViolation("project.json cannot be a symbolic link.")
        }
        let data = try makeJSONEncoder().encode(project)
        try data.write(to: projectJSON, options: .atomic)
    }

    private func pushWithRebaseRecovery(
        in repoURL: URL,
        branch: String,
        token: String?,
        authMethod: GitAuthMethod
    ) async -> GitSyncState {
        do {
            let pushRes = try await runGit(
                arguments: ["push", "-u", "origin", "--", branch],
                in: repoURL,
                authMethod: authMethod,
                token: token,
                allowNonZeroExit: true
            )
            if pushRes.exitCode == 0 {
                return .idle(aheadCount: 0, behindCount: 0, lastSync: Date())
            }

            let err = pushRes.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if isOfflineNetworkError(err) {
                let counts = await aheadBehindCounts(in: repoURL, branch: branch)
                return .offlinePendingPush(aheadCount: max(1, counts.ahead))
            }
            if isAuthenticationError(err) {
                return .failed(message: "GitHub authentication failed. Update your token in Keychain or gh CLI.")
            }

            // Non-fast-forward: fetch & pull --rebase --autostash, then retry push
            if err.localizedCaseInsensitiveContains("fetch first") ||
               err.localizedCaseInsensitiveContains("non-fast-forward") ||
               err.localizedCaseInsensitiveContains("rejected") {
                let pullRes = try await runGit(
                    arguments: ["pull", "--rebase", "--autostash", "origin", branch],
                    in: repoURL,
                    authMethod: authMethod,
                    token: token,
                    allowNonZeroExit: true
                )
                if pullRes.exitCode != 0 {
                    let conflicts = await currentConflictedFiles(in: repoURL)
                    _ = try? await runGit(arguments: ["rebase", "--abort"], in: repoURL, authMethod: .sshKey, token: nil, allowNonZeroExit: true)
                    if !conflicts.isEmpty {
                        return .conflict(
                            conflictedFiles: conflicts,
                            message: "Conflict with remote changes in \(conflicts.joined(separator: ", "))."
                        )
                    }
                    let pullErr = pullRes.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    return .failed(message: pullErr.isEmpty ? "Rebase failed while syncing with GitHub." : pullErr)
                }

                let retryRes = try await runGit(
                    arguments: ["push", "-u", "origin", "--", branch],
                    in: repoURL,
                    authMethod: authMethod,
                    token: token,
                    allowNonZeroExit: true
                )
                if retryRes.exitCode == 0 {
                    return .idle(aheadCount: 0, behindCount: 0, lastSync: Date())
                }
                let retryErr = retryRes.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if isOfflineNetworkError(retryErr) {
                    let counts = await aheadBehindCounts(in: repoURL, branch: branch)
                    return .offlinePendingPush(aheadCount: max(1, counts.ahead))
                }
                return .failed(message: retryErr.isEmpty ? "Push retry failed." : retryErr)
            }

            return .failed(message: err.isEmpty ? "Git push failed." : err)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    private func aheadBehindCounts(in repoURL: URL, branch: String) async -> (ahead: Int, behind: Int) {
        guard let res = try? await runGit(
            arguments: ["rev-list", "--left-right", "--count", "HEAD...@{upstream}"],
            in: repoURL,
            authMethod: .sshKey,
            token: nil,
            allowNonZeroExit: true
        ), res.exitCode == 0 else {
            // Fallback: count local commits if no upstream tracking branch is configured yet
            if let localHead = try? await runGit(
                arguments: ["rev-list", "--count", "HEAD"],
                in: repoURL,
                authMethod: .sshKey,
                token: nil,
                allowNonZeroExit: true
            ), localHead.exitCode == 0 {
                let count = Int(localHead.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                // Check whether origin/<branch> exists
                let hasRemote = (try? await runGit(
                    arguments: ["rev-parse", "--verify", "origin/\(branch)"],
                    in: repoURL,
                    authMethod: .sshKey,
                    token: nil,
                    allowNonZeroExit: true
                ))?.exitCode == 0
                return (hasRemote ? 0 : count, 0)
            }
            return (0, 0)
        }

        let parts = res.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
        guard parts.count == 2,
              let ahead = Int(parts[0]),
              let behind = Int(parts[1]) else {
            return (0, 0)
        }
        return (ahead, behind)
    }

    private func currentConflictedFiles(in repoURL: URL) async -> [String] {
        guard let res = try? await runGit(
            arguments: ["diff", "--name-only", "--diff-filter=U"],
            in: repoURL,
            authMethod: .sshKey,
            token: nil,
            allowNonZeroExit: true
        ) else {
            return []
        }
        return res.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func runGitCommit(message: String, in repoURL: URL) async throws {
        var extraEnv: [String: String] = [:]
        let nameCheck = try? await runGit(
            arguments: ["config", "--get", "user.name"],
            in: repoURL,
            authMethod: .sshKey,
            token: nil,
            allowNonZeroExit: true
        )
        let emailCheck = try? await runGit(
            arguments: ["config", "--get", "user.email"],
            in: repoURL,
            authMethod: .sshKey,
            token: nil,
            allowNonZeroExit: true
        )
        if nameCheck?.exitCode != 0 || (nameCheck?.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            extraEnv["GIT_AUTHOR_NAME"] = "LaTeXaP User"
            extraEnv["GIT_COMMITTER_NAME"] = "LaTeXaP User"
        }
        if emailCheck?.exitCode != 0 || (emailCheck?.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            extraEnv["GIT_AUTHOR_EMAIL"] = "latexap@users.noreply.github.com"
            extraEnv["GIT_COMMITTER_EMAIL"] = "latexap@users.noreply.github.com"
        }

        _ = try await runGit(
            arguments: ["commit", "-m", message],
            in: repoURL,
            authMethod: .sshKey,
            token: nil,
            extraEnvironment: extraEnv
        )
    }

    private func runGit(
        arguments: [String],
        in workingDirectory: URL,
        authMethod: GitAuthMethod,
        token: String?,
        extraEnvironment: [String: String] = [:],
        allowNonZeroExit: Bool = false
    ) async throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let raw = try await runGitRaw(
            arguments: arguments,
            in: workingDirectory,
            authMethod: authMethod,
            token: token,
            extraEnvironment: extraEnvironment,
            allowNonZeroExit: allowNonZeroExit
        )
        let stdoutStr = GitHubWorkspaceValidator.redactSensitiveToken(
            String(data: raw.stdoutData, encoding: .utf8) ?? "",
            token: token
        )
        let stderrStr = GitHubWorkspaceValidator.redactSensitiveToken(
            String(data: raw.stderrData, encoding: .utf8) ?? "",
            token: token
        )
        return (raw.exitCode, stdoutStr, stderrStr)
    }

    private func runGitRaw(
        arguments: [String],
        in workingDirectory: URL,
        authMethod: GitAuthMethod,
        token: String?,
        extraEnvironment: [String: String] = [:],
        allowNonZeroExit: Bool = false
    ) async throws -> (exitCode: Int32, stdoutData: Data, stderrData: Data) {
        guard let gitPath = Self.locateGitBinary() else {
            throw GitStorageError.gitBinaryNotFound
        }

        let fm = FileManager.default
        var fullArgs: [String] = []
        if !allowLocalTestBareRemotes {
            fullArgs.append(contentsOf: ["-c", "protocol.file.allow=never"])
        }
        fullArgs.append(contentsOf: arguments)

        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GCM_INTERACTIVE"] = "never"
        env["SSH_ASKPASS_REQUIRE"] = "never"
        env["LC_ALL"] = "C"
        for (k, v) in extraEnvironment {
            env[k] = v
        }

        var askpassDir: URL?
        if authMethod == .sshKey {
            env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"
        } else if let token, !token.isEmpty {
            let tmpDir = fm.temporaryDirectory.appendingPathComponent("latexap-askpass-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let scriptURL = tmpDir.appendingPathComponent("askpass.sh")
            let scriptBody = """
            #!/bin/sh
            case "$1" in
              *Username*|*username*) printf '%s\\n' 'x-access-token' ;;
              *) printf '%s\\n' "$LATEXAP_GIT_TOKEN" ;;
            esac
            """
            try scriptBody.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
            env["GIT_ASKPASS"] = scriptURL.path
            env["LATEXAP_GIT_TOKEN"] = token
            askpassDir = tmpDir
        }
        defer {
            if let askpassDir {
                try? fm.removeItem(at: askpassDir)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.currentDirectoryURL = workingDirectory
        process.arguments = fullArgs
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let (exitCode, outData, errData): (Int32, Data, Data) = try await withCheckedThrowingContinuation { continuation in
            let pipeQueue = DispatchQueue(label: "com.latexap.git.pipe", qos: .userInitiated, attributes: .concurrent)
            let group = DispatchGroup()
            let boxLock = NSLock()
            var stdoutBox = Data()
            var stderrBox = Data()

            group.enter()
            process.terminationHandler = { _ in
                group.leave()
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                group.leave()
                continuation.resume(throwing: error)
                return
            }

            group.enter()
            pipeQueue.async {
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                boxLock.lock()
                stdoutBox = data
                boxLock.unlock()
                group.leave()
            }

            group.enter()
            pipeQueue.async {
                let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                boxLock.lock()
                stderrBox = data
                boxLock.unlock()
                group.leave()
            }

            group.notify(queue: pipeQueue) {
                boxLock.lock()
                let out = stdoutBox
                let err = stderrBox
                boxLock.unlock()
                continuation.resume(returning: (process.terminationStatus, out, err))
            }
        }

        if exitCode != 0 && !allowNonZeroExit {
            let stderrStr = GitHubWorkspaceValidator.redactSensitiveToken(
                String(data: errData, encoding: .utf8) ?? "",
                token: token
            )
            let msg = stderrStr.trimmingCharacters(in: .whitespacesAndNewlines)
            if isAuthenticationError(msg) {
                throw GitStorageError.authenticationFailed(msg.isEmpty ? "Git authentication failed." : msg)
            }
            throw GitStorageError.commandFailed(msg.isEmpty ? "git \(arguments.first ?? "") failed with status \(exitCode)." : msg)
        }

        return (exitCode, outData, errData)
    }

    private func effectiveToken(explicit: String?, connection: GitHubRepoConnection) -> String? {
        if let explicit, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicit.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        switch connection.authMethod {
        case .personalAccessToken:
            return credentialStore.loadToken(forAccount: connection.fullName)
                ?? credentialStore.loadToken(forAccount: "github.com")
        case .ghCLI:
            return credentialStore.detectGitHubCLIToken()
                ?? credentialStore.loadToken(forAccount: connection.fullName)
        case .sshKey:
            return nil
        }
    }

    private func checkStagingSizeAndSymlinks(in projectDir: URL) throws {
        let fm = FileManager.default
        guard !isSymbolicLink(projectDir) else {
            throw GitStorageError.securityViolation("Project directory cannot be a symbolic link.")
        }
        guard let enumerator = fm.enumerator(
            at: projectDir,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        ) else {
            return
        }
        let resolvedProject = projectDir.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = resolvedProject.hasSuffix("/") ? resolvedProject : resolvedProject + "/"

        while let item = enumerator.nextObject() as? URL {
            if isSymbolicLink(item) {
                throw GitStorageError.securityViolation("Symbolic links are not permitted inside repository projects ('\(item.lastPathComponent)').")
            }
            let vals = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if vals?.isRegularFile == true {
                let resolved = item.standardizedFileURL.resolvingSymlinksInPath().path
                guard resolved.hasPrefix(prefix) else {
                    throw GitStorageError.securityViolation("File '\(item.lastPathComponent)' escapes project directory.")
                }
                let size = Int64(vals?.fileSize ?? 0)
                if size > GitHubWorkspaceValidator.maxGitHubTrackedFileBytes {
                    let mb = Double(size) / (1024 * 1024)
                    throw GitStorageError.fileSizeExceedsGitHubLimit(
                        String(format: "File '%@' is %.1f MB, exceeding LaTeXaP's 50 MB GitHub safety limit.", item.lastPathComponent, mb)
                    )
                }
            }
        }
    }

    private func isValidProjectDescriptor(_ proj: AcademicProjectDescriptor, in repoURL: URL) -> Bool {
        guard GitHubWorkspaceValidator.isValidProjectSlug(proj.slug),
              proj.relativePath == "projects/\(proj.slug)",
              let mainRel = GitHubWorkspaceValidator.validatedProjectRelativeFile(proj.mainTexFile, allowedExtensions: ["tex"]),
              let bibRel = GitHubWorkspaceValidator.validatedProjectRelativeFile(proj.bibFile, allowedExtensions: ["bib"]) else {
            return false
        }
        let projectsRoot = repoURL.appendingPathComponent("projects", isDirectory: true).standardizedFileURL
        guard !isSymbolicLink(projectsRoot) else { return false }
        let projectDir = projectsRoot.appendingPathComponent(proj.slug, isDirectory: true).standardizedFileURL
        guard !isSymbolicLink(projectDir) else { return false }
        if FileManager.default.fileExists(atPath: projectDir.path) {
            guard (try? assertContained(projectDir, inside: repoURL)) != nil else { return false }
            guard !hasSymlinkAlongPath(relativePath: mainRel, inside: projectDir),
                  !hasSymlinkAlongPath(relativePath: bibRel, inside: projectDir) else {
                return false
            }
            let mainURL = projectDir.appendingPathComponent(mainRel).standardizedFileURL
            let bibURL = projectDir.appendingPathComponent(bibRel).standardizedFileURL
            guard (try? assertContained(mainURL, inside: projectDir)) != nil,
                  (try? assertContained(bibURL, inside: projectDir)) != nil else {
                return false
            }
        }
        return true
    }

    private func hasSymlinkAlongPath(relativePath: String, inside baseDir: URL) -> Bool {
        var cursor = baseDir.standardizedFileURL
        for component in relativePath.split(separator: "/").map(String.init) {
            cursor = cursor.appendingPathComponent(component).standardizedFileURL
            if isSymbolicLink(cursor) {
                return true
            }
        }
        return false
    }

    private func assertContained(_ candidate: URL, inside root: URL) throws {
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath().path
        let resolvedCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        guard resolvedCandidate == resolvedRoot || resolvedCandidate.hasPrefix(prefix) else {
            throw GitStorageError.securityViolation("Path '\(candidate.lastPathComponent)' escapes workspace boundary.")
        }
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        let std = url.standardizedFileURL
        if let vals = try? std.resourceValues(forKeys: [.isSymbolicLinkKey]), vals.isSymbolicLink == true {
            return true
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: std.path),
           (attrs[.type] as? FileAttributeType) == .typeSymbolicLink {
            return true
        }
        return false
    }

    private func sanitizedFolderName(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "..", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "repo-\(UUID().uuidString.prefix(8))" : cleaned
    }

    private func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func isOfflineNetworkError(_ stderr: String) -> Bool {
        let lower = stderr.lowercased()
        return lower.contains("could not resolve host") ||
               lower.contains("failed to connect") ||
               lower.contains("unable to access") ||
               lower.contains("operation timed out") ||
               lower.contains("network is unreachable") ||
               lower.contains("connection refused") ||
               lower.contains("no route to host")
    }

    private func isAuthenticationError(_ stderr: String) -> Bool {
        let lower = stderr.lowercased()
        return lower.contains("authentication failed") ||
               lower.contains("could not read username") ||
               lower.contains("permission denied (publickey)") ||
               lower.contains("repository not found") ||
               lower.contains("http basic: access denied") ||
               lower.contains("the requested url returned error: 403") ||
               lower.contains("the requested url returned error: 401")
    }
}
