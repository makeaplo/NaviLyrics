import SwiftUI

enum LibraryRoute: Hashable {
    case favorites
    case playlists
    case history(ListeningHistoryListKind)
}

private struct PlayerRoute: Hashable { }

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerStore.self) private var player
    @Environment(NavidromeSession.self) private var session
    @Environment(ListeningHistoryStore.self) private var history
    @Environment(FavoritesStore.self) private var favorites
    @State private var isPlayerPresented = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        Group {
            if session.status == .connected {
                authenticatedContent
            } else if session.status == .checking {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("正在检查音乐库连接…")
                        .foregroundStyle(.secondary)
                }
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.22), value: session.status)
        .task {
            guard session.status == .checking else { return }
            await session.restore(using: settings)
        }
        .onChange(of: session.status) { _, status in
            if status == .connected {
                history.activate(serverURL: settings.serverURL)
                favorites.activate(serverURL: settings.serverURL)
                if let client = session.client {
                    player.restoreLastPlayback(
                        for: settings.serverURL,
                        using: client
                    )
                }
            } else {
                player.reset()
                history.deactivate()
                favorites.deactivate()
                isPlayerPresented = false
                navigationPath = NavigationPath()
            }
        }
        .onChange(of: player.qualifiedPlayEvent?.id) { _, _ in
            guard let event = player.qualifiedPlayEvent else { return }
            history.record(event, for: settings.serverURL)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                player.refreshNowPlayingInfo()
                if session.status == .connected,
                   let client = session.client {
                    Task {
                        await favorites.refresh(using: client)
                    }
                }
            } else {
                player.persistPlaybackState(force: true)
            }
        }
    }

    private var authenticatedContent: some View {
        NavigationStack(path: $navigationPath) {
            ContentView()
                .navigationDestination(for: SubsonicAlbum.self) { album in
                    if let client = session.client {
                        AlbumView(client: client, album: album)
                    }
                }
                .navigationDestination(for: SubsonicArtist.self) { artist in
                    if let client = session.client {
                        ArtistView(client: client, artist: artist)
                    }
                }
                .navigationDestination(for: SubsonicPlaylist.self) { playlist in
                    if let client = session.client {
                        PlaylistDetailView(
                            playlist: playlist,
                            client: client
                        )
                    }
                }
                .navigationDestination(for: LibraryRoute.self) { route in
                    if let client = session.client {
                        switch route {
                        case .favorites:
                            FavoritesView(client: client)
                        case .playlists:
                            PlaylistsView(client: client)
                        case let .history(kind):
                            SmartSongListView(kind: kind, client: client)
                        }
                    }
                }
                .navigationDestination(for: PlayerRoute.self) { _ in
                    PlayerView()
                }
        }
        .environment(\.playerPresentation, $isPlayerPresented)
        .onChange(of: isPlayerPresented) { _, isPresented in
            if isPresented {
                navigationPath.append(PlayerRoute())
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isPlayerPresented,
               player.currentSong != nil {
                MiniPlayerBar {
                    isPlayerPresented = true
                }
            }
        }
    }
}

private struct MiniPlayerBar: View {
    @Environment(PlayerStore.self) private var player
    let onOpenPlayer: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(
                value: player.progress,
                total: max(player.duration, 1)
            )
            .progressViewStyle(.linear)
            .tint(.accentColor)

            HStack(spacing: 12) {
                Button(action: onOpenPlayer) {
                    HStack(spacing: 10) {
                        LibraryArtwork(
                            url: player.currentSong?.artworkURL,
                            size: 42
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.currentSong?.title ?? "")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(player.currentSong?.artist ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开正在播放")

                Button {
                    player.togglePlayPause()
                } label: {
                    ZStack {
                        Image(
                            systemName: player.isPlaying
                                ? "pause.fill"
                                : "play.fill"
                        )
                        if player.isBuffering {
                            ProgressView()
                                .controlSize(.small)
                                .background(.regularMaterial, in: Circle())
                        }
                    }
                    .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(!player.canTogglePlayback)
                .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

                Button {
                    player.playNext()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(!player.canPlayNext)
                .accessibilityLabel("下一首")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct PlayerPresentationKey: EnvironmentKey {
    static let defaultValue = Binding<Bool>.constant(false)
}

extension EnvironmentValues {
    var playerPresentation: Binding<Bool> {
        get { self[PlayerPresentationKey.self] }
        set { self[PlayerPresentationKey.self] = newValue }
    }
}
