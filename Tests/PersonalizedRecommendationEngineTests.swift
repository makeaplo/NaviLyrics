import XCTest
@testable import NaviLyrics

final class PersonalizedRecommendationEngineTests: XCTestCase {
    @MainActor
    func testPrefersUnplayedSongFromFavoriteArtist() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let favorite = makeSong(
            id: "favorite",
            title: "已收藏",
            artist: "喜欢的艺术家",
            album: "旧专辑"
        )
        let sameArtist = makeSong(
            id: "same-artist",
            title: "还没听过",
            artist: "喜欢的艺术家",
            album: "新专辑"
        )
        let unrelated = makeSong(
            id: "unrelated",
            title: "另一首歌",
            artist: "另一个艺术家",
            album: "另一张专辑"
        )

        var behavior = PlaybackBehaviorSummary(
            song: makeNowPlayingSong(from: favorite)
        )
        behavior.playCount = 3
        behavior.lastPlayedAt = now.addingTimeInterval(-30 * 86_400)

        let recommendations = PersonalizedRecommendationEngine.recommend(
            songs: [favorite, sameArtist, unrelated],
            behavior: [behavior],
            favorites: [favorite],
            now: now,
            limit: 2
        )

        XCTAssertEqual(recommendations.first?.song.id, "same-artist")
        XCTAssertEqual(
            recommendations.first?.reason,
            .favoriteArtist("喜欢的艺术家")
        )
    }

    @MainActor
    func testSkipsRecentlyPlayedSongsAndLimitsArtistRepetition() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent = makeSong(
            id: "recent",
            title: "刚刚听过",
            artist: "常听艺术家",
            album: "专辑"
        )
        let first = makeSong(
            id: "first",
            title: "推荐一",
            artist: "常听艺术家",
            album: "专辑"
        )
        let second = makeSong(
            id: "second",
            title: "推荐二",
            artist: "常听艺术家",
            album: "专辑"
        )
        let third = makeSong(
            id: "third",
            title: "推荐三",
            artist: "常听艺术家",
            album: "专辑"
        )
        let other = makeSong(
            id: "other",
            title: "换个口味",
            artist: "另一个艺术家",
            album: "另一张专辑"
        )

        var recentBehavior = PlaybackBehaviorSummary(
            song: makeNowPlayingSong(from: recent)
        )
        recentBehavior.playCount = 2
        recentBehavior.lastPlayedAt = now.addingTimeInterval(-86_400)
        var artistBehavior = PlaybackBehaviorSummary(
            song: makeNowPlayingSong(from: first)
        )
        artistBehavior.playCount = 4
        artistBehavior.lastPlayedAt = now.addingTimeInterval(-20 * 86_400)

        let recommendations = PersonalizedRecommendationEngine.recommend(
            songs: [recent, first, second, third, other],
            behavior: [recentBehavior, artistBehavior],
            favorites: [],
            now: now,
            limit: 3
        )

        XCTAssertFalse(recommendations.contains { $0.song.id == "recent" })
        XCTAssertTrue(recommendations.contains { $0.song.id == "other" })
        XCTAssertLessThanOrEqual(
            recommendations.filter { $0.song.artist == "常听艺术家" }.count,
            2
        )
    }

    @MainActor
    func testRecommendationCachePersistsByServerAndSignatures() throws {
        let suiteName = "NaviLyricsCoreTests.recommendations.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let serverURL = "https://music.example:4533/"
        let song = makeSong(
            id: "cached",
            title: "缓存推荐",
            artist: "喜欢的艺术家",
            album: "专辑"
        )
        let recommendation = PersonalizedRecommendation(
            song: song,
            reason: .favoriteArtist("喜欢的艺术家"),
            score: 42
        )

        let cache = PersonalizedRecommendationCache(defaults: defaults)
        cache.activate(serverURL: serverURL)
        cache.save(
            [recommendation],
            librarySignature: "library-v1",
            signalSignature: "signals-v1"
        )

        let restored = PersonalizedRecommendationCache(defaults: defaults)
        restored.activate(serverURL: serverURL)

        XCTAssertEqual(
            restored.cachedRecommendations(
                librarySignature: "library-v1",
                signalSignature: "signals-v1"
            ),
            [recommendation]
        )
        XCTAssertNil(
            restored.cachedRecommendations(
                librarySignature: "library-v1",
                signalSignature: "signals-v2"
            )
        )
    }

    @MainActor
    private func makeSong(
        id: String,
        title: String,
        artist: String,
        album: String
    ) -> SubsonicSong {
        SubsonicSong(
            id: id,
            title: title,
            artist: artist,
            album: album,
            duration: 180,
            suffix: "flac",
            bitRate: 960,
            coverArt: "cover-\(id)",
            isStarred: false
        )
    }

    @MainActor
    private func makeNowPlayingSong(
        from song: SubsonicSong
    ) -> NowPlayingSong {
        NowPlayingSong(
            id: song.id,
            title: song.title,
            artist: song.artist,
            album: song.album,
            duration: song.duration,
            streamURL: URL(fileURLWithPath: "/test/stream/\(song.id)"),
            artworkURL: nil,
            artworkIdentifier: song.coverArt
        )
    }
}
