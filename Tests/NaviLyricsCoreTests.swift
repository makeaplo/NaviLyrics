import XCTest
@testable import NaviLyrics

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
}
