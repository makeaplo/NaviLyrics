import SwiftUI

struct PlaylistsView: View {
    let client: SubsonicClient

    @State private var playlists: [SubsonicPlaylist] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadRevision = 0
    @State private var showCreatePlaylist = false
    @State private var editingPlaylist: SubsonicPlaylist?
    @State private var playlistToDelete: SubsonicPlaylist?
    @State private var operationErrorMessage: String?

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
                Section("播放列表 · \(playlists.count)") {
                    ForEach(playlists) { playlist in
                        NavigationLink(value: playlist) {
                            PlaylistRow(
                                playlist: playlist,
                                artworkURL: client.coverURL(
                                    coverArt: playlist.coverArt,
                                    size: 180
                                )
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                playlistToDelete = playlist
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                editingPlaylist = playlist
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
        }
        .navigationTitle("播放列表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreatePlaylist = true
                } label: {
                    Label("新建播放列表", systemImage: "plus")
                }
            }
        }
        .task(id: loadRevision) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showCreatePlaylist) {
            PlaylistEditorView(client: client) {
                loadRevision &+= 1
            }
        }
        .sheet(item: $editingPlaylist) { playlist in
            PlaylistEditorView(client: client, playlist: playlist) {
                loadRevision &+= 1
            }
        }
        .alert(
            "删除播放列表？",
            isPresented: Binding(
                get: { playlistToDelete != nil },
                set: { isPresented in
                    if !isPresented { playlistToDelete = nil }
                }
            )
        ) {
            Button("删除", role: .destructive) {
                guard let playlist = playlistToDelete else { return }
                playlistToDelete = nil
                Task { await delete(playlist) }
            }
            Button("取消", role: .cancel) {
                playlistToDelete = nil
            }
        } message: {
            Text("删除后无法在 NaviLyrics 中恢复此播放列表。")
        }
        .alert(
            "播放列表操作失败",
            isPresented: Binding(
                get: { operationErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { operationErrorMessage = nil }
                }
            )
        ) {
            Button("好", role: .cancel) {
                operationErrorMessage = nil
            }
        } message: {
            Text(operationErrorMessage ?? "请稍后重试。")
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loadedPlaylists = try await client.playlists()
            try Task.checkCancellation()
            playlists = loadedPlaylists
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "加载失败：\(error.localizedDescription)"
        }
    }

    private func delete(_ playlist: SubsonicPlaylist) async {
        do {
            try await client.deletePlaylist(id: playlist.id)
            try Task.checkCancellation()
            loadRevision &+= 1
        } catch is CancellationError {
            return
        } catch {
            operationErrorMessage = "删除失败：\(error.localizedDescription)"
        }
    }
}

struct PlaylistDetailView: View {
    let playlist: SubsonicPlaylist
    let client: SubsonicClient

    @Environment(PlayerStore.self) private var player
    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.playerPresentation) private var playerPresentation
    @State private var songs: [SubsonicSong] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadRevision = 0
    @State private var showSongPicker = false
    @State private var operationErrorMessage: String?
    @State private var updatingSongIndex: Int?

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
                Section("\(songs.count) 首歌曲") {
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await removeSong(at: index) }
                            } label: {
                                if updatingSongIndex == index {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Label("移除", systemImage: "minus.circle")
                                }
                            }
                            .disabled(updatingSongIndex != nil)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSongPicker = true
                } label: {
                    Label("添加歌曲", systemImage: "plus")
                }
                .disabled(isLoading)
            }
        }
        .task(id: loadRevision) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showSongPicker) {
            PlaylistSongPickerView(
                client: client,
                playlistID: playlist.id,
                existingSongIDs: Set(songs.map(\.id))
            ) {
                loadRevision &+= 1
            }
        }
        .alert(
            "播放列表操作失败",
            isPresented: Binding(
                get: { operationErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { operationErrorMessage = nil }
                }
            )
        ) {
            Button("好", role: .cancel) {
                operationErrorMessage = nil
            }
        } message: {
            Text(operationErrorMessage ?? "请稍后重试。")
        }
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
                    Text("\(displayedSongCount) 首歌曲")
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
        defer { isLoading = false }
        do {
            let loadedSongs = try await client.songs(inPlaylist: playlist.id)
            try Task.checkCancellation()
            songs = loadedSongs
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "加载失败：\(error.localizedDescription)"
        }
    }

    private var displayedSongCount: Int {
        isLoading ? max(songs.count, playlist.songCount) : songs.count
    }

    private func removeSong(at index: Int) async {
        guard songs.indices.contains(index), updatingSongIndex == nil else {
            return
        }
        updatingSongIndex = index
        defer { updatingSongIndex = nil }
        do {
            try await client.updatePlaylist(
                id: playlist.id,
                songIndicesToRemove: [index]
            )
            try Task.checkCancellation()
            loadRevision &+= 1
        } catch is CancellationError {
            return
        } catch {
            operationErrorMessage = "移除失败：\(error.localizedDescription)"
        }
    }

    private func play(at index: Int) {
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
        player.load(queue: playbackQueue(from: shuffledSongs), startingAt: 0)
        playerPresentation.wrappedValue = true
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

struct PlaylistEditorView: View {
    let client: SubsonicClient
    let playlist: SubsonicPlaylist?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        client: SubsonicClient,
        playlist: SubsonicPlaylist? = nil,
        onSaved: @escaping () -> Void
    ) {
        self.client = client
        self.playlist = playlist
        self.onSaved = onSaved
        _name = State(initialValue: playlist?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("播放列表名称", text: $name)
                        .textInputAutocapitalization(.sentences)
                } footer: {
                    Text("名称会同步保存到 Navidrome。")
                }
            }
            .navigationTitle(playlist == nil ? "新建播放列表" : "重命名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("保存")
                        }
                    }
                    .disabled(trimmedName.isEmpty || isSaving)
                }
            }
            .alert(
                "保存失败",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { isPresented in
                        if !isPresented { errorMessage = nil }
                    }
                )
            ) {
                Button("好", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "请稍后重试。")
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        guard !trimmedName.isEmpty, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            if let playlist {
                try await client.updatePlaylist(
                    id: playlist.id,
                    name: trimmedName
                )
            } else {
                try await client.createPlaylist(name: trimmedName)
            }
            try Task.checkCancellation()
            onSaved()
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }
}

