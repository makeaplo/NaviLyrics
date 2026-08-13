import Foundation

// MARK: - 模型

struct SubsonicAlbum: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let coverArt: String?
    let year: Int?
}

struct SubsonicPlaylist: Identifiable, Hashable {
    let id: String
    let name: String
    let songCount: Int
    let coverArt: String?
}

struct SubsonicArtist: Identifiable, Hashable {
    let id: String
    let name: String
    let albumCount: Int
}

struct SubsonicSong: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let suffix: String?      // 文件格式 flac/mp3
    let bitRate: Int?
    let coverArt: String?
    var isStarred: Bool
}

struct SubsonicSearchResults {
    let songs: [SubsonicSong]
    let albums: [SubsonicAlbum]
    let artists: [SubsonicArtist]

    init(
        songs: [SubsonicSong] = [],
        albums: [SubsonicAlbum] = [],
        artists: [SubsonicArtist] = []
    ) {
        self.songs = songs
        self.albums = albums
        self.artists = artists
    }

    var isEmpty: Bool {
        songs.isEmpty && albums.isEmpty && artists.isEmpty
    }
}

enum SubsonicLyricsResult {
    case structured([SubsonicStructuredLyrics])
    case text(String)
}

// MARK: - 本地演示数据

/// A small in-process library used by the hidden development entry point.
/// It never touches the real Navidrome account or network.
@MainActor
private final class DemoClientState {
    let albums: [SubsonicAlbum]
    let artists: [SubsonicArtist]
    var songsByAlbum: [String: [SubsonicSong]]
    var playlists: [SubsonicPlaylist]
    var playlistSongs: [String: [SubsonicSong]]
    var favorites: [SubsonicSong]

    init() {
        let firstAlbum = SubsonicAlbum(
            id: "demo-album-midnight",
            title: "Midnight Signals",
            artist: "NaviLyrics Studio",
            coverArt: "demo-cover-midnight",
            year: 2024
        )
        let secondAlbum = SubsonicAlbum(
            id: "demo-album-afterglow",
            title: "Afterglow Letters",
            artist: "NaviLyrics Studio",
            coverArt: "demo-cover-afterglow",
            year: 2023
        )

        let midnightSongs = [
            SubsonicSong(
                id: "demo-song-first-light",
                title: "First Light",
                artist: firstAlbum.artist,
                album: firstAlbum.title,
                duration: 214,
                suffix: "aac",
                bitRate: 256,
                coverArt: firstAlbum.coverArt,
                isStarred: true
            ),
            SubsonicSong(
                id: "demo-song-city-rain",
                title: "City Rain",
                artist: firstAlbum.artist,
                album: firstAlbum.title,
                duration: 187,
                suffix: "flac",
                bitRate: 960,
                coverArt: firstAlbum.coverArt,
                isStarred: false
            ),
            SubsonicSong(
                id: "demo-song-slow-orbit",
                title: "Slow Orbit",
                artist: firstAlbum.artist,
                album: firstAlbum.title,
                duration: 246,
                suffix: "mp3",
                bitRate: 320,
                coverArt: firstAlbum.coverArt,
                isStarred: true
            ),
        ]
        let afterglowSongs = [
            SubsonicSong(
                id: "demo-song-paper-moon",
                title: "Paper Moon",
                artist: secondAlbum.artist,
                album: secondAlbum.title,
                duration: 201,
                suffix: "flac",
                bitRate: 960,
                coverArt: secondAlbum.coverArt,
                isStarred: false
            ),
            SubsonicSong(
                id: "demo-song-soft-static",
                title: "Soft Static",
                artist: secondAlbum.artist,
                album: secondAlbum.title,
                duration: 173,
                suffix: "aac",
                bitRate: 256,
                coverArt: secondAlbum.coverArt,
                isStarred: false
            ),
            SubsonicSong(
                id: "demo-song-homeward",
                title: "Homeward",
                artist: secondAlbum.artist,
                album: secondAlbum.title,
                duration: 229,
                suffix: "mp3",
                bitRate: 320,
                coverArt: secondAlbum.coverArt,
                isStarred: true
            ),
        ]

        albums = [firstAlbum, secondAlbum]
        artists = [
            SubsonicArtist(
                id: "demo-artist-studio",
                name: "NaviLyrics Studio",
                albumCount: albums.count
            )
        ]
        songsByAlbum = [
            firstAlbum.id: midnightSongs,
            secondAlbum.id: afterglowSongs,
        ]

        let playlistID = "demo-playlist-late-night"
        playlists = [
            SubsonicPlaylist(
                id: playlistID,
                name: "深夜漫游",
                songCount: 3,
                coverArt: firstAlbum.coverArt
            )
        ]
        playlistSongs = [
            playlistID: [
                midnightSongs[0],
                afterglowSongs[0],
                afterglowSongs[2],
            ]
        ]
        favorites = [midnightSongs[0], midnightSongs[2], afterglowSongs[2]]
    }

