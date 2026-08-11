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

    func activate(serverURL: String) {
        let normalizedURL = Self.normalizedServerURL(serverURL)
        guard activeServerURL != normalizedURL else { return }

        activeServerURL = normalizedURL
        songs = []
        hasLoaded = false
        errorMessage = nil
        updatingSongIDs = []
    }

    func deactivate() {
        activeServerURL = ""
        songs = []
        isLoading = false
        hasLoaded = false
        errorMessage = nil
        updatingSongIDs = []
    }

    func refresh(using client: SubsonicClient) async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedSongs = try await client.starredSongs()
            try Task.checkCancellation()
            songs = loadedSongs.map { song in
                var song = song
                song.isStarred = true
                return song
            }
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
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
        guard updatingSongIDs.insert(song.id).inserted else {
            return nil
        }
        defer { updatingSongIDs.remove(song.id) }

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
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let candidate = trimmed.contains("://")
            ? trimmed
            : "http://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              let host = components.host?.lowercased() else {
            return trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .lowercased()
        }

        components.scheme = components.scheme?.lowercased()
        components.host = host
        components.query = nil
        components.fragment = nil
        if components.path == "/" {
            components.path = ""
        } else {
            components.path = components.path.trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
            if !components.path.isEmpty {
                components.path = "/\(components.path)"
            }
        }
        return components.string ?? candidate.lowercased()
    }
}
