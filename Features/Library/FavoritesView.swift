import SwiftUI

struct FavoritesView: View {
    let client: SubsonicClient
    @Environment(FavoritesStore.self) private var favorites
    @Environment(PlayerStore.self) private var player
    @Environment(\.playerPresentation) private var playerPresentation
    @State private var loadRevision = 0

    var body: some View {
        List {
            if let errorMessage = favorites.errorMessage,
               !favorites.songs.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button("重试") { loadRevision &+= 1 }
                        .font(.footnote.weight(.semibold))
                }
                .listRowBackground(Color.clear)
            }

            if favorites.isLoading && favorites.songs.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("正在载入收藏…")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if let errorMessage = favorites.errorMessage,
                      favorites.songs.isEmpty {
                ContentUnavailableView {
                    Label("无法载入收藏", systemImage: "heart.slash")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { loadRevision &+= 1 }
                }
                .listRowBackground(Color.clear)
            } else if favorites.songs.isEmpty {
                ContentUnavailableView {
                    Label("还没有喜欢的歌曲", systemImage: "heart")
                } description: {
                    Text("在专辑或搜索结果中点按心形按钮即可收藏。")
                }
                .listRowBackground(Color.clear)
            } else {
                Section("\(favorites.songs.count) 首歌曲") {
                    ForEach(favorites.songs.indices, id: \.self) { index in
                        let song = favorites.songs[index]
                        LibrarySongRow(
                            song: song,
                            artworkURL: client.coverURL(
                                coverArt: song.coverArt,
                                size: 180
                            ),
                            isFavorite: true,
                            isFavoriteUpdating: favorites.isUpdating(
                                songID: song.id
                            ),
                            client: client,
                            onPlay: { play(at: index) },
                            onToggleFavorite: { toggleFavorite(song) }
                        )
                    }
                }
            }
        }
        .navigationTitle("我喜欢的歌曲")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadRevision) {
            await favorites.refresh(using: client)
        }
        .refreshable {
            await favorites.refresh(using: client)
        }
    }

    private func play(at index: Int) {
        guard favorites.songs.indices.contains(index) else { return }
        let queue = favorites.songs.map { song in
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

    private func toggleFavorite(_ song: SubsonicSong) {
        Task {
            _ = await favorites.toggle(song: song, using: client)
        }
    }
}
