import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerStore.self) private var player
    @Environment(NavidromeSession.self) private var session
    @Environment(ListeningHistoryStore.self) private var history
    @Environment(FavoritesStore.self) private var favorites
    @State private var selectedTab: AppTab = .library

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
                if let client = session.client,
                   player.restoreLastPlayback(
                    for: settings.serverURL,
                    using: client
                   ) {
                    selectedTab = .player
                }
            } else {
                player.reset()
                history.deactivate()
                favorites.deactivate()
            }
        }
        .onChange(of: player.qualifiedPlayEvent?.id) { _, _ in
            guard let event = player.qualifiedPlayEvent else { return }
            history.record(event, for: settings.serverURL)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                player.persistPlaybackState(force: true)
            }
        }
    }

    private var authenticatedContent: some View {
        TabView(selection: $selectedTab) {
            ContentView {
                selectedTab = .player
            }
                .tabItem {
                    Label("音乐库", systemImage: "music.note.list")
                }
                .tag(AppTab.library)
            PlayerView()
                .tabItem {
                    Label("播放", systemImage: "play.circle")
                }
                .tag(AppTab.player)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selectedTab != .player,
               player.currentSong != nil {
                MiniPlayerBar {
                    selectedTab = .player
                }
            }
        }
        .onChange(of: player.currentSong?.id) { _, songID in
            if songID != nil {
                selectedTab = .player
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
                        AsyncImage(
                            url: player.currentSong?.artworkURL
                        ) { phase in
                            if case let .success(image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(.quaternary)
                                    .overlay {
                                        Image(systemName: "music.note")
                                            .foregroundStyle(.secondary)
                                    }
                            }
                        }
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 7))

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

private enum AppTab: Hashable {
    case library
    case player
}
