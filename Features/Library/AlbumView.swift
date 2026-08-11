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
