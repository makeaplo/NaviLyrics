import SwiftUI

struct PlayerView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerStore.self) private var player
    @Environment(NavidromeSession.self) private var session
    @Environment(\.playerPresentation) private var playerPresentation
    @State private var lyricsStore: NaviLyricsStore?
    @State private var currentTime: TimeInterval = 0
    @State private var highlightedLyricID: LyricLine.ID?
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0
    @State private var lyricsReloadRevision = 0
    @State private var showQueue = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                playerBackground
                VStack(spacing: 0) {
                    songInfo
                    lyricsArea
                    controls
                }
                // Timed lyrics are assembled from many attributed runs
                // and can report an ideal width larger than the device.
                .frame(
                    width: max(proxy.size.width - 32, 1),
                    height: proxy.size.height
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .onChange(of: player.progress, initial: true) { _, time in
                guard !isScrubbing else { return }
                currentTime = time
                updateHighlight(at: time)
            }
            .onChange(
                of: player.currentSong?.id,
                initial: true
            ) { _, _ in
                isScrubbing = false
                currentTime = player.progress
                scrubTime = player.progress
                highlightedLyricID = nil
            }
        }
        .navigationTitle("正在播放")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .environment(
            \.effectiveLyricsRefreshRate,
            settings.lyricsHighFrameRateEnabled ? .standard : .efficient
        )
        .task(id: lyricsLoadRequest) {
            await loadLyrics()
        }
        .onDisappear {
            playerPresentation.wrappedValue = false
        }
        .sheet(isPresented: $showQueue) {
            PlayerQueueView()
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: 歌曲信息

    private var songInfo: some View {
        HStack(spacing: 14) {
            LibraryArtwork(
                url: player.currentSong?.artworkURL,
                size: 54
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(player.currentSong?.title ?? "未在播放")
                    .font(.title3.bold())
                    .lineLimit(1)
                Text(songSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(player.queue.isEmpty)
            .accessibilityLabel("播放队列")
        }
        .padding(.vertical, 10)
    }

    private var songSubtitle: String {
        guard let song = player.currentSong else { return "" }
        return [song.artist, song.album]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var playerBackground: some View {
        ZStack {
            Color.black
            if let artworkURL = player.currentSong?.artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    if case let .success(image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 72)
                            .scaleEffect(1.25)
                            .opacity(0.42)
                    }
                }
            }
            LinearGradient(
                colors: [
                    .black.opacity(0.22),
                    .black.opacity(0.62),
                    .black.opacity(0.92),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .clipped()
    }

    // MARK: 歌词区

    @ViewBuilder
    private var lyricsArea: some View {
        if player.currentSong == nil {
            ContentUnavailableView(
                "选择一首歌",
                systemImage: "text.quote",
                description: Text("从音乐库打开歌曲后显示歌词")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let lyricsStore {
            Group {
                if lyricsStore.isLoading {
                    ProgressView("正在载入歌词…")
                } else if lyricsStore.lyrics.isEmpty {
                    ContentUnavailableView {
                        Label("暂无歌词", systemImage: "quote.bubble")
                    } description: {
                        Text(lyricsStore.errorMessage ?? "当前歌曲暂无歌词")
                    } actions: {
                        Button("重试") { lyricsReloadRevision &+= 1 }
                            .buttonStyle(.bordered)
                    }
                } else {
                    AppleMusicLyricsView(
                        lyrics: lyricsStore.lyrics,
                        errorMessage: lyricsStore.errorMessage,
                        highlightedLyricID: highlightedLyricID,
                        isActive: player.isPlaying,
                        isInterfaceHidden: false,
                        bottomOverlayHeight: 0,
                        onInterfaceInteraction: {},
                        onInterfaceVisibilityChange: { _ in },
                        onInitialFocusPrepared: {}
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView("正在准备歌词…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: 控制

    private var controls: some View {
        VStack(spacing: 10) {
            if let errorMessage = player.playbackErrorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.footnote)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button("重试") { player.retryPlayback() }
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            Slider(
                value: progressBinding,
                in: 0...max(player.duration, 1),
                onEditingChanged: handleScrubbing
            )
            .tint(.white)
            .disabled(player.currentSong == nil || player.duration <= 0)
            .accessibilityLabel("播放进度")
            .accessibilityValue(timeString(displayedTime))

            HStack {
                Text(timeString(displayedTime))
                Spacer()
                Text("−\(timeString(max(player.duration - displayedTime, 0)))")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.68))

            HStack(spacing: 44) {
                Button {
                    player.playPrevious()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .disabled(!player.canPlayPrevious)
                .accessibilityLabel("上一首")

                Button {
                    player.togglePlayPause()
                } label: {
                    ZStack {
                        Image(
                            systemName: player.isPlaying
                                ? "pause.circle.fill"
                                : "play.circle.fill"
                        )
                        .font(.system(size: 58))
                        if player.isBuffering {
                            Circle()
                                .fill(.black.opacity(0.48))
                                .frame(width: 44, height: 44)
                            ProgressView()
                                .tint(.white)
                        }
                    }
                }
                .disabled(!player.canTogglePlayback)
                .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
                .accessibilityValue(player.isBuffering ? "正在缓冲" : "")

                Button {
                    player.playNext()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .disabled(!player.canPlayNext)
                .accessibilityLabel("下一首")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 14)
    }

    private var progressBinding: Binding<TimeInterval> {
        Binding(
            get: { displayedTime },
            set: { value in
                scrubTime = value
                if isScrubbing {
                    currentTime = value
                    updateHighlight(at: value)
                }
            }
        )
    }

    private var displayedTime: TimeInterval {
        isScrubbing ? scrubTime : currentTime
    }

    private func handleScrubbing(_ editing: Bool) {
        if editing {
            scrubTime = currentTime
            isScrubbing = true
        } else {
            let target = scrubTime
            isScrubbing = false
            currentTime = target
            player.seek(to: target)
            updateHighlight(at: target)
        }
    }

    // MARK: 逻辑

    private var lyricsLoadRequest: LyricsLoadRequest {
        LyricsLoadRequest(
            songID: player.currentSong?.id,
            revision: lyricsReloadRevision
        )
    }

    private func loadLyrics() async {
        highlightedLyricID = nil
        guard let song = player.currentSong,
              let client = session.client else {
            lyricsStore = nil
            return
        }

        let store = NaviLyricsStore(client: client)
        lyricsStore = store
        await store.load(for: song)
        guard !Task.isCancelled,
              player.currentSong?.id == song.id else {
            return
        }
        updateHighlight(at: player.estimatedProgress())
    }

    private func updateHighlight(at time: TimeInterval) {
        guard let store = lyricsStore, !store.lyrics.isEmpty else {
            highlightedLyricID = nil
            return
        }
        let current = LyricPlaybackTimeline.position(
            at: time,
            in: store.lyrics
        ).highlightedLyricID
        if highlightedLyricID != current {
            highlightedLyricID = current
        }
    }

    private func timeString(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let normalized = max(time, 0)
        let minutes = Int(normalized) / 60
        let seconds = Int(normalized) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct LyricsLoadRequest: Hashable {
    let songID: String?
    let revision: Int
}

private struct PlayerQueueView: View {
    @Environment(PlayerStore.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if player.queue.isEmpty {
                    ContentUnavailableView(
                        "播放队列为空",
                        systemImage: "list.bullet"
                    )
                } else {
                    List {
                        ForEach(player.queue.indices, id: \.self) { index in
                            let song = player.queue[index]
                            Button {
                                player.playQueueItem(at: index)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    if player.queueIndex == index {
                                        Image(systemName: "speaker.wave.2.fill")
                                            .foregroundStyle(Color.accentColor)
                                            .frame(width: 22)
                                    } else {
                                        Text("\(index + 1)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 22)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(song.title)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(song.artist)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .moveDisabled(player.queueIndex == index)
                            .deleteDisabled(player.queueIndex == index)
                        }
                        .onDelete(perform: player.removeQueueItems)
                        .onMove(perform: player.moveQueueItem)
                    }
                }
            }
            .navigationTitle("播放队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("清空待播") {
                        player.clearUpcomingQueue()
                    }
                    .disabled(!player.canClearUpcomingQueue)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