    var allSongs: [SubsonicSong] {
        albums.flatMap { songsByAlbum[$0.id] ?? [] }
    }

    func song(withID id: String) -> SubsonicSong? {
        allSongs.first { $0.id == id }
    }

    func updateFavorite(songID: String, isFavorite: Bool) {
        guard let original = song(withID: songID) else { return }
        var updated = original
        updated.isStarred = isFavorite
        favorites.removeAll { $0.id == songID }
        if isFavorite {
            favorites.insert(updated, at: 0)
        }

        for albumID in Array(songsByAlbum.keys) {
            songsByAlbum[albumID] = songsByAlbum[albumID]?.map { song in
                guard song.id == songID else { return song }
                var song = song
                song.isStarred = isFavorite
                return song
            }
        }
        for playlistID in Array(playlistSongs.keys) {
            playlistSongs[playlistID] = playlistSongs[playlistID]?.map {
                song in
                guard song.id == songID else { return song }
                var song = song
                song.isStarred = isFavorite
                return song
            }
        }
    }

    func refreshPlaylist(_ playlistID: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else {
            return
        }
        let playlist = playlists[index]
        playlists[index] = SubsonicPlaylist(
            id: playlist.id,
            name: playlist.name,
            songCount: playlistSongs[playlistID]?.count ?? 0,
            coverArt: playlist.coverArt
        )
    }
}

// MARK: - 客户端

/// Navidrome 实现了标准 Subsonic API（v1.16+），使用 REST + 密码盐加密认证。
@MainActor
struct SubsonicClient {
    private static let maximumResponseSize = 20 * 1_024 * 1_024
    let baseURL: URL
    let username: String
    let password: String

    private let authenticationSalt: String
    private let authenticationToken: String
    private let clientName = "navilyrics"
    private let apiVersion = "1.16.1"
    private let demoState: DemoClientState?

    init(baseURL: URL, username: String, password: String) {
        let salt = String(
            UUID().uuidString
                .replacingOccurrences(of: "-", with: "")
                .prefix(12)
        )
        self.baseURL = baseURL
        self.username = username
        self.password = password
        authenticationSalt = salt
        authenticationToken = (password + salt).md5
        demoState = nil
    }

    @MainActor
    private init(demoState: DemoClientState) {
        baseURL = URL(string: "navi-demo://local-library")!
        username = "演示用户"
        password = ""
        authenticationSalt = ""
        authenticationToken = ""
        self.demoState = demoState
    }

    @MainActor
    static func demo() -> SubsonicClient {
        SubsonicClient(demoState: DemoClientState())
    }

    @MainActor
    var isDemoMode: Bool {
        demoState != nil
    }

    @MainActor
    func demoPreviewSongs() -> [SubsonicSong] {
        demoState?.allSongs ?? []
    }

    func demoAlbums() -> [SubsonicAlbum] {
        demoState?.albums ?? []
    }

    func makeNowPlayingSong(from song: SubsonicSong) -> NowPlayingSong {
        NowPlayingSong(
            id: song.id,
            title: song.title,
            artist: song.artist,
            album: song.album,
            duration: song.duration,
            streamURL: streamURL(songID: song.id),
            artworkURL: coverURL(coverArt: song.coverArt, size: 900),
            artworkIdentifier: song.coverArt
        )
    }

    // MARK: 认证

    func ping() async throws -> Bool {
        if demoState != nil { return true }
        let resp: SubsonicResponse = try await request("ping", params: [:])
        return resp.status == "ok"
    }

    // MARK: 音乐库

