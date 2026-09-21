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
    private(set) var isDemoMode = false
    private(set) var isRefreshing = false
    private(set) var libraryErrorMessage: String?

    private(set) var loadedAlbumCount = 0
    private var loadRevision = UUID()
    private var libraryLoadTask: Task<[SubsonicAlbum], Error>?
    private let transport: any SubsonicTransport

    init(transport: any SubsonicTransport = URLSessionSubsonicTransport()) {
        self.transport = transport
    }

    func cancelLibraryLoading() {
        libraryLoadTask?.cancel()
    }

    private func invalidateLoad() {
        libraryLoadTask?.cancel()
        libraryLoadTask = nil
        loadRevision = UUID()
        isRefreshing = false
        loadedAlbumCount = 0
    }

    private func loadAlbums(using client: SubsonicClient, revision: UUID) async throws -> [SubsonicAlbum] {
        let task = Task {
            try Task.checkCancellation()
            guard try await client.ping() else {
                throw SubsonicError.api(code: nil, message: "服务器没有通过 Navidrome 连接验证")
            }
            try Task.checkCancellation()
            return try await client.allAlbums { [weak self] count in
                guard self?.loadRevision == revision else { return }
                self?.loadedAlbumCount = count
            }
        }
        libraryLoadTask = task
        return try await withTaskCancellationHandler {
            do {
                return try await task.value
            } catch {
                if task.isCancelled { throw CancellationError() }
                throw error
            }
        } onCancel: {
            task.cancel()
        }
    }

    var errorMessage: String? {
        guard case let .failed(message) = status else { return nil }
        return message
    }

    var isConnecting: Bool {
        status == .connecting
    }

    var activeLibraryIdentifier: String {
        guard let client else { return "" }
        return LibraryIdentity.account(
            serverURL: client.baseURL.absoluteString, username: client.username
        )
    }

    func enterDemoMode() {
        invalidateLoad()
        let demoClient = SubsonicClient.demo()
        client = demoClient
        albums = demoClient.demoAlbums()
        isDemoMode = true
        libraryErrorMessage = nil
        status = .connected
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

        invalidateLoad()
        let revision = loadRevision
        status = .connecting
        libraryErrorMessage = nil
        client = nil
        albums = []
        isDemoMode = false

        let candidate = SubsonicClient(
            baseURL: url,
            username: cleanUsername,
            password: password,
            transport: transport
        )

        do {
            let loadedAlbums = try await loadAlbums(using: candidate, revision: revision)
            try Task.checkCancellation()

            guard loadRevision == revision else { return false }
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
            guard loadRevision == revision else { return false }
            status = .signedOut
            return false
        } catch {
            guard loadRevision == revision else { return false }
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
        invalidateLoad()
        let revision = loadRevision
        isRefreshing = true
        libraryErrorMessage = nil
        defer {
            if loadRevision == revision { isRefreshing = false }
        }
        do {
            let refreshedAlbums = try await loadAlbums(using: client, revision: revision)
            try Task.checkCancellation()
            guard loadRevision == revision else { return }
            albums = refreshedAlbums
        } catch is CancellationError {
            return
        } catch {
            guard loadRevision == revision else { return }
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
        invalidateLoad()
        client = nil
        albums = []
        isDemoMode = false
        libraryErrorMessage = nil
        status = .signedOut
    }

    func signOut(settings: AppSettings) {
        requireSignIn()
        settings.clearConnection()
    }

    private func fail(_ message: String) {
        invalidateLoad()
        client = nil
        albums = []
        isDemoMode = false
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
