import SwiftUI

struct ForYouView: View {
    @Environment(NavidromeSession.self) private var session
    @Environment(PlayerStore.self) private var player
    @Environment(ListeningHistoryStore.self) private var history
    @Environment(PlaybackBehaviorStore.self) private var behavior
    @Environment(FavoritesStore.self) private var favorites
    @Environment(PersonalizedRecommendationCache.self)
    private var recommendationCache
    @Environment(\.playerPresentation) private var playerPresentation
    @State private var recommendations: [PersonalizedRecommendation] = []
    @State private var recommendationLibrarySongs: [SubsonicSong] = []
    @State private var recommendationLibrarySignature = ""
    @State private var isLoadingRecommendations = false
    @State private var recommendationErrorMessage: String?
    @State private var recommendationReloadRevision = 0

    var body: some View {
        Group {
            if let client = session.client {
                List {
                    if player.currentSong != nil {
                        continuePlayingSection
                    }

                    recommendationsSection(client: client)
                    historySection(
                        title: "最近播放",
                        kind: .recent,
                        items: history.recentItems(),
                        client: client
                    )
                    historySection(
                        title: "本机常听",
                        kind: .mostPlayed,
                        items: history.mostPlayedItems(),
                        client: client
                    )
                }
                .listStyle(.insetGrouped)
                .task(id: recommendationRequest) {
                    await loadRecommendations(using: client)
                }
                .task(id: favorites.activeServerURL) {
                    guard !favorites.activeServerURL.isEmpty else {
                        return
                    }
                    await favorites.refresh(using: client)
                }
                .refreshable {
                    await session.refreshLibrary()
                    await favorites.refresh(using: client)
                    await loadRecommendations(using: client, force: true)
                }
            } else {
                ProgressView("正在连接音乐库…")
            }
        }
        .navigationTitle("为你")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func recommendationsSection(client: SubsonicClient) -> some View {
        Section {
            if isLoadingRecommendations {
                HStack {
                    Spacer()
                    ProgressView("正在分析你的音乐偏好…")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if let recommendationErrorMessage {
                HStack(spacing: 10) {
                    Label(
                        recommendationErrorMessage,
                        systemImage: "wifi.exclamationmark"
                    )
                    Spacer(minLength: 8)
                    Button("重试") {
                        recommendationReloadRevision &+= 1
                    }
                    .font(.footnote.weight(.semibold))
                }
                .font(.footnote)
            } else if visibleRecommendations.isEmpty {
                Text("播放几首歌或收藏歌曲后，这里会出现只属于你的推荐。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(visibleRecommendations) { recommendation in
                            RecommendationCard(
                                recommendation: recommendation,
                                artworkURL: client.coverURL(
                                    coverArt: recommendation.song.coverArt,
                                    size: 400
                                )
                            ) {
                                playRecommendation(
                                    recommendation,
                                    using: client
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        } header: {
            HStack {
                Text("为你推荐")
                Spacer()
                Button("刷新") {
                    recommendationReloadRevision &+= 1
                }
                .font(.caption.weight(.semibold))
                .disabled(isLoadingRecommendations)
            }
        } footer: {
            if !visibleRecommendations.isEmpty {
                Text("推荐只使用本机播放和收藏记录，不会上传到 Navidrome。")
            }
        }
    }

    private var recommendationRequest: String {
        let albumSignature = session.albums.map(\.id).joined(separator: ",")
        let signalSignature = recommendationSignalSignature
        return [
            session.activeLibraryIdentifier,
            albumSignature,
            signalSignature,
            "\(recommendationReloadRevision)",
        ].joined(separator: "||")
    }

    private var recommendationSignalSignature: String {
        let behaviorSignature = behavior.items.map { item in
            [
                item.id,
                "\(item.playCount)",
                "\(item.completionCount)",
                "\(item.skipCount)",
                "\(item.lastPlayedAt?.timeIntervalSince1970 ?? 0)",
            ].joined(separator: ":")
        }.joined(separator: "|")
        let favoriteSignature = favorites.songs
            .map(\.id)
            .sorted()
            .joined(separator: ",")
        return [
            behaviorSignature,
            favoriteSignature,
        ].joined(separator: "||")
    }

    private var visibleRecommendations: [PersonalizedRecommendation] {
        guard let currentSongID = player.currentSong?.id else {
            return recommendations
        }
        return recommendations.filter { $0.song.id != currentSongID }
    }

    private func loadRecommendations(
        using client: SubsonicClient,
        force: Bool = false
    ) async {
        let librarySignature = session.albums.map(\.id).joined(separator: ",")
        let signalSignature = recommendationSignalSignature
        if force || recommendationLibrarySignature != librarySignature {
            recommendationLibrarySignature = librarySignature
            recommendationLibrarySongs = []
        }

        let hasPersonalSignal = !favorites.songs.isEmpty
            || behavior.items.contains(where: \.hasPositiveSignal)
        guard hasPersonalSignal else {
            recommendations = []
            recommendationErrorMessage = nil
            isLoadingRecommendations = false
            return
        }

        if !force,
           let cachedRecommendations = recommendationCache
                .cachedRecommendations(
                    librarySignature: librarySignature,
                    signalSignature: signalSignature
                ) {
            recommendations = cachedRecommendations
            recommendationErrorMessage = nil
            isLoadingRecommendations = false
            return
        }

        if recommendationLibrarySongs.isEmpty, !session.albums.isEmpty {
            isLoadingRecommendations = true
            recommendationErrorMessage = nil
            do {
                recommendationLibrarySongs = try await client.librarySongs(
                    from: session.albums
                )
            } catch is CancellationError {
                return
            } catch {
                recommendationErrorMessage =
                    "推荐加载失败：\(error.localizedDescription)"
                isLoadingRecommendations = false
                return
            }
        }

        recommendations = PersonalizedRecommendationEngine.recommend(
            songs: recommendationLibrarySongs,
            behavior: behavior.items,
            favorites: favorites.songs,
            limit: 8
        )
        recommendationCache.save(
            recommendations,
            librarySignature: librarySignature,
            signalSignature: signalSignature
        )
        recommendationErrorMessage = nil
        isLoadingRecommendations = false
    }

    private func playRecommendation(
        _ recommendation: PersonalizedRecommendation,
        using client: SubsonicClient
    ) {
        player.load(song: client.makeNowPlayingSong(from: recommendation.song))
        playerPresentation.wrappedValue = true
    }

    private var continuePlayingSection: some View {
        Section("继续播放") {
            Button {
                player.play()
                playerPresentation.wrappedValue = true
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
                    NavigationLink(value: LibraryRoute.history(kind)) {
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
        playerPresentation.wrappedValue = true
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
    @Environment(\.playerPresentation) private var playerPresentation

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
        playerPresentation.wrappedValue = true
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

private struct RecommendationCard: View {
    let recommendation: PersonalizedRecommendation
    let artworkURL: URL?
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 8) {
                LibraryArtwork(url: artworkURL, size: 148)

                Text(recommendation.song.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(
                    recommendation.song.artist.isEmpty
                        ? "未知艺术家"
                        : recommendation.song.artist
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                Text(recommendation.reason.title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .frame(minHeight: 28, alignment: .top)
            }
            .frame(width: 148, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("播放这首推荐歌曲")
    }
}
