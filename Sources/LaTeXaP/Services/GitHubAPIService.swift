import Foundation

public enum GitHubAPIService {
    public static let maxResponseBytes: Int = 2 * 1024 * 1024

    private final class GitHubRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            if let url = request.url,
               url.scheme?.lowercased() == "https",
               let host = url.host?.lowercased(),
               host == "api.github.com" || host == "github.com" {
                completionHandler(request)
            } else {
                completionHandler(nil)
            }
        }
    }

    public static func fetchAuthenticatedUser(token: String) async throws -> GitHubAuthenticatedUser {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else {
            throw GitStorageError.authenticationFailed("Enter a GitHub Personal Access Token or sign in via gh CLI.")
        }

        guard let url = URL(string: "https://api.github.com/user") else {
            throw GitStorageError.invalidRemoteURL("Invalid GitHub API endpoint.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyStandardHeaders(to: &request, token: cleanToken)

        let (data, http) = try await performBoundedRequest(request, token: cleanToken)
        guard (200...299).contains(http.statusCode) else {
            throw mapHTTPError(statusCode: http.statusCode, data: data, token: cleanToken)
        }

        return try parseAuthenticatedUserJSON(data)
    }

    public static func listUserRepositories(
        token: String,
        perPage: Int = 50
    ) async throws -> [GitHubRemoteRepository] {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else {
            throw GitStorageError.authenticationFailed("Missing GitHub token.")
        }

        let clampedPerPage = min(max(perPage, 1), 100)
        var components = URLComponents(string: "https://api.github.com/user/repos")!
        components.queryItems = [
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "affiliation", value: "owner,collaborator"),
            URLQueryItem(name: "per_page", value: String(clampedPerPage))
        ]
        guard let url = components.url else {
            throw GitStorageError.invalidRemoteURL("Invalid GitHub repositories endpoint.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyStandardHeaders(to: &request, token: cleanToken)

        let (data, http) = try await performBoundedRequest(request, token: cleanToken)
        guard (200...299).contains(http.statusCode) else {
            throw mapHTTPError(statusCode: http.statusCode, data: data, token: cleanToken)
        }

        return try parseRepositoriesJSON(data)
    }

    public static func createRepository(
        name: String,
        description: String = "",
        isPrivate: Bool = true,
        autoInit: Bool = true,
        token: String
    ) async throws -> GitHubRemoteRepository {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else {
            throw GitStorageError.authenticationFailed("Missing GitHub token.")
        }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GitHubWorkspaceValidator.isValidGitHubRepoName(cleanName) else {
            throw GitStorageError.invalidRemoteURL("Repository name '\(cleanName)' contains invalid characters.")
        }
        guard let url = URL(string: "https://api.github.com/user/repos") else {
            throw GitStorageError.invalidRemoteURL("Invalid GitHub create-repo endpoint.")
        }

        let payload: [String: Any] = [
            "name": cleanName,
            "description": description.trimmingCharacters(in: .whitespacesAndNewlines),
            "private": isPrivate,
            "auto_init": autoInit
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        applyStandardHeaders(to: &request, token: cleanToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, http) = try await performBoundedRequest(request, token: cleanToken)
        guard (200...299).contains(http.statusCode) else {
            throw mapHTTPError(statusCode: http.statusCode, data: data, token: cleanToken)
        }

        return try parseRepositoryObjectJSON(data)
    }

    // MARK: - JSON Parsing (Exposed for Unit Testing)

    public static func parseAuthenticatedUserJSON(_ data: Data) throws -> GitHubAuthenticatedUser {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = obj["login"] as? String,
              !login.isEmpty else {
            throw GitStorageError.commandFailed("Unexpected response from GitHub /user API.")
        }
        let name = obj["name"] as? String
        return GitHubAuthenticatedUser(login: login, name: name)
    }

    public static func parseRepositoriesJSON(_ data: Data) throws -> [GitHubRemoteRepository] {
        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw GitStorageError.commandFailed("Unexpected response from GitHub /user/repos API.")
        }
        return items.compactMap(decodeRepositoryDict(_:))
    }

    public static func parseRepositoryObjectJSON(_ data: Data) throws -> GitHubRemoteRepository {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let repo = decodeRepositoryDict(dict) else {
            throw GitStorageError.commandFailed("Unexpected repository object from GitHub API.")
        }
        return repo
    }

    private static func decodeRepositoryDict(_ dict: [String: Any]) -> GitHubRemoteRepository? {
        guard let id = dict["id"] as? Int,
              let name = dict["name"] as? String,
              let fullName = dict["full_name"] as? String,
              let cloneURL = dict["clone_url"] as? String else {
            return nil
        }
        let ownerObj = dict["owner"] as? [String: Any]
        let owner = (ownerObj?["login"] as? String) ?? fullName.split(separator: "/").first.map(String.init) ?? ""
        let sshURL = (dict["ssh_url"] as? String) ?? "git@github.com:\(owner)/\(name).git"
        let defaultBranch = (dict["default_branch"] as? String) ?? "main"
        let isPrivate = (dict["private"] as? Bool) ?? false

        var updatedAt: Date?
        if let updatedStr = dict["updated_at"] as? String {
            updatedAt = ISO8601DateFormatter().date(from: updatedStr)
        }

        return GitHubRemoteRepository(
            id: id,
            owner: owner,
            name: name,
            fullName: fullName,
            cloneURL: cloneURL,
            sshURL: sshURL,
            defaultBranch: defaultBranch,
            isPrivate: isPrivate,
            updatedAt: updatedAt
        )
    }

    // MARK: - HTTP Execution Helpers

    private static func applyStandardHeaders(to request: inout URLRequest, token: String) {
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("LaTeXaP/0.3.0", forHTTPHeaderField: "User-Agent")
    }

    private static func performBoundedRequest(
        _ request: URLRequest,
        token: String
    ) async throws -> (Data, HTTPURLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let delegate = GitHubRedirectDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitStorageError.commandFailed("Invalid HTTP response from GitHub.")
        }
        if http.expectedContentLength > Int64(maxResponseBytes) {
            throw GitStorageError.commandFailed("GitHub API response exceeded the 2 MB limit.")
        }

        var data = Data()
        if http.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(http.expectedContentLength), 256 * 1024))
        }
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxResponseBytes {
                throw GitStorageError.commandFailed("GitHub API response exceeded the 2 MB limit.")
            }
        }
        return (data, http)
    }

    private static func mapHTTPError(statusCode: Int, data: Data, token: String) -> GitStorageError {
        let rawMsg: String
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = json["message"] as? String, !msg.isEmpty {
            rawMsg = msg
        } else {
            rawMsg = "GitHub API returned HTTP \(statusCode)."
        }
        let cleanMsg = GitHubWorkspaceValidator.redactSensitiveToken(rawMsg, token: token)
        if statusCode == 401 || statusCode == 403 {
            return .authenticationFailed("GitHub authentication failed (HTTP \(statusCode)): \(cleanMsg)")
        }
        return .commandFailed(cleanMsg)
    }
}
