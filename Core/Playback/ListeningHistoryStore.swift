import Foundation
import Observation

struct ListeningHistoryItem: Codable, Hashable, Identifiable {
    let id: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var artworkIdentifier: String?
    var lastPlayedAt: Date
    var playCount: Int

    init(
        id: String,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        artworkIdentifier: String?,
        lastPlayedAt: Date,
        playCount: Int = 1
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration.isFinite ? max(duration, 0) : 0
        self.artworkIdentifier = artworkIdentifier
        self.lastPlayedAt = lastPlayedAt
        self.playCount = max(playCount, 1)
    }
}

enum PlaybackEventKind: String, Codable, Hashable, Sendable {
    case qualified
    case completed
    case skipped
}

struct PlaybackHistoryEvent: Identifiable {
    let id = UUID()
    let song: NowPlayingSong
    let playedAt: Date
    let kind: PlaybackEventKind

    init(
        song: NowPlayingSong,
        playedAt: Date,
        kind: PlaybackEventKind = .qualified
    ) {
        self.song = song
        self.playedAt = playedAt
        self.kind = kind
    }
}

@MainActor
@Observable
final class ListeningHistoryStore {
    static let maximumStoredItems = 100

    private struct PersistedHistory: Codable {
        var entriesByServer: [String: [ListeningHistoryItem]] = [:]
    }

    private let defaults: UserDefaults
    private let storageKey = "listeningHistory.v1"

    private(set) var activeServerURL = ""
    private(set) var items: [ListeningHistoryItem] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func activate(serverURL: String) {
        let normalizedURL = Self.normalizedServerURL(serverURL)
        guard activeServerURL != normalizedURL else { return }

        activeServerURL = normalizedURL
        guard !normalizedURL.isEmpty else {
            items = []
            return
        }
        items = persistedHistory().entriesByServer[normalizedURL] ?? []
    }

    func deactivate() {
        activeServerURL = ""
        items = []
    }

    func record(_ event: PlaybackHistoryEvent, for serverURL: String) {
        activate(serverURL: serverURL)
        guard !activeServerURL.isEmpty,
              event.kind == .qualified else {
            return
        }

        let song = event.song
        if let index = items.firstIndex(where: { $0.id == song.id }) {
            var item = items[index]
            item.title = song.title
            item.artist = song.artist
            item.album = song.album
            item.duration = song.duration
            item.artworkIdentifier = song.artworkIdentifier
            item.lastPlayedAt = event.playedAt
            item.playCount += 1
            items[index] = item
        } else {
            items.append(
                ListeningHistoryItem(
                    id: song.id,
                    title: song.title,
                    artist: song.artist,
                    album: song.album,
                    duration: song.duration,
                    artworkIdentifier: song.artworkIdentifier,
                    lastPlayedAt: event.playedAt
                )
            )
        }

        items.sort { $0.lastPlayedAt > $1.lastPlayedAt }
        if items.count > Self.maximumStoredItems {
            items = Array(items.prefix(Self.maximumStoredItems))
        }
        save()
    }

    func recentItems(limit: Int = 6) -> [ListeningHistoryItem] {
        Array(
            items
                .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
                .prefix(max(limit, 0))
        )
    }

    func mostPlayedItems(limit: Int = 6) -> [ListeningHistoryItem] {
        Array(
            items
                .sorted {
                    if $0.playCount != $1.playCount {
                        return $0.playCount > $1.playCount
                    }
                    return $0.lastPlayedAt > $1.lastPlayedAt
                }
                .prefix(max(limit, 0))
        )
    }

    func clearCurrentServerHistory() {
        guard !activeServerURL.isEmpty else { return }
        items = []
        var history = persistedHistory()
        history.entriesByServer.removeValue(forKey: activeServerURL)
        save(history)
    }

    private func persistedHistory() -> PersistedHistory {
        guard let data = defaults.data(forKey: storageKey),
              let history = try? JSONDecoder().decode(
                PersistedHistory.self,
                from: data
              ) else {
            return PersistedHistory()
        }
        return history
    }

    private func save() {
        guard !activeServerURL.isEmpty else { return }
        var history = persistedHistory()
        history.entriesByServer[activeServerURL] = items
        save(history)
    }

    private func save(_ history: PersistedHistory) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func normalizedServerURL(_ value: String) -> String {
        LibraryIdentity.normalizedKey(value)
    }
}
