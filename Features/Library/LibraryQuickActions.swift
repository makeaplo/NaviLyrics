import SwiftUI

struct SongQuickActionsModifier: ViewModifier {
    let song: SubsonicSong
    let client: SubsonicClient
    let isFavorite: Bool

    @Environment(PlayerStore.self) private var player
    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.playerPresentation) private var playerPresentation
    @State private var showPlaylistPicker = false
    @State private var playlistSongs: [SubsonicSong] = []

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    player.load(song: client.makeNowPlayingSong(from: song))
                    playerPresentation.wrappedValue = true
                } label: {
                    Label("立即播放", systemImage: "play.fill")
                }

                Button {
                    player.enqueue(
                        [client.makeNowPlayingSong(from: song)],
                        afterCurrent: true
                    )
                } label: {
                    Label("下一首播放", systemImage: "text.insert")
                }

                Button {
                    player.enqueue(
                        [client.makeNowPlayingSong(from: song)],
                        afterCurrent: false
                    )
                } label: {
                    Label("加入播放队列", systemImage: "text.append")
                }

                Button {
                    playlistSongs = [song]
                    showPlaylistPicker = true
                } label: {
                    Label("加入歌单", systemImage: "music.note.list")
                }

                Divider()

                Button {
                    Task {
                        _ = await favorites.toggle(song: song, using: client)
                    }
                } label: {
                    Label(
                        isFavorite ? "取消收藏" : "收藏歌曲",
                        systemImage: isFavorite ? "heart.slash" : "heart"
                    )
                }
            }
            .sheet(isPresented: $showPlaylistPicker) {
                PlaylistSelectionView(
                    client: client,
                    songs: playlistSongs
                )
            }
    }
}

struct AlbumQuickActionsModifier: ViewModifier {
    let album: SubsonicAlbum
    let client: SubsonicClient

    @Environment(PlayerStore.self) private var player
    @Environment(\.playerPresentation) private var playerPresentation
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showPlaylistPicker = false
    @State private var playlistSongs: [SubsonicSong] = []

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    Task { await perform(.play) }
                } label: {
                    Label("播放专辑", systemImage: "play.fill")
                }

                Button {
                    Task { await perform(.shuffle) }
                } label: {
                    Label("随机播放", systemImage: "shuffle")
                }

                Button {
                    Task { await perform(.playNext) }
                } label: {
                    Label("下一首播放", systemImage: "text.insert")
                }

                Button {
                    Task { await perform(.enqueue) }
                } label: {
                    Label("加入播放队列", systemImage: "text.append")
                }

                Button {
                    Task { await perform(.playlist) }
                } label: {
                    Label("加入歌单", systemImage: "music.note.list")
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                }
            }
            .sheet(isPresented: $showPlaylistPicker) {
                PlaylistSelectionView(
                    client: client,
                    songs: playlistSongs
                )
            }
            .alert(
                "专辑操作失败",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { isPresented in
                        if !isPresented { errorMessage = nil }
                    }
                )
            ) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "请稍后重试。")
            }
    }

    private func perform(_ action: AlbumQuickAction) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let songs = try await client.songs(inAlbum: album.id)
            try Task.checkCancellation()
            guard !songs.isEmpty else {
                errorMessage = "这个专辑中没有可播放的歌曲。"
                return
            }

            switch action {
            case .play:
                player.load(queue: playbackQueue(from: songs), startingAt: 0)
                playerPresentation.wrappedValue = true
            case .shuffle:
                player.load(
                    queue: playbackQueue(from: songs.shuffled()),
                    startingAt: 0
                )
                playerPresentation.wrappedValue = true
            case .playNext:
                player.enqueue(
                    playbackQueue(from: songs),
                    afterCurrent: true
                )
            case .enqueue:
                player.enqueue(
                    playbackQueue(from: songs),
                    afterCurrent: false
                )
            case .playlist:
                playlistSongs = songs
                showPlaylistPicker = true
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "加载专辑失败：\(error.localizedDescription)"
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
}

private enum AlbumQuickAction {
    case play
    case shuffle
    case playNext
    case enqueue
    case playlist
}

struct PlaylistSelectionView: View {
    let client: SubsonicClient
    let songs: [SubsonicSong]

    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [SubsonicPlaylist] = []
    @State private var isLoading = true
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("正在载入歌单…")
                } else if playlists.isEmpty {
                    ContentUnavailableView(
                        "还没有歌单",
                        systemImage: "music.note.list",
                        description: Text("请先创建一个歌单")
                    )
                } else {
                    List(playlists) { playlist in
                        Button {
                            Task { await add(songs, to: playlist) }
                        } label: {
                            PlaylistRow(
                                playlist: playlist,
                                artworkURL: client.coverURL(
                                    coverArt: playlist.coverArt,
                                    size: 180
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isAdding)
                    }
                }
            }
            .navigationTitle("加入歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .task { await load() }
            .alert(
                "加入歌单失败",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { isPresented in
                        if !isPresented { errorMessage = nil }
                    }
                )
            ) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "请稍后重试。")
            }
            .overlay {
                if isAdding {
                    ProgressView()
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        do {
            playlists = try await client.playlists()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "加载歌单失败：\(error.localizedDescription)"
        }
        isLoading = false
    }

    private func add(
        _ songs: [SubsonicSong],
        to playlist: SubsonicPlaylist
    ) async {
        guard !songs.isEmpty, !isAdding else { return }
        isAdding = true
        defer { isAdding = false }
        do {
            try await client.updatePlaylist(
                id: playlist.id,
                songIDsToAdd: songs.map(\.id)
            )
            try Task.checkCancellation()
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "加入歌单失败：\(error.localizedDescription)"
        }
    }
}
