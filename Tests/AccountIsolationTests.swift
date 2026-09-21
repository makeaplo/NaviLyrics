import XCTest
@testable import NaviLyrics

final class AccountIsolationTests: XCTestCase {
    @MainActor
    func testIdentityNormalizesServerAndPreservesUsernameCase() {
        let alice = LibraryIdentity.account(serverURL: "HTTPS://MUSIC.EXAMPLE:443/navi/", username: " Alice ")
        XCTAssertEqual(alice, LibraryIdentity.account(serverURL: "https://music.example/navi", username: "Alice"))
        XCTAssertNotEqual(alice, LibraryIdentity.account(serverURL: "https://music.example/navi", username: "alice"))
        XCTAssertNotEqual(alice, LibraryIdentity.account(serverURL: "https://music.example/other", username: "Alice"))
        XCTAssertEqual(LibraryIdentity.normalizedKey(alice), alice)
        XCTAssertFalse(alice.contains("Alice"))
        XCTAssertFalse(alice.contains("music.example"))
    }

    @MainActor
    func testHistoryBehaviorAndRecommendationSnapshotsAreIsolatedAndClearIndependently() throws {
        let suite = "AccountIsolation.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let alice = account("alice")
        let bob = account("bob")
        let history = ListeningHistoryStore(defaults: defaults)
        let behavior = PlaybackBehaviorStore(defaults: defaults)
        let cache = PersonalizedRecommendationCache(defaults: defaults)
        let song = SubsonicSong(id: "song", title: "Song", artist: "Artist", album: "Album",
                                duration: 180, suffix: nil, bitRate: nil, coverArt: nil, isStarred: false)
        let event = PlaybackHistoryEvent(song: nowPlaying("song"), playedAt: Date())
        let recommendations = [PersonalizedRecommendation(song: song, reason: .discover, score: 1)]
        for key in [alice, bob] {
            history.activate(serverURL: key)
            behavior.activate(serverURL: key)
            cache.activate(serverURL: key)
            XCTAssertTrue(history.items.isEmpty)
            XCTAssertTrue(behavior.items.isEmpty)
            XCTAssertNil(cache.cachedRecommendations(librarySignature: "lib", signalSignature: "sig"))
            history.record(event, for: key)
            behavior.record(event, for: key)
            cache.save(recommendations, librarySignature: "lib", signalSignature: "sig")
        }
        history.clearCurrentServerHistory()
        behavior.clearCurrentServerBehavior()
        cache.clearCurrentAccount()
        XCTAssertTrue(history.items.isEmpty)
        XCTAssertTrue(behavior.items.isEmpty)
        XCTAssertNil(cache.cachedRecommendations(librarySignature: "lib", signalSignature: "sig"))
        let restoredHistory = ListeningHistoryStore(defaults: defaults)
        let restoredBehavior = PlaybackBehaviorStore(defaults: defaults)
        let restoredCache = PersonalizedRecommendationCache(defaults: defaults)
        restoredHistory.activate(serverURL: alice)
        restoredBehavior.activate(serverURL: alice)
        restoredCache.activate(serverURL: alice)
        XCTAssertEqual(restoredHistory.items.map(\.id), ["song"])
        XCTAssertEqual(restoredBehavior.items.first?.playCount, 1)
        XCTAssertEqual(restoredCache.cachedRecommendations(librarySignature: "lib", signalSignature: "sig"), recommendations)
    }

    @MainActor
    func testLegacyServerOnlyHistoryIsNotAssignedToFirstAccount() throws {
        let suite = "LegacyIsolation.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ListeningHistoryStore(defaults: defaults)
        store.record(PlaybackHistoryEvent(song: nowPlaying("legacy"), playedAt: Date()), for: "https://music.example")
        store.activate(serverURL: account("alice"))
        XCTAssertTrue(store.items.isEmpty)
        store.activate(serverURL: account("bob"))
        XCTAssertTrue(store.items.isEmpty)
        store.activate(serverURL: "https://music.example")
        XCTAssertEqual(store.items.map(\.id), ["legacy"])
    }