struct PlaylistSongPickerView: View {
    let client: SubsonicClient
    let playlistID: String
    let existingSongIDs: Set<String>
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var results = SubsonicSearchResults()
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var activeQuery = ""
    @State private var searchRevision = 0
    @State private var addingSongIDs: Set<String> = []
    @State private var addedSongIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                let songs = results.songs.filter {
                    !existingSongIDs.contains($0.id)
                        && !addedSongIDs.contains($0.id)
                }

                if isSearching && results.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("正在搜索…")
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("搜索失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("重试") { searchRevision &+= 1 }
                    }
                    .listRowBackground(Color.clear)
                } else if normalizedQuery.isEmpty {
                    ContentUnavailableView(
                        "搜索歌曲",
                        systemImage: "magnifyingglass",
                        description: Text("搜索后选择歌曲加入此播放列表。")
                    )
                    .listRowBackground(Color.clear)
                } else if songs.isEmpty {
                    ContentUnavailableView.search(text: normalizedQuery)
                        .listRowBackground(Color.clear)
                } else {
                    Section("歌曲 · \(songs.count)") {
                        ForEach(songs) { song in
                            Button {
                                add(song)
                            } label: {
                                SongPickerRow(
                                    song: song,
                                    artworkURL: client.coverURL(
                                        coverArt: song.coverArt,
                                        size: 180
                                    ),
                                    isAdding: addingSongIDs.contains(song.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(addingSongIDs.contains(song.id))
                        }
                    }
                }
            }
            .navigationTitle("添加歌曲")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索歌曲、歌手或专辑"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task(id: searchRequest) { await search() }
            .alert(
                "添加失败",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { isPresented in
                        if !isPresented { errorMessage = nil }
                    }
                )
            ) {
                Button("好", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "请稍后重试。")
            }
        }
    }

    private var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchRequest: PlaylistSongSearchRequest {
        PlaylistSongSearchRequest(
            query: normalizedQuery,
            revision: searchRevision
        )
    }

    private func search() async {
        let query = normalizedQuery
        guard !query.isEmpty else {
            activeQuery = ""
            results = SubsonicSearchResults()
            errorMessage = nil
            isSearching = false
            return
        }

        activeQuery = query
        isSearching = true
        errorMessage = nil
        do {
            try await Task.sleep(for: .milliseconds(250))
            let loadedResults = try await client.search(query: query)
            try Task.checkCancellation()
            guard activeQuery == query else { return }
            results = loadedResults
        } catch is CancellationError {
            return
        } catch {
            guard activeQuery == query else { return }
            results = SubsonicSearchResults()
            errorMessage = error.localizedDescription
        }
        if activeQuery == query {
            isSearching = false
        }
    }

    private func add(_ song: SubsonicSong) {
        guard !existingSongIDs.contains(song.id),
              addingSongIDs.insert(song.id).inserted else {
            return
        }
        Task {
            defer { addingSongIDs.remove(song.id) }
            do {
                try await client.updatePlaylist(
                    id: playlistID,
                    songIDsToAdd: [song.id]
                )
                try Task.checkCancellation()
                addedSongIDs.insert(song.id)
                onChanged()
            } catch is CancellationError {
                return
            } catch {
                errorMessage = "添加失败：\(error.localizedDescription)"
            }
        }
    }
}

private struct PlaylistSongSearchRequest: Hashable {
    let query: String
    let revision: Int
}

private struct SongPickerRow: View {
    let song: SubsonicSong
    let artworkURL: URL?
    let isAdding: Bool

    var body: some View {
        HStack(spacing: 12) {
            LibraryArtwork(url: artworkURL, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text([song.artist, song.album]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isAdding {
                ProgressView()
            } else {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(.rect)
    }
}

struct PlaylistRow: View {
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
