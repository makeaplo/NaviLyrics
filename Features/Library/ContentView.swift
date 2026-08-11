import SwiftUI

struct ContentView: View {
    @Environment(NavidromeSession.self) private var session
    @Environment(PlayerStore.self) private var player
    @Environment(ListeningHistoryStore.self) private var history
    private let onOpenPlayer: () -> Void
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var searchResults: [SubsonicSong] = []
    @State private var isSearching = false
    @State private var searchErrorMessage: String?
    @State private var activeSearchQuery = ""
    @State private var searchRevision = 0

    init(onOpenPlayer: @escaping () -> Void = {}) {
        self.onOpenPlayer = onOpenPlayer
    }

    var body: some View {
        NavigationStack {
            Group {
                if let client = session.client {
                    libraryContent(client: client)
                        .navigationDestination(
                            for: SubsonicAlbum.self
                        ) { album in
                            AlbumView(client: client, album: album)
                        }
                        .task(id: searchRequest) {
                            await searchIfNeeded(using: client)
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
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
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
        let recentItems = history.recentItems()
        let mostPlayedItems = history.mostPlayedItems()

        return List {
            if player.currentSong != nil {
                continuePlayingSection
            }

            historySection(
                title: "最近播放",
                kind: .recent,
                items: recentItems,
                client: client
            )
            historySection(
                title: "本机常听",
                kind: .mostPlayed,
                items: mostPlayedItems,
                client: client
            )

            if session.albums.isEmpty {
                ContentUnavailableView(
                    "音乐库为空",
                    systemImage: "music.note.list",
                    description: Text("Navidrome 尚未返回任何专辑")
                )
                .listRowBackground(Color.clear)
            } else {
                Section("最近添加 · \(session.albums.count)") {
                    ForEach(
                        Array(session.albums.enumerated()),
                        id: \.offset
                    ) { _, album in
                        NavigationLink(value: album) {
                            AlbumRow(
                                album: album,
                                artworkURL: client.coverURL(
                                    coverArt: album.coverArt
                                )
                            )
                        }
                    }
                }
            }
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
        }
    }

    private var continuePlayingSection: some View {
        Section("继续播放") {
            Button {
                player.play()
                onOpenPlayer()
            } label: {
                HStack(spacing: 12) {
                    LibraryArtwork(
                        url: player.currentSong?.artworkURL,
                        size: 52
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.currentSong?.title ?? "")
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(
                            player.currentSong?.artist.isEmpty == false
                                ? player.currentSong?.artist ?? ""
                                : "未知歌手"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("继续播放")
        }
    }

    @ViewBuilder
    private func historySection(
        title: String,
        kind: ListeningHistoryListKind,
        items: [ListeningHistoryItem],
        client: SubsonicClient
    ) -> some View {
        Section {
            if items.isEmpty {
                Text(kind.emptyMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(items) { item in
                    Button {
                        playHistoryItem(
                            item,
                            from: items,
                            using: client
                        )
                    } label: {
                        ListeningHistoryRow(
                            item: item,
                            artworkURL: client.coverURL(
                                coverArt: item.artworkIdentifier,
                                size: 180
                            ),
                            showsPlayCount: kind == .mostPlayed
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                if !items.isEmpty {
                    NavigationLink {
                        SmartSongListView(kind: kind, client: client)
                    } label: {
                        Text("查看全部")
                            .font(.caption.weight(.semibold))
                    }
                    .accessibilityLabel("查看全部\(title)")
                }
            }
        }
    }

    private func playHistoryItem(
        _ item: ListeningHistoryItem,
        from items: [ListeningHistoryItem],
        using client: SubsonicClient
    ) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        player.load(
            queue: playbackQueue(from: items, using: client),
            startingAt: index
        )
    }

    private func playbackQueue(
        from items: [ListeningHistoryItem],
        using client: SubsonicClient
    ) -> [NowPlayingSong] {
        items.map { item in
            NowPlayingSong(
                id: item.id,
                title: item.title,
                artist: item.artist,
                album: item.album,
                duration: item.duration,
                streamURL: client.streamURL(songID: item.id),
                artworkURL: client.coverURL(
                    coverArt: item.artworkIdentifier,
                    size: 900
                ),
                artworkIdentifier: item.artworkIdentifier
            )
        }
    }

    private func searchResultList(client: SubsonicClient) -> some View {
        List {
            if isSearching && searchResults.isEmpty {
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
            } else if searchResults.isEmpty {
                ContentUnavailableView.search(text: normalizedSearchQuery)
                    .listRowBackground(Color.clear)
            } else {
                Section("歌曲 · \(searchResults.count)") {
                    ForEach(searchResults.indices, id: \.self) { index in
                        let song = searchResults[index]
                        Button {
                            playSearchResult(at: index, using: client)
                        } label: {
                            SearchSongRow(
                                song: song,
                                artworkURL: client.coverURL(
                                    coverArt: song.coverArt,
                                    size: 180
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSearching)
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

    private func searchIfNeeded(using client: SubsonicClient) async {
        let query = normalizedSearchQuery
        guard !query.isEmpty else {
            activeSearchQuery = ""
            searchResults = []
            searchErrorMessage = nil
            isSearching = false
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
            searchResults = []
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
        guard searchResults.indices.contains(index) else { return }
        let queue = searchResults.map { song in
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
    }
}

enum ListeningHistoryListKind: Hashable {
    case recent
    case mostPlayed

    var title: String {
        switch self {
        case .recent:
            "最近播放"
        case .mostPlayed:
            "本机常听"
        }
    }

    var emptyMessage: String {
        switch self {
        case .recent:
            "播放几首歌后，这里会显示最近播放。"
        case .mostPlayed:
            "累计播放后，这里会显示本机常听歌曲。"
        }
    }
}

struct SmartSongListView: View {
    let kind: ListeningHistoryListKind
    let client: SubsonicClient
    @Environment(ListeningHistoryStore.self) private var history
    @Environment(PlayerStore.self) private var player

    private var items: [ListeningHistoryItem] {
        switch kind {
        case .recent:
            history.recentItems(
                limit: ListeningHistoryStore.maximumStoredItems
            )
        case .mostPlayed:
            history.mostPlayedItems(
                limit: ListeningHistoryStore.maximumStoredItems
            )
        }
    }

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView {
                    Label(kind.title, systemImage: "clock.arrow.circlepath")
                } description: {
                    Text(kind.emptyMessage)
                }
                .listRowBackground(Color.clear)
            } else {
                Section("\(items.count) 首歌曲") {
                    ForEach(items) { item in
                        Button {
                            play(item)
                        } label: {
                            ListeningHistoryRow(
                                item: item,
                                artworkURL: client.coverURL(
                                    coverArt: item.artworkIdentifier,
                                    size: 180
                                ),
                                showsPlayCount: kind == .mostPlayed
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func play(_ item: ListeningHistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        let queue = items.map { item in
            NowPlayingSong(
                id: item.id,
                title: item.title,
                artist: item.artist,
                album: item.album,
                duration: item.duration,
                streamURL: client.streamURL(songID: item.id),
                artworkURL: client.coverURL(
                    coverArt: item.artworkIdentifier,
                    size: 900
                ),
                artworkIdentifier: item.artworkIdentifier
            )
        }
        player.load(queue: queue, startingAt: index)
    }
}

private struct ListeningHistoryRow: View {
    let item: ListeningHistoryItem
    let artworkURL: URL?
    let showsPlayCount: Bool

    var body: some View {
        HStack(spacing: 12) {
            LibraryArtwork(url: artworkURL, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(secondaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if showsPlayCount {
                Text("\(item.playCount) 次")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("播放并从此处继续列表")
    }

    private var secondaryText: String {
        [item.artist, item.album]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private struct LibrarySearchRequest: Hashable {
    let query: String
    let revision: Int
}

private struct AlbumRow: View {
    let album: SubsonicAlbum
    let artworkURL: URL?

    var body: some View {
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
    }
}

private struct SearchSongRow: View {
    let song: SubsonicSong
    let artworkURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            LibraryArtwork(url: artworkURL, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(secondaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Self.timeString(song.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("播放并从此处继续搜索结果队列")
    }

    private var secondaryText: String {
        [song.artist, song.album]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private static func timeString(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "--:--" }
        return String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
    }
}

private struct LibraryArtwork: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill()
            case .empty:
                placeholder.overlay { ProgressView().controlSize(.mini) }
            case .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.13))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: size * 0.13)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
    }
}