    @MainActor
    func testQueueSnapshotsDoNotOverwriteOtherAccounts() throws {
        let suite = "QueueIsolation.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Seed valid credential-free snapshots. Restore remains paused.
        for user in ["alice", "bob"] {
            let key = account(user)
            let data = try JSONSerialization.data(withJSONObject: [
                "serverURL": key, "queue": [["id": user, "title": user, "artist": "A",
                    "album": "B", "duration": 180]], "queueIndex": 0, "progress": 12
            ])
            defaults.set(data, forKey: "lastPlaybackState.v3." + key)
        }
        let player = PlayerStore(defaults: defaults)
        // Demo URL avoids external audio/network access; storage keys still use real account identities.
        let client = SubsonicClient.demo()
        XCTAssertTrue(player.restoreLastPlayback(for: account("alice"), using: client))
        XCTAssertEqual(player.currentSong?.id, "alice")
        XCTAssertFalse(player.isPlaying)
        XCTAssertTrue(player.restoreLastPlayback(for: account("bob"), using: client))
        XCTAssertEqual(player.currentSong?.id, "bob")
        player.reset(clearsPersistedState: true)
        XCTAssertNil(defaults.data(forKey: "lastPlaybackState.v3." + account("bob")))
        XCTAssertNotNil(defaults.data(forKey: "lastPlaybackState.v3." + account("alice")))
        XCTAssertTrue(player.restoreLastPlayback(for: account("alice"), using: client))
        XCTAssertEqual(player.currentSong?.id, "alice")
        player.reset()
    }

    @MainActor
    func testNewPlaybackWritesSeparateCredentialFreeQueues() throws {
        let suite = "QueueWrites.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let player = PlayerStore(defaults: defaults)
        for user in ["alice", "bob"] {
            XCTAssertFalse(player.restoreLastPlayback(for: account(user), using: .demo()))
            let song = NowPlayingSong(id: user, title: user, artist: "A", album: "B", duration: 180,
                                      streamURL: URL(fileURLWithPath: "/nonexistent-test-audio.m4a"), artworkURL: nil)
            player.load(song: song, autoplay: false)
            player.persistPlaybackState(force: true)
            player.reset()
        }
        for user in ["alice", "bob"] {
            let data = try XCTUnwrap(defaults.data(forKey: "lastPlaybackState.v3." + account(user)))
            let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let queue = try XCTUnwrap(snapshot["queue"] as? [[String: Any]])
            XCTAssertEqual(queue.first?["id"] as? String, user)
            XCTAssertNil(queue.first?["streamURL"])
        }
    }

    @MainActor
    func testFavoritesIgnoreResponseFromPreviousAccount() async throws {
        var pending: CheckedContinuation<Void, Never>?
        let transport = StubSubsonicTransport { _ in
            await withCheckedContinuation { pending = $0 }
            return ["status": "ok", "starred2": ["song": [["id": "alice-song", "title": "Alice"]]]]
        }
        let store = FavoritesStore()
        store.activate(serverURL: account("alice"))
        let client = SubsonicClient(baseURL: URL(string: "https://music.example")!, username: "alice",
                                   password: "test", transport: transport)
        let request = Task { await store.refresh(using: client) }
        while pending == nil { await Task.yield() }
        store.activate(serverURL: account("bob"))
        pending?.resume()
        await request.value
        XCTAssertTrue(store.songs.isEmpty)
        XCTAssertFalse(store.hasLoaded)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    private func account(_ username: String) -> String {
        LibraryIdentity.account(serverURL: "https://music.example", username: username)
    }

    @MainActor
    private func nowPlaying(_ id: String) -> NowPlayingSong {
        NowPlayingSong(id: id, title: id, artist: "A", album: "B", duration: 180,
                       streamURL: URL(string: "navi-demo://song/\(id)")!, artworkURL: nil)
    }
}
