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

// MARK: - 客户端

/// Navidrome 实现了标准 Subsonic API（v1.16+），使用 REST + 密码盐加密认证。
struct SubsonicClient {
    private static let maximumResponseSize = 20 * 1_024 * 1_024
    let baseURL: URL
    let username: String
    let password: String

    private let authenticationSalt: String
    private let authenticationToken: String
    private let clientName = "navilyrics"
    private let apiVersion = "1.16.1"

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
    }

    // MARK: 认证

    func ping() async throws -> Bool {
        let resp: SubsonicResponse = try await request("ping", params: [:])
        return resp.status == "ok"
    }

    // MARK: 音乐库

    /// 专辑列表（newest / random / alphabetical / recent / frequent / highest）
    func albumList(type: String = "newest", size: Int = 200) async throws -> [SubsonicAlbum] {
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
        let resp: SubsonicResponse = try await request(
            "getPlaylist",
            params: ["id": playlistID]
        )
        return (resp.playlist?.entry ?? []).map(makeSong(from:))
    }

    /// 专辑内歌曲
    func songs(inAlbum albumID: String) async throws -> [SubsonicSong] {
        let resp: SubsonicResponse = try await request(
            "getAlbum",
            params: ["id": albumID]
        )
        let songs = resp.album?.song ?? []
        return songs.map(makeSong(from:))
    }

    /// 歌手详情及其专辑。
    func albums(byArtist artistID: String) async throws -> [SubsonicAlbum] {
        let resp: SubsonicResponse = try await request(
            "getArtist",
            params: ["id": artistID]
        )
        return (resp.artist?.album ?? []).map(makeAlbum(from:))
    }

    /// 搜索
    func search(query: String) async throws -> SubsonicSearchResults {
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
        let resp: SubsonicResponse = try await request(
            "getStarred2",
            params: [:]
        )
        return (resp.starred2?.song ?? []).map(makeSong(from:))
    }

    /// 在 Navidrome 中添加或取消歌曲收藏。
    func setFavorite(songID: String, isFavorite: Bool) async throws {
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
        params: [String: String]
    ) async throws -> SubsonicResponse {
        guard var comps = URLComponents(
            url: baseURL.appendingPathComponent("rest/\(method).view"),
            resolvingAgainstBaseURL: false
        ) else {
            throw SubsonicError.invalidURL
        }
        var items = makeAuthItems()
        items.append(contentsOf: params.map { URLQueryItem(name: $0.key, value: $0.value) })
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
