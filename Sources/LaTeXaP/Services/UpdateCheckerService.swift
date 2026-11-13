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

public enum UpdateCheckerService {
    private static let latestReleaseEndpoint = URL(string: "https://api.github.com/repos/jameslloyd/LaTeXaP/releases/latest")!

    /// Silently checks GitHub Releases for a newer semantic version.
    /// Never throws or interrupts the user; returns `nil` on network failure or when already up to date.
    public static func checkForUpdate(currentVersion: String) async -> AppReleaseUpdate? {
        var request = URLRequest(url: latestReleaseEndpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("LaTeXaP/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return parseReleaseJSON(data: data, currentVersion: currentVersion)
        } catch {
            return nil
        }
    }

    public static func parseReleaseJSON(data: Data, currentVersion: String) -> AppReleaseUpdate? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let htmlURLString = json["html_url"] as? String,
              let htmlURL = URL(string: htmlURLString)
        else {
            return nil
        }

        let isDraft = (json["draft"] as? Bool) ?? false
        if isDraft { return nil }

        let cleanRemote = normalizeVersion(tagName)
        let cleanCurrent = normalizeVersion(currentVersion)

        guard isVersion(cleanRemote, newerThan: cleanCurrent) else {
            return nil
        }

        return AppReleaseUpdate(
            latestVersion: cleanRemote,
            tagName: tagName,
            htmlURL: htmlURL
        )
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
