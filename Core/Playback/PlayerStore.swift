import AVFoundation
import Foundation
import MediaPlayer
import Observation
import UIKit

// MARK: - 播放状态（对应 MeloX PlayerStore 的歌词渲染所需接口）

struct NowPlayingSong: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let streamURL: URL
    let artworkURL: URL?
    /// Safe server-side identifier used to rebuild an authenticated artwork
    /// URL. Authenticated URLs themselves must never be persisted.
    let artworkIdentifier: String?

    init(
        id: String,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        streamURL: URL,
        artworkURL: URL?,
        artworkIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration.isFinite ? max(duration, 0) : 0
        self.streamURL = streamURL
        self.artworkURL = artworkURL
        self.artworkIdentifier = artworkIdentifier
    }

    // 兼容 MeloX 歌词分享代码的命名
    var name: String { title }
    var artistText: String { artist }
}

@MainActor
@Observable
final class PlayerStore {
    private struct PersistedSong: Codable {
        let id: String
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
        let artworkIdentifier: String?

        init(song: NowPlayingSong) {
            id = song.id
            title = song.title
            artist = song.artist
            album = song.album
            duration = song.duration.isFinite ? max(song.duration, 0) : 0
            artworkIdentifier = song.artworkIdentifier
        }

        func makeNowPlayingSong(
            using client: SubsonicClient
        ) -> NowPlayingSong {
            NowPlayingSong(
                id: id,
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                streamURL: client.streamURL(songID: id),
                artworkURL: client.coverURL(
                    coverArt: artworkIdentifier,
                    size: 900
                ),
                artworkIdentifier: artworkIdentifier
            )
        }
    }

    private struct PersistedPlaybackState: Codable {
        let serverURL: String
        let queue: [PersistedSong]
        let queueIndex: Int
        let progress: TimeInterval
    }

    /// v1 persisted complete authenticated URLs. It is decoded only for a
    /// one-time migration to the credential-free v2 representation.
    private struct LegacyPersistedPlaybackState: Codable {
        struct Song: Codable {
            let id: String
            let title: String
            let artist: String
            let album: String
            let duration: TimeInterval
            let streamURL: URL
            let artworkURL: URL?
        }

        let serverURL: String
        let queue: [Song]
        let queueIndex: Int
        let progress: TimeInterval
    }

    private static let playbackStateKey = "lastPlaybackState.v2"
    private static let legacyPlaybackStateKey = "lastPlaybackState.v1"
    private static let persistenceInterval: TimeInterval = 2
    private static let progressObservationInterval: TimeInterval = 0.2
    private static let artworkCache = NSCache<NSURL, UIImage>()

    // MARK: 歌词视图依赖的成员（与 MeloX PlayerStore 对齐）

    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var playbackErrorMessage: String?
    private(set) var duration: TimeInterval = 0
    private(set) var seekRevision = 0
    private(set) var currentSong: NowPlayingSong?
    private(set) var queue: [NowPlayingSong] = []
    private(set) var queueIndex: Int?
    private(set) var qualifiedPlayEvent: PlaybackHistoryEvent?
    /// 当前播放进度（秒），由时间观察器持续更新，歌词视图 onChange 依赖
    private(set) var progress: TimeInterval = 0

    var canTogglePlayback: Bool {
        currentSong != nil && (player != nil || isDemoPlayback)
    }

    // MARK: 播放器

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var playbackEndObserver: NSObjectProtocol?
    private var playbackFailureObserver: NSObjectProtocol?
    private var audioSessionObservers: [NSObjectProtocol] = []
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var restoreTimeoutTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var demoProgressTask: Task<Void, Never>?
    private var remoteCommandHandlers: [
        (command: MPRemoteCommand, token: Any)
    ] = []
    private let defaults = UserDefaults.standard
    private var persistenceServerURL: String?
    private var lastPersistedProgress: TimeInterval = -.infinity
    private var lastNowPlayingInfoProgress: TimeInterval = -.infinity
    private var isRestoringPlayback = false
    private var shouldResumeAfterInterruption = false
    private var playbackGeneration = 0
    private var accumulatedPlaybackTime: TimeInterval = 0
    private var lastObservedProgress: TimeInterval?
    private var hasQualifiedCurrentPlay = false
    private var isDemoPlayback = false

