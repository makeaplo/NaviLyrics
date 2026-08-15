import Foundation
import Observation

enum RecommendationReason: Hashable {
    case favoriteArtist(String)
    case favoriteAlbum(String)
    case familiarArtist(String)
    case revisitArtist(String)
    case discover

    var title: String {
        switch self {
        case let .favoriteArtist(artist):
            "因为你喜欢 \(artist)"
        case let .favoriteAlbum(album):
            "来自你喜欢的专辑《\(album)》"
        case let .familiarArtist(artist):
            "因为你常听 \(artist)"
        case let .revisitArtist(artist):
            "你有一段时间没听 \(artist)"
        case .discover:
            "为你发现"
        }
    }
}

struct PersonalizedRecommendation: Hashable, Identifiable {
    let song: SubsonicSong
    let reason: RecommendationReason
    let score: Double

    var id: String { song.id }
}

struct PersonalizedRecommendationEngine {
    static func recommend(
        songs: [SubsonicSong],
        behavior: [PlaybackBehaviorSummary],
        favorites: [SubsonicSong],
        excludedSongIDs: Set<String> = [],
        now: Date = Date(),
        limit: Int = 8
    ) -> [PersonalizedRecommendation] {
        guard limit > 0 else { return [] }

        let behaviorByID = Dictionary(
            uniqueKeysWithValues: behavior.map { ($0.id, $0) }
        )
        let artistSignals = makeArtistSignals(from: behavior)
        let albumSignals = makeAlbumSignals(from: behavior)
        let favoriteIDs = Set(favorites.map(\.id))
        let favoriteArtists = Set(
            favorites.map(\.artist).filter { !$0.isEmpty }
        )
        let favoriteAlbums = Set(
            favorites.map(\.album).filter { !$0.isEmpty }
        )

        guard !favoriteIDs.isEmpty
                || behavior.contains(where: \.hasPositiveSignal) else {
            return []
        }

        let uniqueSongs = Dictionary(
            songs.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        ).values

        let scored = uniqueSongs.compactMap { song -> ScoredSong? in
            guard !excludedSongIDs.contains(song.id) else { return nil }
            let summary = behaviorByID[song.id]
            let score = score(
                for: song,
                summary: summary,
                favoriteIDs: favoriteIDs,
                favoriteArtists: favoriteArtists,
                favoriteAlbums: favoriteAlbums,
                artistSignals: artistSignals,
                albumSignals: albumSignals,
                now: now
            )
            guard score > 0 else { return nil }
            return ScoredSong(
                song: song,
                score: score,
                reason: reason(
                    for: song,
                    summary: summary,
                    favoriteArtists: favoriteArtists,
                    favoriteAlbums: favoriteAlbums,
                    artistSignals: artistSignals,
                    now: now
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.song.id < rhs.song.id
        }

        let preferred = scored.filter { item in
            guard let summary = behaviorByID[item.song.id],
                  let lastPlayedAt = summary.lastPlayedAt else {
                return true
            }
            return now.timeIntervalSince(lastPlayedAt) >= 7 * 86_400
        }
        let unseen = preferred.filter { item in
            guard let summary = behaviorByID[item.song.id] else {
                return true
            }
            return !summary.hasPositiveSignal
        }
        let pool = unseen.isEmpty
            ? (preferred.isEmpty ? scored : preferred)
            : unseen

        var selected: [PersonalizedRecommendation] = []
        var artistCounts: [String: Int] = [:]
        for item in pool {
            let artist = item.song.artist
            if !artist.isEmpty, artistCounts[artist, default: 0] >= 2 {
                continue
            }
            selected.append(
                PersonalizedRecommendation(
                    song: item.song,
                    reason: item.reason,
                    score: item.score
                )
            )
            if !artist.isEmpty {
                artistCounts[artist, default: 0] += 1
            }
            if selected.count == limit {
                break
            }
        }

        if selected.count < limit {
            let selectedIDs = Set(selected.map(\.id))
            for item in pool where !selectedIDs.contains(item.song.id) {
                selected.append(
                    PersonalizedRecommendation(
                        song: item.song,
                        reason: item.reason,
                        score: item.score
                    )
                )
                if selected.count == limit {
                    break
                }
            }
        }

        return selected
    }

    private static func score(
        for song: SubsonicSong,
        summary: PlaybackBehaviorSummary?,
        favoriteIDs: Set<String>,
        favoriteArtists: Set<String>,
        favoriteAlbums: Set<String>,
        artistSignals: [String: ArtistSignal],
        albumSignals: [String: AlbumSignal],
        now: Date
    ) -> Double {
        var score = 8.0

        if favoriteIDs.contains(song.id) {
            score += 40
        }
        if favoriteArtists.contains(song.artist) {
            score += 36
        }
        if favoriteAlbums.contains(song.album) {
            score += 28
        }

        if let signal = artistSignals[song.artist] {
            score += min(Double(signal.playCount) * 6, 30)
            score += min(Double(signal.completionCount) * 8, 24)
            score -= min(Double(signal.skipCount) * 6, 18)
            score += revisitBonus(for: signal.lastPlayedAt, now: now)
        }
        if let signal = albumSignals[song.album] {
            score += min(Double(signal.playCount) * 3, 12)
            score += min(Double(signal.completionCount) * 4, 12)
        }

        if let summary {
            score += min(Double(summary.playCount) * 4, 20)
            score += min(Double(summary.completionCount) * 7, 21)
            score -= min(Double(summary.skipCount) * 10, 30)

            if let lastPlayedAt = summary.lastPlayedAt {
                let daysSincePlay = max(
                    now.timeIntervalSince(lastPlayedAt) / 86_400,
                    0
                )
                if daysSincePlay < 7 {
                    score -= 24
                } else {
                    score += min(daysSincePlay, 28)
                }
            } else if summary.hasPositiveSignal {
                score += 10
            }
        } else {
            score += 14
        }

        return score
    }

    private static func reason(
        for song: SubsonicSong,
        summary: PlaybackBehaviorSummary?,
        favoriteArtists: Set<String>,
        favoriteAlbums: Set<String>,
        artistSignals: [String: ArtistSignal],
        now: Date
    ) -> RecommendationReason {
        if favoriteArtists.contains(song.artist) {
            return .favoriteArtist(song.artist)
        }
        if favoriteAlbums.contains(song.album) {
            return .favoriteAlbum(song.album)
        }
        if let signal = artistSignals[song.artist],
           signal.playCount > 0 {
            let daysSincePlay = signal.lastPlayedAt.map {
                now.timeIntervalSince($0) / 86_400
            } ?? 0
            if daysSincePlay >= 21 {
                return .revisitArtist(song.artist)
            }
            return .familiarArtist(song.artist)
        }
        if let summary, let lastPlayedAt = summary.lastPlayedAt {
            let daysSincePlay = now.timeIntervalSince(lastPlayedAt) / 86_400
            if daysSincePlay >= 21 {
                return .revisitArtist(song.artist)
            }
            if summary.hasPositiveSignal {
                return .familiarArtist(song.artist)
            }
        }
        return .discover
    }

    private static func makeArtistSignals(
        from behavior: [PlaybackBehaviorSummary]
    ) -> [String: ArtistSignal] {
        var signals: [String: ArtistSignal] = [:]
        for summary in behavior where !summary.artist.isEmpty {
            signals[summary.artist, default: ArtistSignal()].merge(summary)
        }
        return signals
    }

    private static func makeAlbumSignals(
        from behavior: [PlaybackBehaviorSummary]
    ) -> [String: AlbumSignal] {
        var signals: [String: AlbumSignal] = [:]
        for summary in behavior where !summary.album.isEmpty {
            signals[summary.album, default: AlbumSignal()].merge(summary)
        }
        return signals
    }

    private static func revisitBonus(
        for lastPlayedAt: Date?,
        now: Date
    ) -> Double {
        guard let lastPlayedAt else { return 0 }
        let daysSincePlay = max(
            now.timeIntervalSince(lastPlayedAt) / 86_400,
            0
        )
        return daysSincePlay >= 7 ? min(daysSincePlay, 21) : -12
    }
}

private struct ScoredSong {
    let song: SubsonicSong
    let score: Double
    let reason: RecommendationReason
}

private struct ArtistSignal {
    var playCount = 0
    var completionCount = 0
    var skipCount = 0
    var lastPlayedAt: Date?

    mutating func merge(_ summary: PlaybackBehaviorSummary) {
        playCount += summary.playCount
        completionCount += summary.completionCount
        skipCount += summary.skipCount
        if let date = summary.lastPlayedAt,
           date > (lastPlayedAt ?? .distantPast) {
            lastPlayedAt = date
        }
    }
}

private struct AlbumSignal {
    var playCount = 0
    var completionCount = 0

    mutating func merge(_ summary: PlaybackBehaviorSummary) {
        playCount += summary.playCount
        completionCount += summary.completionCount
    }
}

@MainActor
@Observable
final class PersonalizedRecommendationCache {
    private struct PersistedCache: Codable {
        var snapshotsByServer: [String: PersistedSnapshot] = [:]
    }

    private struct PersistedSnapshot: Codable {
        let librarySignature: String
        let signalSignature: String
        let recommendations: [PersistedRecommendation]
        let updatedAt: Date
    }

    private struct PersistedRecommendation: Codable {
        let song: PersistedSong
        let reason: PersistedReason
        let score: Double

        init(_ recommendation: PersonalizedRecommendation) {
            song = PersistedSong(recommendation.song)
            reason = PersistedReason(recommendation.reason)
            score = recommendation.score
        }

        func makeRecommendation() -> PersonalizedRecommendation? {
            guard let reason = reason.makeReason() else { return nil }
            return PersonalizedRecommendation(
                song: song.makeSong(),
                reason: reason,
                score: score
            )
        }
    }

    private struct PersistedSong: Codable {
        let id: String
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
        let suffix: String?
        let bitRate: Int?
        let coverArt: String?
        let isStarred: Bool

        init(_ song: SubsonicSong) {
            id = song.id
            title = song.title
            artist = song.artist
            album = song.album
            duration = song.duration
            suffix = song.suffix
            bitRate = song.bitRate
            coverArt = song.coverArt
            isStarred = song.isStarred
        }

        func makeSong() -> SubsonicSong {
            SubsonicSong(
                id: id,
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                suffix: suffix,
                bitRate: bitRate,
                coverArt: coverArt,
                isStarred: isStarred
            )
        }
    }

    private struct PersistedReason: Codable {
        enum Kind: String, Codable {
            case favoriteArtist
            case favoriteAlbum
            case familiarArtist
            case revisitArtist
            case discover
        }

        let kind: Kind
        let value: String?

        init(_ reason: RecommendationReason) {
            switch reason {
            case let .favoriteArtist(artist):
                kind = .favoriteArtist
                value = artist
            case let .favoriteAlbum(album):
                kind = .favoriteAlbum
                value = album
            case let .familiarArtist(artist):
                kind = .familiarArtist
                value = artist
            case let .revisitArtist(artist):
                kind = .revisitArtist
                value = artist
            case .discover:
                kind = .discover
                value = nil
            }
        }

        func makeReason() -> RecommendationReason? {
            switch kind {
            case .favoriteArtist:
                guard let value else { return nil }
                return .favoriteArtist(value)
            case .favoriteAlbum:
                guard let value else { return nil }
                return .favoriteAlbum(value)
            case .familiarArtist:
                guard let value else { return nil }
                return .familiarArtist(value)
            case .revisitArtist:
                guard let value else { return nil }
                return .revisitArtist(value)
            case .discover:
                return .discover
            }
        }
    }

    private let defaults: UserDefaults
    private let storageKey = "personalizedRecommendationCache.v1"

    private(set) var activeServerURL = ""

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func activate(serverURL: String) {
        let normalizedURL = Self.normalizedServerURL(serverURL)
        guard activeServerURL != normalizedURL else { return }
        activeServerURL = normalizedURL
    }

    func deactivate() {
        activeServerURL = ""
    }

    func cachedRecommendations(
        librarySignature: String,
        signalSignature: String
    ) -> [PersonalizedRecommendation]? {
        guard !activeServerURL.isEmpty,
              let snapshot = persistedCache()
                .snapshotsByServer[activeServerURL],
              snapshot.librarySignature == librarySignature,
              snapshot.signalSignature == signalSignature else {
            return nil
        }

        return snapshot.recommendations.compactMap {
            $0.makeRecommendation()
        }
    }

    func save(
        _ recommendations: [PersonalizedRecommendation],
        librarySignature: String,
        signalSignature: String
    ) {
        guard !activeServerURL.isEmpty else { return }

        var cache = persistedCache()
        cache.snapshotsByServer[activeServerURL] = PersistedSnapshot(
            librarySignature: librarySignature,
            signalSignature: signalSignature,
            recommendations: recommendations.map(PersistedRecommendation.init),
            updatedAt: Date()
        )
        save(cache)
    }

    private func persistedCache() -> PersistedCache {
        guard let data = defaults.data(forKey: storageKey),
              let cache = try? JSONDecoder().decode(
                PersistedCache.self,
                from: data
              ) else {
            return PersistedCache()
        }
        return cache
    }

    private func save(_ cache: PersistedCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
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
