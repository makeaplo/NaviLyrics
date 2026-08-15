import SwiftUI

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(NavidromeSession.self) private var session
    @Environment(PlayerStore.self) private var player
    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.playerPresentation) private var playerPresentation
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var searchResults = SubsonicSearchResults()
    @State private var isSearching = false
    @State private var searchErrorMessage: String?
    @State private var activeSearchQuery = ""
    @State private var searchRevision = 0
    @State private var searchScope: LibrarySearchScope = .all

    var body: some View {
        Group {
            if let client = session.client {
                libraryContent(client: client)
                    .task(id: searchRequest) {
                        await searchIfNeeded(using: client)
                    }
                    .task(id: favorites.activeServerURL) {
                        guard !favorites.activeServerURL.isEmpty else {
                            return
                        }
                        await favorites.refresh(using: client)
                    }
            } else {
                ProgressView("正在连接音乐库…")
            }
        }
        .navigationTitle(
            normalizedSearchQuery.isEmpty ? "音乐库" : "搜索"
        )
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索歌曲、歌手或专辑"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = session.libraryErrorMessage {
                libraryErrorBanner(message: message)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    @ViewBuilder
    private func libraryContent(client: SubsonicClient) -> some View {
        if normalizedSearchQuery.isEmpty {
            libraryHome(client: client)
        } else {
            searchResultList(client: client)
        }
    }

    private func libraryHome(client: SubsonicClient) -> some View {
        return List {
            if session.albums.isEmpty {
                ContentUnavailableView(
                    "音乐库为空",
                    systemImage: "music.note.list",
                    description: Text("Navidrome 尚未返回任何专辑")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(
                        Array(session.albums.prefix(12).enumerated()),
                        id: \.offset
                    ) { _, album in
                        NavigationLink(value: album) {
                            AlbumRow(
                                album: album,
                                artworkURL: client.coverURL(
                                    coverArt: album.coverArt
                                ),
                                client: client
                            )
                        }
                    }
                } header: {
                    HStack {
                        Text("最近添加")
                        Spacer()
                        NavigationLink(value: LibraryRoute.albums) {
                            Text("查看全部")
                                .font(.caption.weight(.semibold))
                        }
                        .accessibilityLabel("查看全部专辑")
                    }
                }
            }

            libraryBrowseSection
        }
        .overlay {
            if session.isRefreshing {
                ProgressView("正在刷新")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .refreshable {
            await session.refreshLibrary()
            await favorites.refresh(using: client)
        }
    }

    private var libraryBrowseSection: some View {
        Section("浏览音乐库") {
            NavigationLink(value: LibraryRoute.albums) {
                Label("全部专辑", systemImage: "square.stack")
            }
            NavigationLink(value: LibraryRoute.artists) {
                Label("全部艺术家", systemImage: "person.2")
            }
        }
    }

    private func searchResultList(client: SubsonicClient) -> some View {
        List {
            searchScopeBar

            if isSearching && !hasVisibleSearchResults {
                HStack {
                    Spacer()
                    ProgressView("正在搜索…")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if let searchErrorMessage {
                ContentUnavailableView {
                    Label("搜索失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(searchErrorMessage)
                } actions: {
                    Button("重试") {
                        searchRevision &+= 1
                    }
                }
                .listRowBackground(Color.clear)
            } else if !hasVisibleSearchResults {
                ContentUnavailableView {
                    Label(
                        "没有\(searchScope.title)结果",
                        systemImage: "magnifyingglass"
                    )
                } description: {
                    Text("可以切换类型或修改搜索词")
                }
                .listRowBackground(Color.clear)
            } else {
                searchSections(client: client)
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: isSearching
        )
    }

    private var searchScopeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibrarySearchScope.allCases) { scope in
                    Button {
                        withAnimation(
                            reduceMotion ? nil : .easeInOut(duration: 0.2)
                        ) {
                            searchScope = scope
                        }
                    } label: {
                        Text("\(scope.title) \(scopeCount(for: scope))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                searchScope == scope
                                    ? Color.white
                                    : Color.primary
                            )
                            .padding(.horizontal, 12)
                            .frame(minHeight: 32)
                            .background(
                                searchScope == scope
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "筛选\(scope.title)，\(scopeCount(for: scope))项"
                    )
                    .accessibilityAddTraits(
                        searchScope == scope ? .isSelected : []
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func searchSections(client: SubsonicClient) -> some View {
        if searchScope.showsSongs, !searchResults.songs.isEmpty {
            Section("歌曲 · \(searchResults.songs.count)") {
                ForEach(searchResults.songs.indices, id: \.self) { index in
                    let song = searchResults.songs[index]
                    LibrarySongRow(
                        song: song,
                        artworkURL: client.coverURL(
                            coverArt: song.coverArt,
                            size: 180
                        ),
                        isFavorite: favorites.isFavorite(
                            songID: song.id,
                            fallback: song.isStarred
                        ),
                        isFavoriteUpdating: favorites.isUpdating(
                            songID: song.id
                        ),
                        client: client,
                        onPlay: {
                            playSearchResult(at: index, using: client)
                        },
                        onToggleFavorite: {
                            toggleFavorite(song, using: client)
                        }
                    )
                }
            }
        }

        if searchScope.showsAlbums, !searchResults.albums.isEmpty {
            Section("专辑 · \(searchResults.albums.count)") {
                ForEach(searchResults.albums) { album in
                    NavigationLink(value: album) {
                        AlbumRow(
                            album: album,
                            artworkURL: client.coverURL(
                                coverArt: album.coverArt,
                                size: 180
                            ),
                            client: client
                        )
                    }
                }
            }
        }

        if searchScope.showsArtists, !searchResults.artists.isEmpty {
            Section("艺术家 · \(searchResults.artists.count)") {
                ForEach(searchResults.artists) { artist in
                    NavigationLink(value: artist) {
                        ArtistRow(artist: artist)
                    }
                }
            }
        }

        if searchScope.showsPlaylists, !searchResults.playlists.isEmpty {
            Section("歌单 · \(searchResults.playlists.count)") {
                ForEach(searchResults.playlists) { playlist in
                    NavigationLink(value: playlist) {
                        PlaylistRow(
                            playlist: playlist,
                            artworkURL: client.coverURL(
                                coverArt: playlist.coverArt,
                                size: 180
                            )
                        )
                    }
                }
            }
        }
    }

    private func libraryErrorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("重试") {
                Task { await session.refreshLibrary() }
            }
            .font(.footnote.weight(.semibold))
            Button {
                session.dismissLibraryError()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("关闭错误提示")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var normalizedSearchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchRequest: LibrarySearchRequest {
        LibrarySearchRequest(
            query: normalizedSearchQuery,
            revision: searchRevision
        )
    }

    private var hasVisibleSearchResults: Bool {
        scopeCount(for: searchScope) > 0
    }

    private func scopeCount(for scope: LibrarySearchScope) -> Int {
        switch scope {
        case .all:
            searchResults.songs.count
                + searchResults.albums.count
                + searchResults.artists.count
                + searchResults.playlists.count
        case .songs:
            searchResults.songs.count
        case .albums:
            searchResults.albums.count
        case .artists:
            searchResults.artists.count
        case .playlists:
            searchResults.playlists.count
        }
    }

    private func searchIfNeeded(using client: SubsonicClient) async {
        let query = normalizedSearchQuery
        guard !query.isEmpty else {
            activeSearchQuery = ""
            searchResults = SubsonicSearchResults()
            searchErrorMessage = nil
            isSearching = false
            searchScope = .all
            return
        }

        activeSearchQuery = query
        isSearching = true
        searchErrorMessage = nil
        do {
            try await Task.sleep(for: .milliseconds(300))
            let results = try await client.search(query: query)
            try Task.checkCancellation()
            guard activeSearchQuery == query else { return }
            searchResults = results
        } catch is CancellationError {
            return
        } catch {
            guard activeSearchQuery == query else { return }
            searchResults = SubsonicSearchResults()
            searchErrorMessage = error.localizedDescription
        }
        if activeSearchQuery == query {
            isSearching = false
        }
    }

    private func playSearchResult(
        at index: Int,
        using client: SubsonicClient
    ) {
        guard searchResults.songs.indices.contains(index) else { return }
        let queue = searchResults.songs.map { song in
            NowPlayingSong(
                id: song.id,
                title: song.title,
                artist: song.artist,
                album: song.album,
                duration: song.duration,
                streamURL: client.streamURL(songID: song.id),
                artworkURL: client.coverURL(
                    coverArt: song.coverArt,
                    size: 900
                ),
                artworkIdentifier: song.coverArt
            )
        }
        player.load(queue: queue, startingAt: index)
        playerPresentation.wrappedValue = true
    }

    private func toggleFavorite(
        _ song: SubsonicSong,
        using client: SubsonicClient
    ) {
        Task {
            _ = await favorites.toggle(song: song, using: client)
        }
    }
}

private enum LibrarySearchScope: String, CaseIterable, Hashable, Identifiable {
    case all
    case songs
    case albums
    case artists
    case playlists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "全部"
        case .songs:
            "歌曲"
        case .albums:
            "专辑"
        case .artists:
            "艺术家"
        case .playlists:
            "歌单"
        }
    }

    var showsSongs: Bool { self == .all || self == .songs }
    var showsAlbums: Bool { self == .all || self == .albums }
    var showsArtists: Bool { self == .all || self == .artists }
    var showsPlaylists: Bool { self == .all || self == .playlists }
}

private struct LibrarySearchRequest: Hashable {
    let query: String
    let revision: Int
}

struct AlbumRow: View {
    let album: SubsonicAlbum
    let artworkURL: URL?
    let quickActionClient: SubsonicClient?

    init(
        album: SubsonicAlbum,
        artworkURL: URL?,
        client: SubsonicClient? = nil
    ) {
        self.album = album
        self.artworkURL = artworkURL
        quickActionClient = client
    }

    @ViewBuilder
    var body: some View {
        if let quickActionClient {
            rowContent
                .modifier(
                    AlbumQuickActionsModifier(
                        album: album,
                        client: quickActionClient
                    )
                )
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            LibraryArtwork(url: artworkURL, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(album.title)
                    .font(.body)
                    .lineLimit(1)
                Text(album.artist.isEmpty ? "未知歌手" : album.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开专辑；长按查看更多操作")
    }
}

struct ArtistRow: View {
    let artist: SubsonicArtist

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 27)
                .fill(.quaternary)
                .frame(width: 54, height: 54)
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(artist.name)
                    .font(.body)
                    .lineLimit(1)
                Text("\(artist.albumCount) 张专辑")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开艺术家")
    }
}
