import Foundation
import Observation

// MARK: - 歌词加载器（对接 Subsonic 数据源 → MeloX LyricLine 模型）

@MainActor
@Observable
final class NaviLyricsStore {
    private static let maximumLyricLineCount = 2_000
    private static let maximumSyllableCountPerLine = 1_000
    private static let maximumRawLyricCharacterCount = 2_000_000

    private(set) var lyrics: [LyricLine] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let client: SubsonicClient

    init(client: SubsonicClient) {
        self.client = client
    }

    func load(for song: NowPlayingSong) async {
        isLoading = true
        lyrics = []
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let result = try await client.lyrics(
                songID: song.id,
                artist: song.artist,
                title: song.title
            ) else {
                errorMessage = "当前歌曲暂无歌词"
                return
            }
            try Task.checkCancellation()
            let loadedLyrics: [LyricLine]
            switch result {
            case let .text(raw):
                let safeRaw = String(
                    raw.prefix(Self.maximumRawLyricCharacterCount)
                )
                let parsedLyrics = LyricParser.parseLRC(safeRaw)
                if parsedLyrics.isEmpty {
                    loadedLyrics = makeUntimedLyrics(
                        from: safeRaw,
                        songDuration: song.duration
                    )
                } else {
                    loadedLyrics = parsedLyrics
                }
            case let .structured(tracks):
                loadedLyrics = makeStructuredLyrics(
                    from: tracks,
                    songDuration: song.duration
                )
            }
            try Task.checkCancellation()
            lyrics = Array(
                loadedLyrics.prefix(Self.maximumLyricLineCount)
            )
            errorMessage = lyrics.isEmpty ? "歌词解析失败" : nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "歌词获取失败：\(error.localizedDescription)"
        }
    }

    private func makeStructuredLyrics(
        from tracks: [SubsonicStructuredLyrics],
        songDuration: TimeInterval
    ) -> [LyricLine] {
        guard let mainTrack = tracks.first(where: {
            let kind = $0.kind?.lowercased()
            return kind == nil || kind == "main"
        }) ?? tracks.first else {
            return []
        }

        var lines = lyricLines(
            from: mainTrack,
            songDuration: songDuration
        )
        guard !lines.isEmpty else { return [] }

        if let translation = tracks.first(where: {
            $0.kind?.lowercased() == "translation"
        }) {
            lines = attach(
                lyricLines(from: translation, songDuration: songDuration),
                to: lines,
                asRomanization: false
            )
        }

        if let romanization = tracks.first(where: {
            let kind = $0.kind?.lowercased()
            return kind == "pronunciation" || kind == "romanization"
        }) {
            lines = attach(
                lyricLines(from: romanization, songDuration: songDuration),
                to: lines,
                asRomanization: true
            )
        }
        return lines
    }

    private func lyricLines(
        from track: SubsonicStructuredLyrics,
        songDuration: TimeInterval
    ) -> [LyricLine] {
        if let cueLines = track.cueLine, !cueLines.isEmpty {
            let sorted = Array(
                cueLines
                    .sorted { $0.start < $1.start }
                    .prefix(Self.maximumLyricLineCount)
            )
            return sorted.enumerated().map { index, cueLine in
                let startTime = TimeInterval(cueLine.start) / 1_000
                let nextStart = index + 1 < sorted.count
                    ? TimeInterval(sorted[index + 1].start) / 1_000
                    : nil
                let explicitEnd = cueLine.end.map { TimeInterval($0) / 1_000 }
                let endTime = explicitEnd ?? nextStart
                    ?? max(songDuration, startTime + 2)
                let syllables = (cueLine.cue ?? [])
                    .prefix(Self.maximumSyllableCountPerLine)
                    .compactMap {
                    cue -> LyricSyllable? in
                    let start = TimeInterval(cue.start) / 1_000
                    let end = TimeInterval(cue.end) / 1_000
                    guard end >= start, !cue.value.isEmpty else { return nil }
                    return LyricSyllable(
                        text: cue.value,
                        startTime: start,
                        endTime: end
                    )
                }
                let text = cueLine.value.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                let resolvedText = text.isEmpty
                    ? syllables.map(\.text).joined()
                    : text
                return LyricLine(
                    time: startTime,
                    duration: max(endTime - startTime, 0.05),
                    text: resolvedText,
                    syllables: syllables
                )
            }
        }

        let timedLines = (track.line ?? [])
            .compactMap { line -> (Int, String)? in
                guard let start = line.start,
                      !line.value.trimmingCharacters(
                        in: .whitespacesAndNewlines
                      ).isEmpty else {
                    return nil
                }
                return (start, line.value)
            }
            .sorted { $0.0 < $1.0 }
            .prefix(Self.maximumLyricLineCount)
        let safeTimedLines = Array(timedLines)
        if !safeTimedLines.isEmpty {
            return safeTimedLines.enumerated().map { index, item in
                let start = TimeInterval(item.0) / 1_000
                let end = index + 1 < safeTimedLines.count
                    ? TimeInterval(safeTimedLines[index + 1].0) / 1_000
                    : max(songDuration, start + 2)
                return LyricLine(
                    time: start,
                    duration: max(end - start, 0.05),
                    text: item.1
                )
            }
        }

        let text = (track.line ?? []).map(\.value).joined(separator: "\n")
        return makeUntimedLyrics(from: text, songDuration: songDuration)
    }

    private func attach(
        _ secondaryLines: [LyricLine],
        to primaryLines: [LyricLine],
        asRomanization: Bool
    ) -> [LyricLine] {
        guard !secondaryLines.isEmpty else { return primaryLines }
        let sortedSecondaryLines = secondaryLines.sorted {
            $0.time < $1.time
        }
        var secondaryIndex = 0
        return primaryLines.map { line in
            while secondaryIndex + 1 < sortedSecondaryLines.count,
                  abs(sortedSecondaryLines[secondaryIndex + 1].time - line.time)
                    < abs(sortedSecondaryLines[secondaryIndex].time - line.time) {
                secondaryIndex += 1
            }
            let secondary = sortedSecondaryLines[secondaryIndex]
            guard abs(secondary.time - line.time) <= 0.8 else {
                return line
            }
            if asRomanization {
                return line.attachingRomanization(
                    secondary.text,
                    romanizationSyllables: secondary.syllables
                )
            }
            return line.attachingTranslation(secondary.text)
        }
    }

    private func makeUntimedLyrics(
        from raw: String,
        songDuration: TimeInterval
    ) -> [LyricLine] {
        let rows = raw
            .split(whereSeparator: \Character.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(Self.maximumLyricLineCount)
        let safeRows = Array(rows)
        guard !safeRows.isEmpty else { return [] }

        // 无时间歌词先均匀铺到歌曲时间轴上，保证可以阅读；不会生成逐字高亮。
        let safeSongDuration = songDuration.isFinite
            ? max(songDuration, 0)
            : 0
        let availableDuration = max(
            safeSongDuration,
            Double(safeRows.count) * 3
        )
        let lineDuration = availableDuration / Double(safeRows.count)
        return safeRows.enumerated().map { index, text in
            LyricLine(
                time: Double(index) * lineDuration,
                duration: lineDuration,
                text: text
            )
        }
    }
}
