import Foundation
import Observation

@MainActor
@Observable
final class FavoritesStore {
    private(set) var activeServerURL = ""
    private(set) var songs: [SubsonicSong] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var updatingSongIDs: Set<String> = []

    private var revision = UUID()

    func activate(serverURL: String) {
        let normalizedURL = Self.normalizedServerURL(serverURL)
        guard activeServerURL != normalizedURL else { return }

        revision = UUID()
        isLoading = false
        activeServerURL = normalizedURL
        songs = []
        hasLoaded = false
        errorMessage = nil
        updatingSongIDs = []
    }

    func deactivate() {
        revision = UUID()
        activeServerURL = ""
        songs = []
        isLoading = false
        hasLoaded = false
        errorMessage = nil
        updatingSongIDs = []
    }

    func refresh(using client: SubsonicClient) async {
        guard !isLoading, activeServerURL == LibraryIdentity.account(
            serverURL: client.baseURL.absoluteString, username: client.username
        ) else { return }
        let requestRevision = revision

        isLoading = true
        errorMessage = nil
        defer { if revision == requestRevision { isLoading = false } }

        do {
            let loadedSongs = try await client.starredSongs()
            try Task.checkCancellation()
            guard revision == requestRevision else { return }
            songs = loadedSongs.map { song in
                var song = song
                song.isStarred = true
                return song
            }
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            guard revision == requestRevision else { return }
            errorMessage = "收藏加载失败：\(error.localizedDescription)"
        }
    }

    func isFavorite(songID: String, fallback: Bool = false) -> Bool {
        if hasLoaded {
            return songs.contains { $0.id == songID }
        }
        return fallback
    }

    func isUpdating(songID: String) -> Bool {
        updatingSongIDs.contains(songID)
    }

    @discardableResult
    func toggle(
        song: SubsonicSong,
        using client: SubsonicClient
    ) async -> Bool? {
        guard activeServerURL == LibraryIdentity.account(
            serverURL: client.baseURL.absoluteString, username: client.username
        ), updatingSongIDs.insert(song.id).inserted else {
            return nil
        }
        let requestRevision = revision
        defer {
            if revision == requestRevision { updatingSongIDs.remove(song.id) }
        }

        let currentlyFavorite = isFavorite(
            songID: song.id,
            fallback: song.isStarred
        )
        let shouldFavorite = !currentlyFavorite

        do {
            try await client.setFavorite(
                songID: song.id,
                isFavorite: shouldFavorite
            )
            try Task.checkCancellation()
            guard revision == requestRevision else { return nil }
            var updatedSong = song
            updatedSong.isStarred = shouldFavorite
            if shouldFavorite {
                replaceOrAppend(updatedSong)
            } else {
                songs.removeAll { $0.id == song.id }
            }
            hasLoaded = true
            errorMessage = nil
            return shouldFavorite
        } catch {
            guard revision == requestRevision else { return nil }
            errorMessage = "收藏操作失败：\(error.localizedDescription)"
            return nil
        }
    }

    private func replaceOrAppend(_ song: SubsonicSong) {
        if let index = songs.firstIndex(where: { $0.id == song.id }) {
            songs[index] = song
        } else {
            songs.insert(song, at: 0)
        }
    }

    private static func normalizedServerURL(_ value: String) -> String {
        LibraryIdentity.normalizedKey(value)
    }
}
