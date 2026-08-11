import SwiftUI

struct ArtistView: View {
    let client: SubsonicClient
    let artist: SubsonicArtist

    @State private var albums: [SubsonicAlbum] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadRevision = 0

    var body: some View {
        List {
            if isLoading && albums.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("正在载入专辑…")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if let errorMessage, albums.isEmpty {
                ContentUnavailableView {
                    Label("无法载入艺人", systemImage: "person.fill")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { loadRevision &+= 1 }
                }
                .listRowBackground(Color.clear)
            } else if albums.isEmpty {
                ContentUnavailableView(
                    "没有找到专辑",
                    systemImage: "square.stack"
                )
                .listRowBackground(Color.clear)
            } else {
                Section("专辑 · \(albums.count)") {
                    ForEach(albums) { album in
                        NavigationLink(value: album) {
                            AlbumRow(
                                album: album,
                                artworkURL: client.coverURL(
                                    coverArt: album.coverArt,
                                    size: 180
                                )
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadRevision) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let loadedAlbums = try await client.albums(byArtist: artist.id)
            try Task.checkCancellation()
            albums = loadedAlbums
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "加载失败：\(error.localizedDescription)"
        }
        isLoading = false
    }
}
