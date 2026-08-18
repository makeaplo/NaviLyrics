import XCTest
@testable import NaviLyrics

final class PlaybackBehaviorStoreTests: XCTestCase {
    @MainActor
    func testBehaviorStoreSeparatesPositiveAndNegativeSignals() throws {
        let suiteName = "NaviLyricsCoreTests.behavior.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PlaybackBehaviorStore(defaults: defaults)
        let song = try makeSong(id: "song")
        let serverURL = "http://music.example:4533/"

        store.record(
            PlaybackHistoryEvent(
                song: song,
                playedAt: Date(timeIntervalSince1970: 100),
                kind: .qualified
            ),
            for: serverURL
        )
        store.record(
            PlaybackHistoryEvent(
                song: song,
                playedAt: Date(timeIntervalSince1970: 120),
                kind: .completed
            ),
            for: serverURL
        )
        store.record(
            PlaybackHistoryEvent(
                song: song,
                playedAt: Date(timeIntervalSince1970: 140),
                kind: .skipped
            ),
            for: serverURL
        )

        let summary = try XCTUnwrap(store.items.first)
        XCTAssertEqual(summary.playCount, 1)
        XCTAssertEqual(summary.completionCount, 1)
        XCTAssertEqual(summary.skipCount, 1)
    }

    @MainActor
    func testBehaviorStorePersistsPerServer() throws {
        let suiteName = "NaviLyricsCoreTests.behavior.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let song = try makeSong(id: "song")
        let firstServer = "https://music.example:4533/"
        let secondServer = "https://other.example:4533"
        let store = PlaybackBehaviorStore(defaults: defaults)

        store.record(
            PlaybackHistoryEvent(song: song, playedAt: Date()),
            for: firstServer
        )
        store.activate(serverURL: secondServer)
        XCTAssertTrue(store.items.isEmpty)

        let restored = PlaybackBehaviorStore(defaults: defaults)
        restored.activate(serverURL: firstServer)
        XCTAssertEqual(restored.items.map(\.id), ["song"])
    }

    @MainActor
    private func makeSong(id: String) throws -> NowPlayingSong {
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
