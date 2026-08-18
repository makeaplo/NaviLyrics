import XCTest
@testable import NaviLyrics

@MainActor
final class NaviLyricsCoreTests: XCTestCase {
    @MainActor
    func testDuplicateTimestampAndTextReceiveUniqueIdentities() {
        let first = LyricLine(time: 12.5, text: "重复副歌")
        let second = LyricLine(time: 12.5, text: "重复副歌")

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(Set([first.id, second.id]).count, 2)
    }

    @MainActor
    func testAnnotationsPreserveOriginalLineIdentity() {
        let line = LyricLine(time: 3, text: "原文")
        let translated = line.attachingTranslation("Translation")
        let romanized = translated.attachingRomanization("romanization")

        XCTAssertEqual(line.id, translated.id)
        XCTAssertEqual(line.id, romanized.id)
    }

    @MainActor
    func testParserKeepsSimultaneousDuplicateLinesSafe() {
        let lyrics = LyricParser.parseLRC(
            "[00:10.00]同一句\n[00:10.00]同一句"
        )

        XCTAssertEqual(lyrics.count, 2)
        XCTAssertEqual(Set(lyrics.map(\.id)).count, 2)
    }

    @MainActor
    func testParserRejectsNonFiniteTimestamp() {
        let oversizedNumber = String(repeating: "9", count: 400)
        let lyrics = LyricParser.parseLRC(
            "[\(oversizedNumber):00.00]异常时间"
        )

        XCTAssertTrue(lyrics.isEmpty)
    }

    @MainActor
    func testPlaybackTimelineSelectsLastSimultaneousLine() {
        let first = LyricLine(time: 5, text: "合唱一")
        let second = LyricLine(time: 5, text: "合唱二")
        let third = LyricLine(time: 8, text: "下一句")
        let lyrics = [first, second, third]

        let position = LyricPlaybackTimeline.position(
            at: 5,
            in: lyrics
        )

        XCTAssertEqual(position.highlightedLyricID, second.id)
        XCTAssertEqual(position.nextTransitionTime, 8)
    }

    @MainActor
    func testAuthenticatedArtworkURLIsStableWithinSession() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://music.example.com"))
        let client = SubsonicClient(
            baseURL: baseURL,
            username: "listener",
            password: "secret"
        )

        let first = client.coverURL(coverArt: "cover-1", size: 600)
        let second = client.coverURL(coverArt: "cover-1", size: 600)

        XCTAssertEqual(first, second)
        XCTAssertFalse(first?.absoluteString.contains("secret") ?? true)
    }

    @MainActorx
    func testDemoClientProvidesLocalLibraryAndLyrics() async throws {
        let client = SubsonicClient.demo()

        XCTAssertTrue(client.isDemoMode)
        let albums = try await client.albumList()
        XCTAssertEqual(albums.count, 2)

        let songs = try await client.songs(inAlbum: albums[0].id)
        XCTAssertFalse(songs.isEmpty)
        XCTAssertEqual(
            client.streamURL(songID: songs[0].id).scheme,
            "navi-demo"
        )
        XCTAssertEqual(
            client.coverURL(coverArt: songs[0].coverArt)?.scheme,
            "navi-demo"
        )

        let result = try await client.lyrics(
            songID: songs[0].id,
            artist: songs[0].artist,
            title: songs[0].title
        )
        guard case let .structured(tracks) = result else {
            XCTFail("演示歌曲应提供结构化歌词")
            return
        }
        XCTAssertGreaterThanOrEqual(tracks.count, 2)
        XCTAssertFalse(tracks[0].line?.isEmpty ?? true)
    }

    @MainActor
    func testInvalidDurationCannotEnterPlaybackState() throws {
        let streamURL = try XCTUnwrap(
            URL(string: "https://music.example.com/stream")
        )
        let song = NowPlayingSong(
            id: "song-1",
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: .infinity,
            streamURL: streamURL,
            artworkURL: nil
        )

        XCTAssertEqual(song.duration, 0)
    }

    @MainActor
    func testListeningHistoryTracksRecentAndMostPlayedSongs() throws {
        let suiteName = "NaviLyricsCoreTests.history.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ListeningHistoryStore(defaults: defaults)
        let firstSong = try makeHistorySong(id: "first")
        let secondSong = try makeHistorySong(id: "second")
        let serverURL = "http://music.example:4533/"

        store.record(
            PlaybackHistoryEvent(
                song: firstSong,
                playedAt: Date(timeIntervalSince1970: 100)
            ),
            for: serverURL
        )
        store.record(
            PlaybackHistoryEvent(
                song: secondSong,
                playedAt: Date(timeIntervalSince1970: 200)
            ),
            for: serverURL
        )
        store.record(
            PlaybackHistoryEvent(
                song: firstSong,
                playedAt: Date(timeIntervalSince1970: 300)
            ),
            for: serverURL
        )

        XCTAssertEqual(store.recentItems().map(\.id), ["first", "second"])
        XCTAssertEqual(store.mostPlayedItems().first?.id, "first")
        XCTAssertEqual(store.items.first(where: { $0.id == "first" })?.playCount, 2)
    }

    @MainActor
    func testListeningHistorySeparatesServersAndPersists() throws {
        let suiteName = "NaviLyricsCoreTests.history.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let song = try makeHistorySong(id: "song")
        let firstServer = "https://music.example:4533/"
        let secondServer = "https://other.example:4533"

        let firstStore = ListeningHistoryStore(defaults: defaults)
        firstStore.record(
            PlaybackHistoryEvent(song: song, playedAt: Date()),
            for: firstServer
        )
        firstStore.activate(serverURL: secondServer)
        XCTAssertTrue(firstStore.items.isEmpty)

        let secondStore = ListeningHistoryStore(defaults: defaults)
        secondStore.activate(serverURL: firstServer)
        XCTAssertEqual(secondStore.items.map(\.id), ["song"])

        secondStore.clearCurrentServerHistory()
        XCTAssertTrue(secondStore.items.isEmpty)
    }

    @MainActor
    private func makeHistorySong(id: String) throws -> NowPlayingSong {
        let streamURL = try XCTUnwrap(
            URL(string: "https://music.example.com/stream/\(id)")
        )
        return NowPlayingSong(
            id: id,
            title: "歌曲 \(id)",
            artist: "歌手",
            album: "专辑",
            duration: 180,
            streamURL: streamURL,
            artworkURL: nil,
            artworkIdentifier: "cover-\(id)"
        )
    }
}