    /// 专辑列表（newest / random / alphabetical / recent / frequent / highest）
    func albumList(type: String = "newest", size: Int = 200) async throws -> [SubsonicAlbum] {
        if let demoState { return demoState.albums }
        let resp: SubsonicResponse = try await request(
            "getAlbumList2",
            params: ["type": type, "size": "\(size)"]
        )
        let albums = resp.albumList2?.album ?? []
        return albums.map { a in
            SubsonicAlbum(
                id: a.id,
                title: a.title ?? a.name ?? "未命名专辑",
                artist: a.artist ?? "",
                coverArt: a.coverArt, year: a.year
            )
        }
    }

    /// 播放列表目录。
    func playlists() async throws -> [SubsonicPlaylist] {
        if let demoState { return demoState.playlists }
        let resp: SubsonicResponse = try await request(
            "getPlaylists",
            params: [:]
        )
        return (resp.playlists?.playlist ?? []).map { playlist in
            SubsonicPlaylist(
                id: playlist.id,
                name: playlist.name,
                songCount: max(playlist.songCount ?? 0, 0),
                coverArt: playlist.coverArt
            )
        }
    }

    /// 播放列表内歌曲。
    func songs(inPlaylist playlistID: String) async throws -> [SubsonicSong] {
        if let demoState { return demoState.playlistSongs[playlistID] ?? [] }
        let resp: SubsonicResponse = try await request(
            "getPlaylist",
            params: ["id": playlistID]
        )
        return (resp.playlist?.entry ?? []).map(makeSong(from:))
    }

    /// 创建播放列表，可选地一次加入歌曲。
    func createPlaylist(
        name: String,
        songIDs: [String] = []
    ) async throws {
        if let demoState {
            let id = "demo-playlist-\(UUID().uuidString)"
            let songs = songIDs.compactMap { demoState.song(withID: $0) }
            demoState.playlists.insert(
                SubsonicPlaylist(
                    id: id,
                    name: name,
                    songCount: songs.count,
                    coverArt: songs.first?.coverArt
                ),
                at: 0
            )
            demoState.playlistSongs[id] = songs
            return
        }
        let songItems = songIDs.map {
            URLQueryItem(name: "songId", value: $0)
        }
        _ = try await request(
            "createPlaylist",
            params: ["name": name],
            additionalItems: songItems
        )
    }

    /// 修改播放列表名称，或加入、移除其中的歌曲。
    func updatePlaylist(
        id: String,
        name: String? = nil,
        songIDsToAdd: [String] = [],
        songIndicesToRemove: [Int] = []
    ) async throws {
        if let demoState {
            guard let index = demoState.playlists.firstIndex(
                where: { $0.id == id }
            ) else { return }
            if let name {
                let playlist = demoState.playlists[index]
                demoState.playlists[index] = SubsonicPlaylist(
                    id: playlist.id,
                    name: name,
                    songCount: playlist.songCount,
                    coverArt: playlist.coverArt
                )
            }
            var songs = demoState.playlistSongs[id] ?? []
            for songIndex in songIndicesToRemove.sorted(by: >)
                where songs.indices.contains(songIndex) {
                songs.remove(at: songIndex)
            }
            for songID in songIDsToAdd {
                if let song = demoState.song(withID: songID),
                   !songs.contains(where: { $0.id == songID }) {
                    songs.append(song)
                }
            }
            demoState.playlistSongs[id] = songs
            demoState.refreshPlaylist(id)
            return
        }
        var params = ["playlistId": id]
        if let name {
            params["name"] = name
        }
        let addItems = songIDsToAdd.map {
            URLQueryItem(name: "songIdToAdd", value: $0)
        }
        let removeItems = songIndicesToRemove.map {
            URLQueryItem(name: "songIndexToRemove", value: "\($0)")
        }
        _ = try await request(
            "updatePlaylist",
            params: params,
            additionalItems: addItems + removeItems
        )
    }

    /// 删除播放列表。
    func deletePlaylist(id: String) async throws {
        if let demoState {
            demoState.playlists.removeAll { $0.id == id }
            demoState.playlistSongs.removeValue(forKey: id)
            return
        }
        _ = try await request("deletePlaylist", params: ["id": id])
    }

