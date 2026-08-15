import SwiftUI

struct AlbumView: View {
    let client: SubsonicClient
    let album: SubsonicAlbum
    @Environment(PlayerStore.self) private var player
    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.playerPresentation) private var playerPresentation

    @State private var songs: [SubsonicSong] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadRevision = 0

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if isLoading && songs.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("正在载入曲目…")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if let errorMessage, songs.isEmpty {
                ContentUnavailableView {
                    Label("无法载入专辑", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { loadRevision &+= 1 }
                }
                .listRowBackground(Color.clear)
            } else if songs.isEmpty {
                ContentUnavailableView(
                    "专辑内没有歌曲",
                    systemImage: "music.note"
                )
                .listRowBackground(Color.clear)
            } else {
                Section("\(songs.count) 首歌曲") {
                    ForEach(songs.indices, id: \.self) { index in
                        songRow(songs[index], at: index)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadRevision) { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(spacing: 18) {
            HStack(spacing: 16) {
                LibraryArtwork(
                    url: client.coverURL(
                        coverArt: album.coverArt,
                        size: 400
                    ),
                    size: 108
                )
                .shadow(color: .black.opacity(0.14), radius: 12, y: 6)

                VStack(alignment: .leading, spacing: 6) {
                    Text(album.title)
                        .font(.title3.bold())
                        .lineLimit(3)
                    Text(album.artist.isEmpty ? "未知歌手" : album.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let year = album.year {
                        Text(String(year))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                Button {
                    playAll()
                } label: {
                    Label("播放", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(songs.isEmpty)

                Button {
                    shufflePlay()
                } label: {
                    Label("随机播放", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(songs.isEmpty)
            }
        }
        .padding(.vertical, 8)
    }

    private func songRow(
        _ song: SubsonicSong,
        at index: Int
    ) -> some View {
        LibrarySongRow(
            song: song,
            leadingLabel: player.currentSong?.id == song.id
                ? nil
                : "\(index + 1)",
            leadingSymbol: player.currentSong?.id == song.id
                ? "speaker.wave.2.fill"
                : nil,
            metadata: songMetadata(song),
            isFavorite: favorites.isFavorite(
                songID: song.id,
                fallback: song.isStarred
            ),
            isFavoriteUpdating: favorites.isUpdating(songID: song.id),
            client: client,
            onPlay: { play(song, at: index) },
            onToggleFavorite: { toggleFavorite(song) }
        )
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let loadedSongs = try await client.songs(inAlbum: album.id)
            try Task.checkCancellation()
            songs = loadedSongs
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "加载失败：\(error.localizedDescription)"
        }
        isLoading = false
    }

    private func play(_ song: SubsonicSong, at index: Int) {
        guard songs.indices.contains(index) else { return }
        player.load(queue: playbackQueue(from: songs), startingAt: index)
        playerPresentation.wrappedValue = true
    }

    private func playAll() {
        guard !songs.isEmpty else { return }
        player.load(queue: playbackQueue(from: songs), startingAt: 0)
        playerPresentation.wrappedValue = true
    }

    private func shufflePlay() {
        let shuffledSongs = songs.shuffled()
        guard !shuffledSongs.isEmpty else { return }
        player.load(
            queue: playbackQueue(from: shuffledSongs),
            startingAt: 0
        )
        playerPresentation.wrappedValue = true
    }

    private func toggleFavorite(_ song: SubsonicSong) {
        Task {
            _ = await favorites.toggle(song: song, using: client)
        }
    }

    private func playbackQueue(
        from songs: [SubsonicSong]
    ) -> [NowPlayingSong] {
        songs.map { song in
            let artworkIdentifier = song.coverArt ?? album.coverArt
            return NowPlayingSong(
                id: song.id,
                title: song.title,
                artist: song.artist,
                album: song.album,
                duration: song.duration,
                streamURL: client.streamURL(songID: song.id),
                artworkURL: client.coverURL(
                    coverArt: artworkIdentifier,
                    size: 900
                ),
                artworkIdentifier: artworkIdentifier
            )
        }
    }

    private func songMetadata(_ song: SubsonicSong) -> String {
        var values: [String] = []
        if !song.artist.isEmpty, song.artist != album.artist {
            values.append(song.artist)
        }
        if let suffix = song.suffix, !suffix.isEmpty {
            values.append(suffix.uppercased())
        }
        if let bitRate = song.bitRate, bitRate > 0 {
            values.append("\(bitRate) kbps")
        }
        return values.isEmpty ? "音频" : values.joined(separator: " · ")
    }

    private func timeString(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "--:--" }
        return String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
    }
}

enum AlbumLibrarySortOption: String, CaseIterable, Hashable, Identifiable {
    case recentlyAdded
    case title
    case artist
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyAdded:
            "最近添加"
        case .title:
            "专辑名称"
        case .artist:
            "艺术家"
        case .year:
            "发行年份"
        }
    }
}

enum AlbumLibraryLayout: String {
    case grid
    case list
}

struct AlbumLibraryView: View {
    let client: SubsonicClient

    @Environment(NavidromeSession.self) private var session
    @AppStorage("library.albumSort") private var sortRawValue =
        AlbumLibrarySortOption.recentlyAdded.rawValue
    @AppStorage("library.albumLayout") private var layoutRawValue =
        AlbumLibraryLayout.grid.rawValue

    private var sortOption: AlbumLibrarySortOption {
        AlbumLibrarySortOption(rawValue: sortRawValue) ?? .recentlyAdded
    }

    private var layout: AlbumLibraryLayout {
        AlbumLibraryLayout(rawValue: layoutRawValue) ?? .grid
    }

    private var sortedAlbums: [SubsonicAlbum] {
        switch sortOption {
        case .recentlyAdded:
            return session.albums
        case .title:
            return session.albums.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .artist:
            return session.albums.sorted {
                let artistComparison = $0.artist.localizedStandardCompare($1.artist)
                if artistComparison == .orderedSame {
                    return $0.title.localizedStandardCompare($1.title)
                        == .orderedAscending
                }
                return artistComparison == .orderedAscending
            }
        case .year:
            return session.albums.sorted {
                switch ($0.year, $1.year) {
                case let (left?, right?) where left != right:
                    return left > right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return $0.title.localizedStandardCompare($1.title)
                        == .orderedAscending
                }
            }
        }
    }

    var body: some View {
        Group {
            if sortedAlbums.isEmpty {
                ContentUnavailableView(
                    "没有专辑",
                    systemImage: "square.stack",
                    description: Text("音乐库中暂时没有可浏览的专辑")
                )
            } else if layout == .grid {
                gridContent
            } else {
                listContent
            }
        }
        .navigationTitle("全部专辑")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                sortMenu
                Button {
                    layoutRawValue = layout == .grid
                        ? AlbumLibraryLayout.list.rawValue
                        : AlbumLibraryLayout.grid.rawValue
                } label: {
                    Image(
                        systemName: layout == .grid
                            ? "list.bullet"
                            : "square.grid.2x2"
                    )
                }
                .accessibilityLabel(
                    layout == .grid ? "切换为列表视图" : "切换为网格视图"
                )
            }
        }
        .refreshable {
            await session.refreshLibrary()
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("排序方式", selection: sortBinding) {
                ForEach(AlbumLibrarySortOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("专辑排序")
    }

    private var sortBinding: Binding<AlbumLibrarySortOption> {
        Binding(
            get: { sortOption },
            set: { sortRawValue = $0.rawValue }
        )
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 148), spacing: 16)
                ],
                spacing: 22
            ) {
                ForEach(sortedAlbums) { album in
                    NavigationLink(value: album) {
                        AlbumGridCard(
                            album: album,
                            artworkURL: client.coverURL(
                                coverArt: album.coverArt,
                                size: 400
                            )
                        )
                        .modifier(
                            AlbumQuickActionsModifier(
                                album: album,
                                client: client
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
    }

    private var listContent: some View {
        List(sortedAlbums) { album in
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
        .listStyle(.insetGrouped)
    }
}

private struct AlbumGridCard: View {
    let album: SubsonicAlbum
    let artworkURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LibraryArtwork(url: artworkURL, size: 148)
                .frame(maxWidth: .infinity)

            Text(album.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(album.artist.isEmpty ? "未知艺术家" : album.artist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开专辑")
    }
}
