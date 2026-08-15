import SwiftUI

enum LibraryRoute: Hashable {
    case albums
    case artists
    case favorites
    case playlists
    case history(ListeningHistoryListKind)
}

enum NowPlayingAnimation {
    static let artworkID = "now-playing-artwork"
    static let open = Animation.spring(
        response: 0.46,
        dampingFraction: 0.88
    )
    static let dismiss = Animation.interactiveSpring(
        response: 0.38,
        dampingFraction: 0.86
    )
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerStore.self) private var player
    @Environment(NavidromeSession.self) private var session
    @Environment(ListeningHistoryStore.self) private var history
    @Environment(PlaybackBehaviorStore.self) private var behavior
    @Environment(FavoritesStore.self) private var favorites
    @State private var isPlayerPresented = false
    @State private var navigationPath = NavigationPath()
    @Namespace private var playerNamespace

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
        .animation(statusAnimation, value: session.status)
        .task {
            guard session.status == .checking else { return }
            await session.restore(using: settings)
        }
        .onChange(of: session.status) { _, status in
            if status == .connected {
                let libraryIdentifier = session.isDemoMode
                    ? session.activeLibraryIdentifier
                    : settings.serverURL
                history.activate(serverURL: libraryIdentifier)
                behavior.activate(serverURL: libraryIdentifier)
                favorites.activate(serverURL: libraryIdentifier)
                if !session.isDemoMode,
                   let client = session.client {
                    player.restoreLastPlayback(
                        for: settings.serverURL,
                        using: client
                    )
                } else {
                    player.reset()
                }
            } else {
                player.reset()
                history.deactivate()
                behavior.deactivate()
                favorites.deactivate()
                isPlayerPresented = false
                navigationPath = NavigationPath()
            }
        }
        .onChange(of: player.qualifiedPlayEvent?.id) { _, _ in
            guard let event = player.qualifiedPlayEvent else { return }
            let libraryIdentifier = session.isDemoMode
                ? session.activeLibraryIdentifier
                : settings.serverURL
            history.record(event, for: libraryIdentifier)
            behavior.record(event, for: libraryIdentifier)
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
        ZStack {
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
                            case .albums:
                                AlbumLibraryView(client: client)
                            case .artists:
                                ArtistLibraryView(client: client)
                            case .favorites:
                                FavoritesView(client: client)
                            case .playlists:
                                PlaylistsView(client: client)
                            case let .history(kind):
                                SmartSongListView(kind: kind, client: client)
                            }
                        }
                    }
            }
            .scaleEffect(isPlayerPresented ? 0.965 : 1)
            .blur(radius: isPlayerPresented ? 2 : 0)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: isPlayerPresented ? 18 : 0,
                    style: .continuous
                )
            )

            Color.black
                .opacity(isPlayerPresented ? 0.18 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if isPlayerPresented {
                PlayerOverlay(
                    isPresented: $isPlayerPresented,
                    namespace: playerNamespace
                )
                .zIndex(1)
                .transition(playerTransition)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .environment(
            \.playerPresentation,
            Binding(
                get: { isPlayerPresented },
                set: { presented in
                    withAnimation(playerPresentationAnimation(for: presented)) {
                        isPlayerPresented = presented
                    }
                }
            )
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isPlayerPresented,
               player.currentSong != nil {
                MiniPlayerBar(namespace: playerNamespace) {
                    withAnimation(playerPresentationAnimation(for: true)) {
                        isPlayerPresented = true
                    }
                }
            }
        }
    }

    private var statusAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    private func playerPresentationAnimation(
        for presented: Bool
    ) -> Animation? {
        reduceMotion
            ? nil
            : (presented
                ? NowPlayingAnimation.open
                : NowPlayingAnimation.dismiss)
    }

    private var playerTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }
}

private struct MiniPlayerBar: View {
    @Environment(PlayerStore.self) private var player
    let namespace: Namespace.ID
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
                        .matchedGeometryEffect(
                            id: NowPlayingAnimation.artworkID,
                            in: namespace
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

private struct PlayerOverlay: View {
    @Binding var isPresented: Bool
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            PlayerView(namespace: namespace)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: dragOffset)
                .scaleEffect(scale(for: proxy.size.height), anchor: .center)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                )
                .overlay(alignment: .top) {
                    Color.clear
                        .frame(width: 112, height: 52)
                        .contentShape(Rectangle())
                        .gesture(dismissGesture(height: proxy.size.height))
                        .overlay(alignment: .top) {
                            Capsule()
                                .fill(.white.opacity(0.72))
                                .frame(width: 36, height: 5)
                                .padding(.top, 8)
                        }
                        .accessibilityLabel("下拉关闭播放器")
                }
                .onAppear { dragOffset = 0 }
        }
    }

    private var cornerRadius: CGFloat {
        guard !reduceMotion else { return 0 }
        return min(max(dragOffset / 5, 0), 22)
    }

    private func scale(for height: CGFloat) -> CGFloat {
        guard !reduceMotion else { return 1 }
        let progress = min(max(dragOffset / max(height * 0.78, 1), 0), 1)
        return 1 - progress * 0.04
    }

    private func dismissGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard value.translation.height > 0,
                      value.translation.height
                        > abs(value.translation.width) else {
                    return
                }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let translation = max(value.translation.height, 0)
                let predictedTranslation = max(
                    value.predictedEndTranslation.height,
                    0
                )
                let shouldDismiss = translation > max(120, height * 0.16)
                    || predictedTranslation > height * 0.28

                if shouldDismiss {
                    withAnimation(reduceMotion ? nil : NowPlayingAnimation.dismiss) {
                        isPresented = false
                    }
                } else {
                    withAnimation(reduceMotion ? nil : NowPlayingAnimation.dismiss) {
                        dragOffset = 0
                    }
                }
            }
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
