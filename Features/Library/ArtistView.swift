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
                                ),
                                client: client
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

struct ArtistLibraryView: View {
    let client: SubsonicClient

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artists: [SubsonicArtist] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadRevision = 0

    private var groupedArtists: [ArtistGroup] {
        let grouped = Dictionary(
            grouping: artists.sorted {
                $0.name.localizedStandardCompare($1.name)
                    == .orderedAscending
            },
            by: sectionKey(for:)
        )
        return grouped.keys.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }.compactMap { key in
            guard let artists = grouped[key] else { return nil }
            return ArtistGroup(key: key, artists: artists)
        }
    }

    var body: some View {
        Group {
            if isLoading && artists.isEmpty {
                ProgressView("正在载入艺术家…")
            } else if let errorMessage, artists.isEmpty {
                ContentUnavailableView {
                    Label("无法载入艺术家", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { loadRevision &+= 1 }
                }
            } else if artists.isEmpty {
                ContentUnavailableView(
                    "没有找到艺术家",
                    systemImage: "person.2",
                    description: Text("音乐库中暂时没有可浏览的艺术家")
                )
            } else {
                artistDirectory
            }
        }
        .navigationTitle("全部艺术家")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadRevision) { await load() }
        .refreshable { await load() }
    }

    private var artistDirectory: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                letterPicker { key in
                    withAnimation(
                        reduceMotion ? nil : .easeInOut(duration: 0.2)
                    ) {
                        proxy.scrollTo(key, anchor: .top)
                    }
                }

                ScrollView {
                    LazyVStack(
                        alignment: .leading,
                        spacing: 0,
                        pinnedViews: [.sectionHeaders]
                    ) {
                        ForEach(groupedArtists) { group in
                            Section {
                                ForEach(group.artists) { artist in
                                    NavigationLink(value: artist) {
                                        ArtistRow(artist: artist)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 7)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                Text(group.key)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(.regularMaterial)
                                    .id(group.id)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func letterPicker(
        onSelect: @escaping (String) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(groupedArtists) { group in
                    Button(group.key) {
                        onSelect(group.id)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(minWidth: 30, minHeight: 30)
                    .background(.quaternary, in: Capsule())
                    .accessibilityLabel("跳转到\(group.key)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let loadedArtists = try await client.artists()
            try Task.checkCancellation()
            artists = loadedArtists
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "加载失败：\(error.localizedDescription)"
        }
        isLoading = false
    }

    private func sectionKey(for artist: SubsonicArtist) -> String {
        guard let first = artist.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first else {
            return "#"
        }
        let key = String(first).uppercased()
        return key.rangeOfCharacter(from: .letters) == nil ? "#" : key
    }
}

private struct ArtistGroup: Identifiable {
    let key: String
    let artists: [SubsonicArtist]

    var id: String { key }
}