    init() {
        prepareAudioSession()
        installAudioSessionObservers()
        configureRemoteCommands()
    }

    // MARK: 控制

    func load(song: NowPlayingSong, autoplay: Bool = true) {
        persistPlaybackState(force: true)
        isRestoringPlayback = false
        restoreTimeoutTask?.cancel()
        queue = [song]
        queueIndex = 0
        loadCurrentSong(song, autoplay: autoplay)
    }

    func load(
        queue: [NowPlayingSong],
        startingAt index: Int,
        autoplay: Bool = true
    ) {
        guard queue.indices.contains(index) else { return }
        persistPlaybackState(force: true)
        isRestoringPlayback = false
        restoreTimeoutTask?.cancel()
        self.queue = queue
        queueIndex = index
        loadCurrentSong(queue[index], autoplay: autoplay)
    }

    func playQueueItem(at index: Int) {
        guard queue.indices.contains(index) else { return }
        persistPlaybackState(force: true)
        isRestoringPlayback = false
        restoreTimeoutTask?.cancel()
        queueIndex = index
        loadCurrentSong(queue[index], autoplay: true)
    }

    /// Adds songs after the current item or at the end of the queue.
    /// If nothing is playing yet, the first song starts immediately.
    func enqueue(
        _ songs: [NowPlayingSong],
        afterCurrent: Bool
    ) {
        guard !songs.isEmpty else { return }
        guard let currentIndex = queueIndex,
              currentSong != nil,
              queue.indices.contains(currentIndex) else {
            load(queue: songs, startingAt: 0)
            return
        }

        let insertionIndex = afterCurrent
            ? currentIndex + 1
            : queue.count
        queue.insert(contentsOf: songs, at: insertionIndex)
        persistPlaybackState(force: true)
        updateRemoteCommandAvailability()
    }

    private func loadCurrentSong(
        _ song: NowPlayingSong,
        autoplay: Bool
    ) {
        playbackGeneration &+= 1
        let generation = playbackGeneration

        artworkTask?.cancel()
        artworkTask = nil
        tearDownPlayer()
        currentSong = song
        duration = song.duration
        progress = 0
        isPlaying = false
        isBuffering = false
        playbackErrorMessage = nil
        qualifiedPlayEvent = nil
        accumulatedPlaybackTime = 0
        lastObservedProgress = nil
        hasQualifiedCurrentPlay = false

        if song.streamURL.scheme == "navi-demo" {
            isDemoPlayback = true
            updateRemoteCommandAvailability()
            updateNowPlayingInfo(force: true)
            if autoplay {
                play()
            } else {
                persistPlaybackState(force: true)
            }
            return
        }

        let item = AVPlayerItem(url: song.streamURL)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        player = newPlayer
        installTimeObserver(for: newPlayer, generation: generation)
        installPlaybackObservers(
            for: newPlayer,
            item: item,
            generation: generation
        )
        updateRemoteCommandAvailability()
        updateNowPlayingInfo(force: true)
        loadNowPlayingArtwork(for: song, generation: generation)

        if autoplay {
            play()
        } else {
            persistPlaybackState(force: true)
        }
    }