    /// 专辑内歌曲
    func songs(inAlbum albumID: String) async throws -> [SubsonicSong] {
        if let demoState { return demoState.songsByAlbum[albumID] ?? [] }
        let resp: SubsonicResponse = try await request(
            "getAlbum",
            params: ["id": albumID]
        )
        let songs = resp.album?.song ?? []
        return songs.map(makeSong(from:))
    }

    /// 歌手详情及其专辑。
    func albums(byArtist artistID: String) async throws -> [SubsonicAlbum] {
        if let demoState {
            let artistName = demoState.artists.first {
                $0.id == artistID
            }?.name
            return demoState.albums.filter { $0.artist == artistName }
        }
        let resp: SubsonicResponse = try await request(
            "getArtist",
            params: ["id": artistID]
        )
        return (resp.artist?.album ?? []).map(makeAlbum(from:))
    }

    /// 搜索
    func search(query: String) async throws -> SubsonicSearchResults {
        if let demoState {
            let normalizedQuery = query.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).lowercased()
            return SubsonicSearchResults(
                songs: demoState.allSongs.filter {
                    [$0.title, $0.artist, $0.album].contains {
                        $0.lowercased().contains(normalizedQuery)
                    }
                },
                albums: demoState.albums.filter {
                    [$0.title, $0.artist].contains {
                        $0.lowercased().contains(normalizedQuery)
                    }
                },
                artists: demoState.artists.filter {
                    $0.name.lowercased().contains(normalizedQuery)
                }
            )
        }
        let resp: SubsonicResponse = try await request(
            "search3",
            params: [
                "query": query,
                "songCount": "100",
                "albumCount": "50",
                "artistCount": "50",
            ]
        )
        let result = resp.searchResult3
        return SubsonicSearchResults(
            songs: (result?.song ?? []).map(makeSong(from:)),
            albums: (result?.album ?? []).map(makeAlbum(from:)),
            artists: (result?.artist ?? []).map { artist in
                SubsonicArtist(
                    id: artist.id,
                    name: artist.name,
                    albumCount: max(artist.albumCount ?? 0, 0)
                )
            }
        )
    }

    /// 返回当前账号标记为喜欢的歌曲。
    func starredSongs() async throws -> [SubsonicSong] {
        if let demoState { return demoState.favorites }
        let resp: SubsonicResponse = try await request(
            "getStarred2",
            params: [:]
        )
        return (resp.starred2?.song ?? []).map(makeSong(from:))
    }

    /// 在 Navidrome 中添加或取消歌曲收藏。
    func setFavorite(songID: String, isFavorite: Bool) async throws {
        if let demoState {
            demoState.updateFavorite(songID: songID, isFavorite: isFavorite)
            return
        }
        _ = try await request(
            isFavorite ? "star" : "unstar",
            params: ["id": songID]
        )
    }

    /// 优先读取 OpenSubsonic 结构化歌词（支持逐字时间），不支持时回退到传统歌词接口。
    func lyrics(
        songID: String,
        artist: String,
        title: String
    ) async throws -> SubsonicLyricsResult? {
        if demoState != nil {
            return .structured([
                SubsonicStructuredLyrics(
                    displayArtist: artist,
                    displayTitle: title,
                    lang: "en",
                    kind: "main",
                    synced: true,
                    line: [
                        SubsonicStructuredLyricLine(start: 0, value: "City lights are waking slowly"),
                        SubsonicStructuredLyricLine(start: 7_000, value: "Footsteps echo through the blue"),
                        SubsonicStructuredLyricLine(start: 14_000, value: "Every quiet road is glowing"),
                        SubsonicStructuredLyricLine(start: 21_000, value: "I keep finding my way to you"),
                    ],
                    cueLine: nil
                ),
                SubsonicStructuredLyrics(
                    displayArtist: artist,
                    displayTitle: title,
                    lang: "zh",
                    kind: "translation",
                    synced: true,
                    line: [
                        SubsonicStructuredLyricLine(start: 0, value: "城市灯火慢慢醒来"),
                        SubsonicStructuredLyricLine(start: 7_000, value: "脚步声穿过蓝色夜幕"),
                        SubsonicStructuredLyricLine(start: 14_000, value: "每条安静的路都在发光"),
                        SubsonicStructuredLyricLine(start: 21_000, value: "我总能找到通往你的方向"),
                    ],
                    cueLine: nil
                ),
            ])
        }
        do {
            let resp = try await request(
                "getLyricsBySongId",
                params: ["id": songID, "enhanced": "true"]
            )
            if let lyrics = resp.lyricsList?.structuredLyrics,
               !lyrics.isEmpty {
                return .structured(lyrics)
            }
        } catch {
            // 旧版服务器可能尚未实现结构化歌词扩展，继续尝试传统接口。
        }

        do {
            let resp = try await request(
                "getLyrics",
                params: ["artist": artist, "title": title]
            )
            guard let value = resp.lyrics?.value,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return .text(value)
        } catch {
            throw error
        }
    }

    /// 歌曲流 URL（播放用）
    func streamURL(songID: String) -> URL {
        if demoState != nil {
            return URL(string: "navi-demo://stream/\(songID)")!
        }
        guard var comps = URLComponents(
            url: baseURL.appendingPathComponent("rest/stream.view"),
            resolvingAgainstBaseURL: false
        ) else {
            return baseURL
        }
        comps.queryItems = makeAuthItems() + [
            URLQueryItem(name: "id", value: songID),
            URLQueryItem(name: "format", value: "raw"),  // 原样传输，不转码
        ]
        return comps.url ?? baseURL
    }

    /// 封面 URL
    func coverURL(coverArt: String?, size: Int = 600) -> URL? {
        guard let coverArt, !coverArt.isEmpty else { return nil }
        if demoState != nil {
            return URL(string: "navi-demo://cover/\(coverArt)")
        }
        guard var comps = URLComponents(
            url: baseURL.appendingPathComponent("rest/getCoverArt.view"),
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        comps.queryItems = makeAuthItems() + [
            URLQueryItem(name: "id", value: coverArt),
            URLQueryItem(name: "size", value: "\(size)"),
        ]
        return comps.url
    }

    // MARK: 底层

    private func makeAuthItems() -> [URLQueryItem] {
        return [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "t", value: authenticationToken),
            URLQueryItem(name: "s", value: authenticationSalt),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "c", value: clientName),
            URLQueryItem(name: "f", value: "json"),
        ]
    }

    private func makeSong(from entry: SongEntry) -> SubsonicSong {
        SubsonicSong(
            id: entry.id,
            title: entry.title,
            artist: entry.artist ?? "",
            album: entry.album ?? "",
            duration: TimeInterval(entry.duration ?? 0),
            suffix: entry.suffix,
            bitRate: entry.bitRate,
            coverArt: entry.coverArt,
            isStarred: entry.starred != nil
        )
    }

    private func makeAlbum(from entry: AlbumEntry) -> SubsonicAlbum {
        SubsonicAlbum(
            id: entry.id,
            title: entry.title ?? entry.name ?? "未命名专辑",
            artist: entry.artist ?? "",
            coverArt: entry.coverArt,
            year: entry.year
        )
    }

    private func request(
        _ method: String,
        params: [String: String],
        additionalItems: [URLQueryItem] = []
    ) async throws -> SubsonicResponse {
        guard var comps = URLComponents(
            url: baseURL.appendingPathComponent("rest/\(method).view"),
            resolvingAgainstBaseURL: false
        ) else {
            throw SubsonicError.invalidURL
        }
        var items = makeAuthItems()
        items.append(contentsOf: params.map { URLQueryItem(name: $0.key, value: $0.value) })
        items.append(contentsOf: additionalItems)
        comps.queryItems = items

        guard let url = comps.url else {
            throw SubsonicError.invalidURL
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SubsonicError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw SubsonicError.http(statusCode: http.statusCode)
        }
        guard data.count <= Self.maximumResponseSize else {
            throw SubsonicError.responseTooLarge
        }
        let decoder = JSONDecoder()
        let envelope: SubsonicResponseEnvelope
        do {
            envelope = try decoder.decode(SubsonicResponseEnvelope.self, from: data)
        } catch let error as DecodingError {
            throw SubsonicError.decoding(
                endpoint: method,
                detail: Self.decodingDetail(for: error)
            )
        } catch {
            throw SubsonicError.invalidResponse
        }
        guard envelope.response.status == "ok" else {
            throw SubsonicError.api(
                code: envelope.response.error?.code,
                message: envelope.response.error?.message
                    ?? "服务器拒绝了请求"
            )
        }
        return envelope.response
    }

    private static func decodingDetail(for error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, context):
            return "缺少字段 \(codingPath(context.codingPath + [key]))"
        case let .typeMismatch(_, context):
            return "字段类型不兼容 \(codingPath(context.codingPath))"
        case let .valueNotFound(_, context):
            return "字段为空 \(codingPath(context.codingPath))"
        case let .dataCorrupted(context):
            return "数据损坏 \(codingPath(context.codingPath))"
        @unknown default:
            return "未知解码错误"
        }
    }

    private static func codingPath(_ path: [CodingKey]) -> String {
        let value = path.map { key in
            key.intValue.map { "[\($0)]" } ?? key.stringValue
        }.joined(separator: ".")
        return value.isEmpty ? "<root>" : value
    }
}

