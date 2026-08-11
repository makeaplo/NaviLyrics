import SwiftUI

struct PlaylistsView: View {
    let client: SubsonicClient

    @State private var playlists: [SubsonicPlaylist] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadRevision = 0

    var body: some View {
        List {
            if isLoading && playlists.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("正在载入播放列表…")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if let errorMessage, playlists.isEmpty {
                ContentUnavailableView {
                    Label("无法载入播放列表", systemImage: "music.note.list")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { loadRevision &+= 1 }
                }
                .listRowBackground(Color.clear)
            } else if playlists.isEmpty {
                ContentUnavailableView(
                    "还没有播放列表",
                    systemImage: "music.note.list"
                )
                .listRowBackground(Color.clear)
            } else {
                Section("播放列表 · (playlists.count)") {
                    ForEach(playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(
                                playlist: playlist,
                                client: client
                            )
                        } label: {
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
        .navigationTitle("播放列表")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadRevision) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let loadedPlaylists = try await client.playlists()
            try Task.checkCancellation()
            playlists = loadedPlaylists
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "加载失败：(error.localizedDescription)"
        }
        isLoading = false
    }
}

struct PlaylistDetailView: View {
    let playlist: SubsonicPlaylist
    let client: SubsonicClient

    @Environment(PlayerStore.self) private var player
    @Environment(FavoritesStore.self) private var favorites
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
                    Label("无法载入播放列表", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { loadRevision &+= 1 }
                }
                .listRowBackground(Color.clear)
            } else if songs.isEmpty {
                ContentUnavailableView(
                    "播放列表为空",
                    systemImage: "music.note"
                )
                .listRowBackground(Color.clear)
            } else {
                Section("(songs.count) 首歌曲") {
                    ForEach(songs.indices, id: \.self) { index in
                        let song = songs[index]
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
                            isFavoriteUpdating: favorites.isUpdating(
                                songID: song.id
                            ),
                            onPlay: { play(at: index) },
                            onToggleFavorite: {
                                toggleFavorite(song)
                            }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadRevision) { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                LibraryArtwork(
                    url: client.coverURL(
                        coverArt: playlist.coverArt,
                        size: 400
                    ),
                    size: 92
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(playlist.name)
                        .font(.title3.bold())
                        .lineLimit(3)
                    Text("\(max(songs.count, playlist.songCount)) 首歌曲")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let loadedSongs = try await client.songs(inPlaylist: playlist.id)
            try Task.checkCancellation()
            songs = loadedSongs
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "加载失败：(error.localizedDescription)"
        }
        isLoading = false
    }

    private func play(at index: Int) {
        guard songs.indices.contains(index) else { return }
        player.load(queue: playbackQueue(from: songs), startingAt: index)
    }

    private func playAll() {
        guard !songs.isEmpty else { return }
        player.load(queue: playbackQueue(from: songs), startingAt: 0)
    }

    private func shufflePlay() {
        let shuffledSongs = songs.shuffled()
        guard !shuffledSongs.isEmpty else { return }
        player.load(queue: playbackQueue(from: shuffledSongs), startingAt: 0)
    }

    private func playbackQueue(
        from songs: [SubsonicSong]
    ) -> [NowPlayingSong] {
        songs.map { song in
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
    }

    private func toggleFavorite(_ song: SubsonicSong) {
        Task {
            _ = await favorites.toggle(song: song, using: client)
        }
    }

    private func songMetadata(_ song: SubsonicSong) -> String {
        var values: [String] = []
        if !song.artist.isEmpty {
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
}

private struct PlaylistRow: View {
    let playlist: SubsonicPlaylist
    let artworkURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            LibraryArtwork(url: artworkURL, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.body)
                    .lineLimit(1)
                Text("\(playlist.songCount) 首歌曲")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
