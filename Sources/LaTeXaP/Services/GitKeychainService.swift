import Foundation
import Security

public protocol GitCredentialStore: Sendable {
    func saveToken(_ token: String, forAccount account: String) throws
    func loadToken(forAccount account: String) -> String?
    func deleteToken(forAccount account: String) throws
    func detectGitHubCLIToken() -> String?
}

public final class InMemoryGitCredentialStore: GitCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]
    private let cliToken: String?

    public init(initialTokens: [String: String] = [:], cliToken: String? = nil) {
        self.storage = initialTokens
        self.cliToken = cliToken
    }

    public func saveToken(_ token: String, forAccount account: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitStorageError.authenticationFailed("Personal Access Token cannot be empty.")
        }
        lock.lock()
        storage[account] = trimmed
        lock.unlock()
    }

    public func loadToken(forAccount account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[account]
    }

    public func deleteToken(forAccount account: String) throws {
        lock.lock()
        storage.removeValue(forKey: account)
        lock.unlock()
    }

    public func detectGitHubCLIToken() -> String? {
        cliToken
    }
}

public final class GitKeychainService: GitCredentialStore, @unchecked Sendable {
    public static let shared = GitKeychainService()
    public static let serviceIdentifier = "com.latexap.studio.github"

    public init() {}

    public func saveToken(_ token: String, forAccount account: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitStorageError.authenticationFailed("Personal Access Token cannot be empty.")
        }
        guard let tokenData = trimmed.data(using: .utf8) else {
            throw GitStorageError.authenticationFailed("Unable to encode token as UTF-8.")
        }

        let cleanAccount = normalizedAccount(account)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceIdentifier,
            kSecAttrAccount as String: cleanAccount
        ]

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: tokenData
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = tokenData
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw GitStorageError.authenticationFailed("Could not save token to macOS Keychain (status \(addStatus)).")
            }
            return
        }

        throw GitStorageError.authenticationFailed("Could not update macOS Keychain token (status \(updateStatus)).")
    }

    public func loadToken(forAccount account: String) -> String? {
        let cleanAccount = normalizedAccount(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceIdentifier,
            kSecAttrAccount as String: cleanAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    public func deleteToken(forAccount account: String) throws {
        let cleanAccount = normalizedAccount(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceIdentifier,
            kSecAttrAccount as String: cleanAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitStorageError.authenticationFailed("Could not remove macOS Keychain token (status \(status)).")
        }
    }

    public func detectGitHubCLIToken() -> String? {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh"
        ]
        guard let ghPath = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = ["auth", "token"]
        var env = ProcessInfo.processInfo.environment
        env["GH_PROMPT_DISABLED"] = "1"
        env["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private func normalizedAccount(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "github.com" : trimmed
    }
}