enum SubsonicError: LocalizedError {
    case invalidURL
    case invalidResponse
    case http(statusCode: Int)
    case api(code: Int?, message: String)
    case decoding(endpoint: String, detail: String)
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "服务器地址无效"
        case .invalidResponse:
            "服务器返回了无法识别的响应"
        case let .http(statusCode):
            "服务器请求失败（HTTP \(statusCode)）"
        case let .api(code, message):
            code.map { "\(message)（错误码 \($0)）" } ?? message
        case let .decoding(endpoint, detail):
            "\(endpoint) 响应格式不兼容：\(detail)"
        case .responseTooLarge:
            "服务器响应过大，已停止处理以保护设备内存"
        }
    }
}

// MARK: - 响应结构

private struct SubsonicResponseEnvelope: Decodable {
    let response: SubsonicResponse

    private enum CodingKeys: String, CodingKey {
        case response = "subsonic-response"
    }
}

struct SubsonicResponse: Decodable {
    let status: String
    let version: String?
    let albumList2: AlbumList2?
    let album: AlbumDetail?
    let artist: ArtistDetail?
    let playlists: Playlists?
    let playlist: PlaylistDetail?
    let searchResult3: SearchResult3?
    let starred2: Starred2?
    let lyrics: LyricWrapper?
    let lyricsList: LyricsList?
    let error: SubsonicAPIError?
}

