import Foundation
import Observation

struct PlaybackBehaviorSummary: Codable, Hashable, Identifiable {
    let id: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var artworkIdentifier: String?
    var playCount: Int
    var completionCount: Int
    var skipCount: Int
    var lastPlayedAt: Date?
    var lastCompletedAt: Date?
    var lastSkippedAt: Date?

    init(song: NowPlayingSong) {
        id = song.id
        title = song.title
        artist = song.artist
        album = song.album
        duration = song.duration
        artworkIdentifier = song.artworkIdentifier
        playCount = 0
        completionCount = 0
        skipCount = 0
        lastPlayedAt = nil
        lastCompletedAt = nil
        lastSkippedAt = nil
    }

    var lastActivityAt: Date {
        [lastPlayedAt, lastCompletedAt, lastSkippedAt]
            .compactMap { $0 }
            .max() ?? .distantPast
    }

    var hasPositiveSignal: Bool {
        playCount > 0 || completionCount > 0
    }
}

@MainActor
@Observable
final class PlaybackBehaviorStore {
    static let maximumStoredItems = 500

    private struct PersistedBehavior: Codable {
        var entriesByServer: [String: [PlaybackBehaviorSummary]] = [:]
    }

    private let defaults: UserDefaults
    private let storageKey = "playbackBehavior.v1"

    private(set) var activeServerURL = ""
    private(set) var items: [PlaybackBehaviorSummary] = []

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
        items = persistedBehavior().entriesByServer[normalizedURL] ?? []
        sortAndTrim()
    }

    func deactivate() {
        activeServerURL = ""
        items = []
    }

    func record(_ event: PlaybackHistoryEvent, for serverURL: String) {
        activate(serverURL: serverURL)
        guard !activeServerURL.isEmpty else { return }

        let index: Int
        if let existingIndex = items.firstIndex(where: { $0.id == event.song.id }) {
            index = existingIndex
        } else {
            items.append(PlaybackBehaviorSummary(song: event.song))
            index = items.index(before: items.endIndex)
        }

        var summary = items[index]
        summary.title = event.song.title
        summary.artist = event.song.artist
        summary.album = event.song.album
        summary.duration = event.song.duration
        summary.artworkIdentifier = event.song.artworkIdentifier

        switch event.kind {
        case .qualified:
            summary.playCount += 1
            summary.lastPlayedAt = event.playedAt
        case .completed:
            summary.completionCount += 1
            summary.lastCompletedAt = event.playedAt
        case .skipped:
            summary.skipCount += 1
            summary.lastSkippedAt = event.playedAt
        }

        items[index] = summary
        sortAndTrim()
        save()
    }

    func clearCurrentServerBehavior() {
        guard !activeServerURL.isEmpty else { return }
        items = []
        var behavior = persistedBehavior()
        behavior.entriesByServer.removeValue(forKey: activeServerURL)
        save(behavior)
    }

    private func sortAndTrim() {
        items.sort {
            if $0.lastActivityAt != $1.lastActivityAt {
                return $0.lastActivityAt > $1.lastActivityAt
            }
            return $0.id < $1.id
        }
        if items.count > Self.maximumStoredItems {
            items = Array(items.prefix(Self.maximumStoredItems))
        }
    }

    private func persistedBehavior() -> PersistedBehavior {
        guard let data = defaults.data(forKey: storageKey),
              let behavior = try? JSONDecoder().decode(
                  PersistedBehavior.self,
                  from: data
              ) else {
            return PersistedBehavior()
        }
        return behavior
    }

    private func save() {
        guard !activeServerURL.isEmpty else { return }
        var behavior = persistedBehavior()
        behavior.entriesByServer[activeServerURL] = items
        save(behavior)
    }

    private func save(_ behavior: PersistedBehavior) {
        guard let data = try? JSONEncoder().encode(behavior) else { return }
        defaults.set(data, forKey: storageKey)
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
