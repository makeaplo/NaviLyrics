import XCTest
@testable import NaviLyrics

@MainActor
final class StubSubsonicTransport: SubsonicTransport {
    var requests: [URLRequest] = []
    var handler: @MainActor (URLRequest) async throws -> [String: Any]

    init(handler: @escaping @MainActor (URLRequest) async throws -> [String: Any]) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let payload = try await handler(request)
        let data = try JSONSerialization.data(withJSONObject: ["subsonic-response": payload])
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    static func parameter(_ name: String, in request: URLRequest) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }
}

final class LibraryLoadingTests: XCTestCase {
    @MainActor
    func testPaginationLoads301600And1000Albums() async throws {
        for count in [0, 301, 600, 1000] {
            let transport = StubSubsonicTransport { request in
                let offset = Int(StubSubsonicTransport.parameter("offset", in: request)!)!
                let size = Int(StubSubsonicTransport.parameter("size", in: request)!)!
                let entries = (min(offset, count)..<min(offset + size, count)).map {
                    ["id": "album-\($0)", "name": "Album \($0)"]
                }
                return ["status": "ok", "albumList2": ["album": entries]]
            }
            let client = makeClient(transport)
            var progress: [Int] = []
            let albums = try await client.allAlbums { progress.append($0) }
            XCTAssertEqual(albums.count, count)
            XCTAssertEqual(Set(albums.map(\.id)).count, count)
            XCTAssertEqual(transport.requests.count, count / 300 + 1)
            if count > 0 { XCTAssertEqual(progress.last, count) }
        }
    }

    @MainActor
    func testRepeatedPageFailsInsteadOfLoopingOrClaimingComplete() async throws {
        let transport = StubSubsonicTransport { _ in
            ["status": "ok", "albumList2": ["album": [["id": "a", "name": "A"]]]]
        }
        do {
            _ = try await makeClient(transport).allAlbums(pageSize: 1)
            XCTFail("Repeated full page must fail")
        } catch SubsonicError.paginationStalled {
            XCTAssertEqual(transport.requests.count, 2)
        }
    }

    @MainActor
    func testCancelledPaginationDoesNotScheduleNextPage() async throws {
        let transport = StubSubsonicTransport { _ in
            throw CancellationError()
        }
        do {
            _ = try await makeClient(transport).allAlbums()
            XCTFail("Cancellation must propagate")
        } catch is CancellationError {
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    @MainActor
    func testRecommendationLoadingBoundsConcurrencyAndDeduplicates() async throws {
        for count in [100, 300, 1000] {
            var active = 0
            var maximumActive = 0
            let transport = StubSubsonicTransport { request in
                active += 1
                maximumActive = max(maximumActive, active)
                defer { active -= 1 }
                // Yield while the request is in flight; assertions don't depend on timing.
                await Task.yield()
                await Task.yield()
                let id = StubSubsonicTransport.parameter("id", in: request)!
                return ["status": "ok", "album": ["song": [
                    ["id": id, "title": id], ["id": "shared", "title": "Shared"]
                ]]]
            }
            let albums = (0..<count).map {
                SubsonicAlbum(id: "a\($0)", title: "A", artist: "", coverArt: nil, year: nil)
            }
            var completed = 0
            let songs = try await makeClient(transport).librarySongs(from: albums + [albums[0]]) { done, total in
                completed = done
                XCTAssertEqual(total, count)
            }
            XCTAssertEqual(transport.requests.count, count)
            XCTAssertEqual(completed, count)
            XCTAssertGreaterThan(maximumActive, 1)
            XCTAssertLessThanOrEqual(maximumActive, 4)
            XCTAssertEqual(songs.count, count + 1)
            XCTAssertEqual(songs.prefix(3).map(\.id), ["a0", "shared", "a1"])
        }
    }

    @MainActor
    func testRecommendationFailureDoesNotReturnPartialResults() async throws {
        let transport = StubSubsonicTransport { _ in throw URLError(.notConnectedToInternet) }
        let albums = (0..<20).map {
            SubsonicAlbum(id: "\($0)", title: "A", artist: "", coverArt: nil, year: nil)
        }
        do {
            _ = try await makeClient(transport).librarySongs(from: albums)
            XCTFail("Failure must propagate without a partial snapshot")
        } catch {
            XCTAssertLessThanOrEqual(transport.requests.count, 4)
        }
    }

    @MainActor
    func testRefreshFailureRetainsPreviousLibrary() async throws {
        let transport = StubSubsonicTransport { request in
            if request.url!.path.contains("ping") { return ["status": "ok"] }
            return ["status": "ok", "albumList2": ["album": [["id": "old", "name": "Old"]]]]
        }
        let session = NavidromeSession(transport: transport)
        let signedIn = await session.signIn(serverURL: "https://music.example", username: "alice",
                                            password: "test", settings: AppSettings(), savesCredentials: false)
        XCTAssertTrue(signedIn)
        transport.handler = { request in
            if request.url!.path.contains("ping") { return ["status": "ok"] }
            let offset = StubSubsonicTransport.parameter("offset", in: request)
            if offset == "0" {
                return ["status": "ok", "albumList2": ["album": (0..<300).map {
                    ["id": "new-\($0)", "name": "New"]
                }]]
            }
            throw URLError(.networkConnectionLost)
        }
        await session.refreshLibrary()
        XCTAssertEqual(session.albums.map(\.id), ["old"])
        XCTAssertEqual(session.status, .connected)
        XCTAssertNotNil(session.libraryErrorMessage)
        XCTAssertFalse(session.isRefreshing)
    }

    @MainActor
    func testSignOutDuringLoadCannotReconnectOldAccount() async throws {
        var pending: CheckedContinuation<Void, Never>?
        let transport = StubSubsonicTransport { request in
            if request.url!.path.contains("ping") { return ["status": "ok"] }
            await withCheckedContinuation { pending = $0 }
            return ["status": "ok", "albumList2": ["album": [["id": "old", "name": "Old"]]]]
        }
        let session = NavidromeSession(transport: transport)
        let login = Task {
            await session.signIn(serverURL: "https://music.example", username: "alice", password: "test",
                                 settings: AppSettings(), savesCredentials: false)
        }
        while pending == nil { await Task.yield() }
        session.requireSignIn()
        pending?.resume()
        let connected = await login.value
        XCTAssertFalse(connected)
        XCTAssertEqual(session.status, .signedOut)
        XCTAssertNil(session.client)
        XCTAssertTrue(session.albums.isEmpty)
    }

    @MainActor
    func testCancelButtonCancelsConnectionDuringPing() async throws {
        var pending: CheckedContinuation<Void, Never>?
        let transport = StubSubsonicTransport { _ in
            await withCheckedContinuation { pending = $0 }
            return ["status": "ok"]
        }
        let session = NavidromeSession(transport: transport)
        let login = Task {
            await session.signIn(serverURL: "https://music.example", username: "alice", password: "test",
                                 settings: AppSettings(), savesCredentials: false)
        }
        while pending == nil { await Task.yield() }
        session.cancelLibraryLoading()
        pending?.resume()
        let connected = await login.value
        XCTAssertFalse(connected)
        XCTAssertEqual(session.status, .signedOut)
        XCTAssertEqual(transport.requests.count, 1)
    }

    @MainActor
    private func makeClient(_ transport: any SubsonicTransport) -> SubsonicClient {
        SubsonicClient(baseURL: URL(string: "https://music.example")!, username: "alice",
                       password: "test", transport: transport)
    }
}