    /// Restores the last queue and position for the connected server. Restored
    /// audio remains paused so launching the app never starts sound by itself.
    @discardableResult
    func restoreLastPlayback(
        for serverURL: String,
        using client: SubsonicClient
    ) -> Bool {
        let normalizedServerURL = Self.normalizedServerURL(serverURL)
        persistenceServerURL = normalizedServerURL
        guard let state = persistedPlaybackState(
            for: normalizedServerURL
        ), state.queue.indices.contains(state.queueIndex) else {
            return false
        }

        let restoredQueue = state.queue.map {
            $0.makeNowPlayingSong(using: client)
        }
        guard restoredQueue.indices.contains(state.queueIndex) else {
            return false
        }

        isRestoringPlayback = true
        queue = restoredQueue
        queueIndex = state.queueIndex
        loadCurrentSong(restoredQueue[state.queueIndex], autoplay: false)

        let savedProgress = state.progress.isFinite ? state.progress : 0
        let target = min(
            max(savedProgress, 0),
            max(restoredQueue[state.queueIndex].duration, 0)
        )
        progress = target
        seekRevision &+= 1
        let generation = playbackGeneration
        let targetTime = CMTime(
            seconds: target,
            preferredTimescale: 600
        )
        player?.seek(
            to: targetTime,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.playbackGeneration == generation else {
                    return
                }
                self.finishPlaybackRestore(at: target)
            }
        }
        scheduleRestoreTimeout(
            generation: generation,
            target: target
        )
        return true
    }

    func persistPlaybackState(force: Bool = false) {
        guard !isDemoPlayback,
              !isRestoringPlayback,
              let serverURL = persistenceServerURL,
              let queueIndex,
              queue.indices.contains(queueIndex) else {
            return
        }

        let currentProgress = estimatedProgress()
        guard currentProgress.isFinite,
              force
                || abs(currentProgress - lastPersistedProgress)
                    >= Self.persistenceInterval else {
            return
        }
        let state = PersistedPlaybackState(
            serverURL: serverURL,
            queue: queue.map(PersistedSong.init(song:)),
            queueIndex: queueIndex,
            progress: currentProgress
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.playbackStateKey)
        defaults.removeObject(forKey: Self.legacyPlaybackStateKey)
        lastPersistedProgress = currentProgress
    }

    func clearPersistedPlaybackState() {
        defaults.removeObject(forKey: Self.playbackStateKey)
        defaults.removeObject(forKey: Self.legacyPlaybackStateKey)
        lastPersistedProgress = -.infinity
    }

    var canPlayPrevious: Bool {
        guard currentSong != nil else { return false }
        return progress > 3 || (queueIndex.map { $0 > 0 } ?? false)
    }

    var canPlayNext: Bool {
        guard let queueIndex else { return false }
        return queue.indices.contains(queueIndex + 1)
    }

    var canClearUpcomingQueue: Bool {
        guard let queueIndex else { return false }
        return queue.indices.contains(queueIndex + 1)
    }

    func playPrevious() {
        guard currentSong != nil else { return }
        if progress > 3 {
            seek(to: 0)
            return
        }
        guard let queueIndex,
              queueIndex > 0,
              queue.indices.contains(queueIndex - 1) else {
            seek(to: 0)
            return
        }
        persistPlaybackState(force: true)
        let previousIndex = queueIndex - 1
        self.queueIndex = previousIndex
        loadCurrentSong(queue[previousIndex], autoplay: true)
    }

    func playNext() {
        guard let queueIndex,
              queue.indices.contains(queueIndex + 1) else {
            pause()
            return
        }
        persistPlaybackState(force: true)
        let nextIndex = queueIndex + 1
        self.queueIndex = nextIndex
        loadCurrentSong(queue[nextIndex], autoplay: true)
    }

    func removeQueueItems(at offsets: IndexSet) {
        guard let currentIndex = queueIndex else { return }
        let validOffsets = offsets.filter { queue.indices.contains($0) }
        guard !validOffsets.isEmpty,
              !validOffsets.contains(currentIndex) else {
            return
        }

        for offset in validOffsets.sorted(by: >) {
            queue.remove(at: offset)
        }
        let removedBeforeCurrent = validOffsets.filter {
            $0 < currentIndex
        }.count
        queueIndex = currentIndex - removedBeforeCurrent
        persistPlaybackState(force: true)
        updateRemoteCommandAvailability()
    }

    func moveQueueItem(from offsets: IndexSet, to destination: Int) {
        guard offsets.count == 1,
              let source = offsets.first,
              queue.indices.contains(source),
              let currentIndex = queueIndex,
              source != currentIndex else {
            return
        }

        let item = queue.remove(at: source)
        var insertionIndex = destination
        if source < destination {
            insertionIndex -= 1
        }
        insertionIndex = min(max(insertionIndex, 0), queue.count)
        queue.insert(item, at: insertionIndex)

        var adjustedCurrentIndex = currentIndex
        if source < currentIndex {
            adjustedCurrentIndex -= 1
        }
        if insertionIndex <= adjustedCurrentIndex {
            adjustedCurrentIndex += 1
        }
        queueIndex = adjustedCurrentIndex
        persistPlaybackState(force: true)
    }

    func clearUpcomingQueue() {
        guard canClearUpcomingQueue,
              let currentIndex = queueIndex else {
            return
        }
        queue = Array(queue.prefix(currentIndex + 1))
        persistPlaybackState(force: true)
        updateRemoteCommandAvailability()
    }

    func play() {
        guard currentSong != nil else { return }
        if duration > 0, progress >= duration - 0.25 {
            seek(to: 0)
        }
        lastObservedProgress = estimatedProgress()
        if !isDemoPlayback {
            guard activateAudioSession() else { return }
        }
        playbackErrorMessage = nil
        if isDemoPlayback {
            isPlaying = true
            isBuffering = false
            startDemoProgressTask()
            updateNowPlayingInfo(force: true)
            persistPlaybackState(force: true)
            return
        }
        guard let player else { return }
        player.play()
        isPlaying = true
        isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        updateNowPlayingInfo(force: true)
        persistPlaybackState(force: true)
    }

    func pause() {
        guard currentSong != nil else { return }
        lastObservedProgress = estimatedProgress()
        demoProgressTask?.cancel()
        demoProgressTask = nil
        player?.pause()
        isPlaying = false
        isBuffering = false
        updateNowPlayingInfo(force: true)
        persistPlaybackState(force: true)
    }

    func retryPlayback() {
        guard let currentSong else { return }
        let target = progress
        loadCurrentSong(currentSong, autoplay: false)
        seek(to: target)
        play()
    }

    func reset(clearsPersistedState: Bool = false) {
        if clearsPersistedState {
            clearPersistedPlaybackState()
        } else {
            persistPlaybackState(force: true)
        }
        isRestoringPlayback = false
        restoreTimeoutTask?.cancel()
        artworkTask?.cancel()
        artworkTask = nil
        playbackGeneration &+= 1
        tearDownPlayer()
        currentSong = nil
        queue = []
        queueIndex = nil
        duration = 0
        progress = 0
        isPlaying = false
        isBuffering = false
        playbackErrorMessage = nil
        qualifiedPlayEvent = nil
        seekRevision &+= 1
        updateRemoteCommandAvailability()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        deactivateAudioSession()
    }

    func togglePlayPause() {
        guard canTogglePlayback else { return }
        isPlaying ? pause() : play()
    }

    func seek(to time: TimeInterval) {
        guard currentSong != nil,
              time.isFinite else {
            return
        }
        let upperBound = duration > 0 ? duration : max(time, 0)
        let target = min(max(time, 0), upperBound)
        progress = target
        lastObservedProgress = target
        if let player {
            let cmTime = CMTime(seconds: target, preferredTimescale: 600)
            player.seek(to: cmTime)
        }
        seekRevision &+= 1
        updateNowPlayingInfo(force: true)
        persistPlaybackState(force: true)
    }

    /// 当前播放进度（歌词高亮用）
    func estimatedProgress() -> TimeInterval {
        guard let player else { return max(progress, 0) }
        let time = player.currentTime().seconds
        return time.isFinite ? max(time, 0) : max(progress, 0)
    }

    /// 指定时刻的播放进度（TimelineView 驱动用）
    func estimatedProgress(at date: Date) -> TimeInterval {
        estimatedProgress()
    }

    private func startDemoProgressTask() {
        demoProgressTask?.cancel()
        let generation = playbackGeneration
        demoProgressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch {
                    return
                }
                guard let self,
                      self.playbackGeneration == generation,
                      self.isDemoPlayback,
                      self.isPlaying else {
                    return
                }
                self.progress = min(
                    self.progress + 0.2,
                    max(self.duration, 0)
                )
                self.recordQualifiedPlayIfNeeded()
                self.persistPlaybackState()
                self.updateNowPlayingInfo()
                if self.duration > 0,
                   self.progress >= self.duration {
                    self.playNext()
                    return
                }
            }
        }
    }

    // MARK: 时间与播放器观察

    private func installTimeObserver(
        for player: AVPlayer,
        generation: Int
    ) {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(
                seconds: Self.progressObservationInterval,
                preferredTimescale: 600
            ),
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      self.playbackGeneration == generation else {
                    return
                }
                let normalizedSeconds = max(seconds, 0)
                if self.isPlaying,
                   let previous = self.lastObservedProgress {
                    let delta = normalizedSeconds - previous
                    if delta > 0, delta <= 2 {
                        self.accumulatedPlaybackTime += delta
                    }
                }
                self.lastObservedProgress = normalizedSeconds
                self.progress = normalizedSeconds
                self.recordQualifiedPlayIfNeeded()
                self.persistPlaybackState()
                self.updateNowPlayingInfo()
            }
        }
    }

    private func installPlaybackObservers(
        for player: AVPlayer,
        item: AVPlayerItem,
        generation: Int
    ) {
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.playbackGeneration == generation else {
                    return
                }
                self.playNext()
            }
        }

        playbackFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let message = (notification.userInfo?[
                AVPlayerItemFailedToPlayToEndTimeErrorKey
            ] as? Error)?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self,
                      self.playbackGeneration == generation else {
                    return
                }
                self.handlePlaybackFailure(message: message)
            }
        }

        itemStatusObservation = item.observe(
            \.status,
            options: [.initial, .new]
        ) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription
            let itemDuration = item.duration.seconds
            Task { @MainActor [weak self] in
                guard let self,
                      self.playbackGeneration == generation else {
                    return
                }
                self.handleItemStatus(
                    status,
                    duration: itemDuration,
                    errorMessage: message
                )
            }
        }

        timeControlStatusObservation = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self,
                      self.playbackGeneration == generation else {
                    return
                }
                self.isBuffering =
                    self.isPlaying
                    && status == .waitingToPlayAtSpecifiedRate
            }
        }
    }

    private func handleItemStatus(
        _ status: AVPlayerItem.Status,
        duration itemDuration: TimeInterval,
        errorMessage: String?
    ) {
        switch status {
        case .readyToPlay:
            if itemDuration.isFinite, itemDuration > 0 {
                duration = itemDuration
            }
            playbackErrorMessage = nil
            updateNowPlayingInfo(force: true)
        case .failed:
            handlePlaybackFailure(message: errorMessage)
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func handlePlaybackFailure(message: String?) {
        isPlaying = false
        isBuffering = false
        isRestoringPlayback = false
        restoreTimeoutTask?.cancel()
        playbackErrorMessage = message.map {
            "播放失败：\($0)"
        } ?? "播放失败，请检查网络或音频格式"
        updateNowPlayingInfo(force: true)
    }

    private func recordQualifiedPlayIfNeeded() {
        guard !hasQualifiedCurrentPlay,
              isPlaying,
              let currentSong else {
            return
        }

        let qualificationThreshold: TimeInterval
        if duration.isFinite, duration > 0 {
            qualificationThreshold = min(30, max(duration * 0.5, 1))
        } else {
            qualificationThreshold = 30
        }
        guard accumulatedPlaybackTime >= qualificationThreshold else {
            return
        }

        hasQualifiedCurrentPlay = true
        qualifiedPlayEvent = PlaybackHistoryEvent(
            song: currentSong,
            playedAt: Date()
        )
    }

    private func tearDownPlayer() {
        demoProgressTask?.cancel()
        demoProgressTask = nil
        isDemoPlayback = false
        player?.pause()
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
        playbackEndObserver = nil
        if let playbackFailureObserver {
            NotificationCenter.default.removeObserver(
                playbackFailureObserver
            )
        }
        playbackFailureObserver = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        timeControlStatusObservation?.invalidate()
        timeControlStatusObservation = nil
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    // MARK: 播放恢复与持久化迁移

    private func finishPlaybackRestore(at target: TimeInterval) {
        restoreTimeoutTask?.cancel()
        progress = target
        isRestoringPlayback = false
        lastPersistedProgress = target
        updateNowPlayingInfo(force: true)
        persistPlaybackState(force: true)
    }

    private func scheduleRestoreTimeout(
        generation: Int,
        target: TimeInterval
    ) {
        restoreTimeoutTask?.cancel()
        restoreTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard let self,
                  self.playbackGeneration == generation,
                  self.isRestoringPlayback else {
                return
            }
            self.finishPlaybackRestore(at: target)
        }
    }

    private func persistedPlaybackState(
        for normalizedServerURL: String
    ) -> PersistedPlaybackState? {
        if let data = defaults.data(forKey: Self.playbackStateKey),
           let state = try? JSONDecoder().decode(
                PersistedPlaybackState.self,
                from: data
           ), Self.normalizedServerURL(state.serverURL)
                == normalizedServerURL {
            return state
        }

        guard let legacyData = defaults.data(
            forKey: Self.legacyPlaybackStateKey
        ), let legacyState = try? JSONDecoder().decode(
            LegacyPersistedPlaybackState.self,
            from: legacyData
        ), Self.normalizedServerURL(legacyState.serverURL)
            == normalizedServerURL else {
            return nil
        }

        let migratedState = PersistedPlaybackState(
            serverURL: legacyState.serverURL,
            queue: legacyState.queue.map { song in
                PersistedSong(
                    song: NowPlayingSong(
                        id: song.id,
                        title: song.title,
                        artist: song.artist,
                        album: song.album,
                        duration: song.duration,
                        streamURL: song.streamURL,
                        artworkURL: song.artworkURL,
                        artworkIdentifier: Self.artworkIdentifier(
                            from: song.artworkURL
                        )
                    )
                )
            },
            queueIndex: legacyState.queueIndex,
            progress: legacyState.progress.isFinite
                ? max(legacyState.progress, 0)
                : 0
        )
        if let migratedData = try? JSONEncoder().encode(migratedState) {
            defaults.set(migratedData, forKey: Self.playbackStateKey)
            defaults.removeObject(forKey: Self.legacyPlaybackStateKey)
        }
        return migratedState
    }

    private static func artworkIdentifier(from url: URL?) -> String? {
        guard let url,
              let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
              ) else {
            return nil
        }
        return components.queryItems?.first {
            $0.name == "id"
        }?.value
    }

    // MARK: 系统音频会话

    private func prepareAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default
            )
        } catch {
            // Retried when playback actually starts so opening NaviLyrics
            // never interrupts another app merely to configure audio.
        }
    }

    @discardableResult
    private func activateAudioSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            return true
        } catch {
            playbackErrorMessage =
                "无法启用音频：\(error.localizedDescription)"
            return false
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func installAudioSessionObservers() {
        let center = NotificationCenter.default
        audioSessionObservers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                let rawType = notification.userInfo?[
                    AVAudioSessionInterruptionTypeKey
                ] as? UInt
                let rawOptions = notification.userInfo?[
                    AVAudioSessionInterruptionOptionKey
                ] as? UInt
                Task { @MainActor [weak self] in
                    self?.handleAudioInterruption(
                        rawType: rawType,
                        rawOptions: rawOptions
                    )
                }
            }
        )
        audioSessionObservers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                let rawReason = notification.userInfo?[
                    AVAudioSessionRouteChangeReasonKey
                ] as? UInt
                Task { @MainActor [weak self] in
                    guard rawReason.flatMap(
                        AVAudioSession.RouteChangeReason.init(rawValue:)
                    ) == .oldDeviceUnavailable else {
                        return
                    }
                    self?.pause()
                }
            }
        )
    }

    private func handleAudioInterruption(
        rawType: UInt?,
        rawOptions: UInt?
    ) {
        guard let rawType,
              let type = AVAudioSession.InterruptionType(
                rawValue: rawType
              ) else {
            return
        }
        switch type {
        case .began:
            shouldResumeAfterInterruption = isPlaying
            pause()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(
                rawValue: rawOptions ?? 0
            )
            let shouldResume = shouldResumeAfterInterruption
                && options.contains(.shouldResume)
            shouldResumeAfterInterruption = false
            if shouldResume {
                play()
            }
        @unknown default:
            break
        }
    }

    // MARK: 锁屏与耳机遥控

    func refreshNowPlayingInfo() {
        updateNowPlayingInfo(force: true)
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        remoteCommandHandlers.append((
            center.playCommand,
            center.playCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in self?.play() }
                return .success
            }
        ))
        remoteCommandHandlers.append((
            center.pauseCommand,
            center.pauseCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in self?.pause() }
                return .success
            }
        ))
        remoteCommandHandlers.append((
            center.togglePlayPauseCommand,
            center.togglePlayPauseCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.togglePlayPause()
                }
                return .success
            }
        ))
        remoteCommandHandlers.append((
            center.previousTrackCommand,
            center.previousTrackCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in self?.playPrevious() }
                return .success
            }
        ))
        remoteCommandHandlers.append((
            center.nextTrackCommand,
            center.nextTrackCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in self?.playNext() }
                return .success
            }
        ))
        remoteCommandHandlers.append((
            center.changePlaybackPositionCommand,
            center.changePlaybackPositionCommand.addTarget {
                [weak self] event in
                guard let event = event
                    as? MPChangePlaybackPositionCommandEvent else {
                    return .commandFailed
                }
                let position = event.positionTime
                Task { @MainActor [weak self] in
                    self?.seek(to: position)
                }
                return .success
            }
        ))
        updateRemoteCommandAvailability()
    }

    private func updateRemoteCommandAvailability() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = canTogglePlayback && !isPlaying
        center.pauseCommand.isEnabled = canTogglePlayback && isPlaying
        center.togglePlayPauseCommand.isEnabled = canTogglePlayback
        center.previousTrackCommand.isEnabled = canPlayPrevious
        center.nextTrackCommand.isEnabled = canPlayNext
        center.changePlaybackPositionCommand.isEnabled =
            canTogglePlayback && duration > 0
    }

    private func loadNowPlayingArtwork(
        for song: NowPlayingSong,
        generation: Int
    ) {
        guard let artworkURL = song.artworkURL else { return }
        if let image = Self.artworkCache.object(
            forKey: artworkURL as NSURL
        ) {
            updateNowPlayingInfo(force: true, artwork: image)
            return
        }

        artworkTask = Task { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(
                    from: artworkURL
                )
                guard let httpResponse = response as? HTTPURLResponse,
                      200..<300 ~= httpResponse.statusCode,
                      let image = UIImage(data: data) else {
                    return
                }
                try Task.checkCancellation()
                guard let self,
                      self.playbackGeneration == generation,
                      self.currentSong?.id == song.id else {
                    return
                }
                Self.artworkCache.setObject(
                    image,
                    forKey: artworkURL as NSURL
                )
                self.updateNowPlayingInfo(force: true, artwork: image)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func updateNowPlayingInfo(
        force: Bool = false,
        artwork: UIImage? = nil
    ) {
        guard let song = currentSong else { return }
        let elapsed = estimatedProgress()
        guard force
                || abs(elapsed - lastNowPlayingInfoProgress) >= 1 else {
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyExternalContentIdentifier: song.id,
        ]
        if !song.album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = song.album
        }
        if duration.isFinite, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artwork = artwork
                ?? song.artworkURL.flatMap({
                    Self.artworkCache.object(forKey: $0 as NSURL)
                }) {
            info[MPMediaItemPropertyArtwork] = Self.makeMediaArtwork(
                from: artwork
            )
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState =
            isPlaying ? .playing : .paused
        lastNowPlayingInfoProgress = elapsed
        updateRemoteCommandAvailability()
    }

    private nonisolated static func makeMediaArtwork(
        from image: UIImage
    ) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private static func normalizedServerURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let candidate = trimmed.contains("://")
            ? trimmed
            : "http://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              let host = components.host?.lowercased() else {
            return trimmed
                .trimmingCharacters(
                    in: CharacterSet(charactersIn: "/")
                )
                .lowercased()
        }
        components.scheme = components.scheme?.lowercased()
        components.host = host
        components.query = nil
        components.fragment = nil
        if components.path == "/" {
            components.path = ""
        } else {
            components.path = components.path.trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
            if !components.path.isEmpty {
                components.path = "/\(components.path)"
            }
        }
        return components.string ?? candidate.lowercased()
    }

    isolated deinit {
        restoreTimeoutTask?.cancel()
        artworkTask?.cancel()
        demoProgressTask?.cancel()
        tearDownPlayer()
        for observer in audioSessionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        for handler in remoteCommandHandlers {
            handler.command.removeTarget(handler.token)
        }
    }
}
