import Foundation
import Observation

@MainActor
@Observable
final class NavidromeSession {
    enum Status: Equatable {
        case checking
        case signedOut
        case connecting
        case connected
        case failed(String)
    }

    private(set) var status: Status = .checking
    private(set) var client: SubsonicClient?
    private(set) var albums: [SubsonicAlbum] = []
    private(set) var isRefreshing = false
    private(set) var libraryErrorMessage: String?

    var errorMessage: String? {
        guard case let .failed(message) = status else { return nil }
        return message
    }

    var isConnecting: Bool {
        status == .connecting
    }

    func restore(using settings: AppSettings) async {
        guard settings.hasSavedConnection else {
            status = .signedOut
            return
        }
        _ = await signIn(
            serverURL: settings.serverURL,
            username: settings.username,
            password: settings.password,
            settings: settings,
            savesCredentials: false
        )
    }

    @discardableResult
    func signIn(
        serverURL: String,
        username: String,
        password: String,
        settings: AppSettings,
        savesCredentials: Bool = true
    ) async -> Bool {
        let cleanServerURL = serverURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let cleanUsername = username.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !cleanServerURL.isEmpty,
              !cleanUsername.isEmpty,
              !password.isEmpty else {
            fail("请完整填写服务器地址、用户名和密码")
            return false
        }
        guard let url = Self.normalizedURL(from: cleanServerURL) else {
            fail("服务器地址格式不正确")
            return false
        }

        status = .connecting
        libraryErrorMessage = nil
        client = nil
        albums = []

        let candidate = SubsonicClient(
            baseURL: url,
            username: cleanUsername,
            password: password
        )

        do {
            guard try await candidate.ping() else {
                fail("服务器没有通过 Navidrome 连接验证")
                return false
            }
            let loadedAlbums = try await candidate.albumList(
                type: "newest",
                size: 300
            )
            try Task.checkCancellation()

            client = candidate
            albums = loadedAlbums
            if savesCredentials {
                settings.updateConnection(
                    serverURL: url.absoluteString,
                    username: cleanUsername,
                    password: password
                )
            }
            status = .connected
            return true
        } catch is CancellationError {
            status = .signedOut
            return false
        } catch {
            fail("连接失败：\(error.localizedDescription)")
            return false
        }
    }

    func refreshLibrary() async {
        guard !isRefreshing else { return }
        guard let client else {
            status = .signedOut
            return
        }
        isRefreshing = true
        libraryErrorMessage = nil
        defer { isRefreshing = false }
        do {
            _ = try await client.ping()
            let refreshedAlbums = try await client.albumList(
                type: "newest",
                size: 300
            )
            try Task.checkCancellation()
            albums = refreshedAlbums
        } catch is CancellationError {
            return
        } catch {
            // A transient Wi-Fi or NAS interruption must not discard the
            // loaded library, stop playback, or force the user to sign in.
            libraryErrorMessage =
                "刷新失败：\(error.localizedDescription)"
        }
    }

    func dismissLibraryError() {
        libraryErrorMessage = nil
    }

    func requireSignIn() {
        client = nil
        albums = []
        libraryErrorMessage = nil
        status = .signedOut
    }

    func signOut(settings: AppSettings) {
        requireSignIn()
        settings.clearConnection()
    }

    private func fail(_ message: String) {
        client = nil
        albums = []
        libraryErrorMessage = nil
        status = .failed(message)
    }

    private static func normalizedURL(from value: String) -> URL? {
        let candidate = value.contains("://") ? value : "http://\(value)"
        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil else {
            return nil
        }
        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