struct SubsonicAPIError: Decodable {
    let code: Int?
    let message: String?
}

struct AlbumList2: Decodable {
    let album: [AlbumEntry]?
}
struct AlbumEntry: Decodable {
    let id: String
    let title: String?
    let name: String?
    let artist: String?
    let coverArt: String?
    let year: Int?
}
struct AlbumDetail: Decodable {
    let song: [SongEntry]?
}
struct ArtistDetail: Decodable {
    let album: [AlbumEntry]?
}
struct Playlists: Decodable {
    let playlist: [PlaylistEntry]?
}
struct PlaylistEntry: Decodable {
    let id: String
    let name: String
    let songCount: Int?
    let coverArt: String?
}
struct PlaylistDetail: Decodable {
    let entry: [SongEntry]?
}
struct SearchResult3: Decodable {
    let song: [SongEntry]?
    let album: [AlbumEntry]?
    let artist: [ArtistEntry]?
}
struct ArtistEntry: Decodable {
    let id: String
    let name: String
    let albumCount: Int?
}
struct Starred2: Decodable {
    let song: [SongEntry]?
}
struct SongEntry: Decodable {
    let id: String
    let title: String
    let artist: String?
    let album: String?
    let duration: Int?
    let suffix: String?
    let bitRate: Int?
    let coverArt: String?
    let starred: String?
}
struct LyricWrapper: Decodable {
    let value: String?
}

struct LyricsList: Decodable {
    let structuredLyrics: [SubsonicStructuredLyrics]?
}

struct SubsonicStructuredLyrics: Decodable {
    let displayArtist: String?
    let displayTitle: String?
    let lang: String?
    let kind: String?
    let synced: Bool?
    let line: [SubsonicStructuredLyricLine]?
    let cueLine: [SubsonicStructuredCueLine]?
}

struct SubsonicStructuredLyricLine: Decodable {
    let start: Int?
    let value: String
}

struct SubsonicStructuredCueLine: Decodable {
    let start: Int
    let end: Int?
    let value: String
    let cue: [SubsonicStructuredCue]?
}

struct SubsonicStructuredCue: Decodable {
    let start: Int
    let end: Int
    let value: String
}
