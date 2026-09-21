import CryptoKit
import Foundation

/// A credential-free, account-scoped storage identifier. Legacy URL-only keys
/// remain readable by legacy callers, but are never assigned to a new account.
enum LibraryIdentity {
    static func account(serverURL: String, username: String) -> String {
        let server = normalizedKey(serverURL)
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        // Length prefix prevents ambiguous concatenations; usernames are case-sensitive.
        let source = "\(server.utf8.count):\(server)\(user)"
        let digest = SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "account-v1:\(digest)"
    }

    static func normalizedKey(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("account-v1:") { return trimmed }
        let candidate = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              let host = components.host?.lowercased() else { return trimmed }
        components.scheme = components.scheme?.lowercased()
        components.host = host
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        if (components.scheme == "http" && components.port == 80)
            || (components.scheme == "https" && components.port == 443) {
            components.port = nil
        }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        return components.string ?? candidate
    }
}
