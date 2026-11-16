import Foundation

public struct AppReleaseUpdate: Equatable, Sendable {
    public let latestVersion: String
    public let tagName: String
    public let htmlURL: URL

    public init(latestVersion: String, tagName: String, htmlURL: URL) {
        self.latestVersion = latestVersion
        self.tagName = tagName
        self.htmlURL = htmlURL
    }
}

public enum UpdateCheckStatus: Equatable, Sendable {
    case updateAvailable(AppReleaseUpdate)
    case upToDate(currentVersion: String, latestTag: String?)
    case failed(String)
}

public enum UpdateCheckerService {
    private static let latestReleaseEndpoint = URL(string: "https://api.github.com/repos/jameslloyd/LaTeXaP/releases/latest")!
    public static let releasesPageURL = URL(string: "https://github.com/jameslloyd/LaTeXaP/releases")!

    /// Silently checks GitHub Releases for a newer semantic version.
    /// Never throws or interrupts the user; returns `nil` on network failure or when already up to date.
    public static func checkForUpdate(currentVersion: String) async -> AppReleaseUpdate? {
        if case .updateAvailable(let update) = await checkForUpdateInteractive(currentVersion: currentVersion) {
            return update
        }
        return nil
    }

    /// Checks GitHub Releases interactively and reports whether an update is available, up to date, or failed.
    public static func checkForUpdateInteractive(currentVersion: String) async -> UpdateCheckStatus {
        var request = URLRequest(url: latestReleaseEndpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("LaTeXaP/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed("Invalid response received from GitHub.")
            }
            guard http.statusCode == 200 else {
                return .failed("GitHub API returned HTTP \(http.statusCode).")
            }
            return evaluateReleaseJSON(data: data, currentVersion: currentVersion)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    public static func evaluateReleaseJSON(data: Data, currentVersion: String) -> UpdateCheckStatus {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let htmlURLString = json["html_url"] as? String,
              let htmlURL = URL(string: htmlURLString)
        else {
            return .failed("Could not parse release metadata from GitHub.")
        }

        let isDraft = (json["draft"] as? Bool) ?? false
        if isDraft {
            return .upToDate(currentVersion: normalizeVersion(currentVersion), latestTag: nil)
        }

        let cleanRemote = normalizeVersion(tagName)
        let cleanCurrent = normalizeVersion(currentVersion)

        if isVersion(cleanRemote, newerThan: cleanCurrent) {
            return .updateAvailable(
                AppReleaseUpdate(
                    latestVersion: cleanRemote,
                    tagName: tagName,
                    htmlURL: htmlURL
                )
            )
        }

        return .upToDate(currentVersion: cleanCurrent, latestTag: tagName)
    }

    public static func parseReleaseJSON(data: Data, currentVersion: String) -> AppReleaseUpdate? {
        if case .updateAvailable(let update) = evaluateReleaseJSON(data: data, currentVersion: currentVersion) {
            return update
        }
        return nil
    }

    public static func normalizeVersion(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            trimmed.removeFirst()
        }
        return trimmed
    }

    /// Compares two dotted numeric version strings (e.g. "0.1.2" > "0.1.1" or "0.2" > "0.1.1").
    public static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candParts = normalizeVersion(candidate)
            .split(separator: ".")
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        let currParts = normalizeVersion(current)
            .split(separator: ".")
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }

        let maxCount = max(candParts.count, currParts.count)
        for idx in 0..<maxCount {
            let cVal = idx < candParts.count ? candParts[idx] : 0
            let curVal = idx < currParts.count ? currParts[idx] : 0
            if cVal != curVal {
                return cVal > curVal
            }
        }
        return false
    }
}
