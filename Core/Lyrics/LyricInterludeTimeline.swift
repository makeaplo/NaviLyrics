import Foundation

struct LyricInterlude: Identifiable, Hashable {
    let startTime: TimeInterval
    let countdownEndTime: TimeInterval
    let followingLyricTime: TimeInterval
    let precedingLyricID: LyricLine.ID?
    let followingLyricID: LyricLine.ID
    let displayBeforeLyricID: LyricLine.ID

    var id: String {
        "lyric-interlude-\(startTime)-\(displayBeforeLyricID)-\(followingLyricID)"
    }

    var isPrelude: Bool {
        precedingLyricID == nil
    }
}

struct LyricInterludePlaybackPosition: Equatable {
    let activeInterludeID: LyricInterlude.ID?
    let nextTransitionTime: TimeInterval?
}

enum LyricInterludeTimeline {
    /// Apple Music leaves a short visual handoff before the following lyric.
    static let lyricHandoffDuration: TimeInterval = 0.25

    /// Short pauses should remain ordinary lyric spacing instead of looking
    /// like a loading state.
    static let minimumCountdownDuration: TimeInterval = 4

    private static let focusHandoffGraceDuration: TimeInterval = 0.5

    static func interludes(in lyrics: [LyricLine]) -> [LyricInterlude] {
        guard let firstLyric = lyrics.first else { return [] }

        var result: [LyricInterlude] = []
        // NetEase YRC can prepend untimed credit rows at t=0. Treat the
        // first precisely timed lyric as the musical entrance so those rows
        // cannot suppress an otherwise valid intro countdown.
        let firstMusicalLyric = lyrics.first {
            preciseEndTime(for: $0) != nil
        } ?? firstLyric
        if let prelude = makeInterlude(
            startTime: 0,
            precedingLyricID: nil,
            followingLyric: firstMusicalLyric,
            displayBeforeLyricID: firstLyric.id
        ) {
            result.append(prelude)
        }

        guard lyrics.count > 1 else { return result }
        for followingIndex in lyrics.indices.dropFirst() {
            let precedingIndex = lyrics.index(before: followingIndex)
            let precedingLyric = lyrics[precedingIndex]
            let followingLyric = lyrics[followingIndex]
            guard let precedingEndTime = preciseEndTime(
                for: precedingLyric
            ), let interlude = makeInterlude(
                startTime: precedingEndTime,
                precedingLyricID: precedingLyric.id,
                followingLyric: followingLyric,
                displayBeforeLyricID: followingLyric.id
            ) else {
                continue
            }
            result.append(interlude)
        }
        return result
    }

    static func position(
        at playbackTime: TimeInterval,
        in interludes: [LyricInterlude]
    ) -> LyricInterludePlaybackPosition {
        guard playbackTime.isFinite else {
            return LyricInterludePlaybackPosition(
                activeInterludeID: nil,
                nextTransitionTime: nil
            )
        }

        for interlude in interludes {
            if playbackTime < interlude.startTime {
                return LyricInterludePlaybackPosition(
                    activeInterludeID: nil,
                    nextTransitionTime: interlude.startTime
                )
            }

            let focusEndTime = interlude.followingLyricTime
                + focusHandoffGraceDuration
            if playbackTime < focusEndTime {
                return LyricInterludePlaybackPosition(
                    activeInterludeID: interlude.id,
                    nextTransitionTime: focusEndTime
                )
            }
        }

        return LyricInterludePlaybackPosition(
            activeInterludeID: nil,
            nextTransitionTime: nil
        )
    }

    private static func makeInterlude(
        startTime: TimeInterval,
        precedingLyricID: LyricLine.ID?,
        followingLyric: LyricLine,
        displayBeforeLyricID: LyricLine.ID
    ) -> LyricInterlude? {
        guard startTime.isFinite,
              followingLyric.time.isFinite else {
            return nil
        }

        let countdownEndTime = max(
            startTime,
            followingLyric.time - lyricHandoffDuration
        )
        guard countdownEndTime - startTime
                >= minimumCountdownDuration else {
            return nil
        }

        return LyricInterlude(
            startTime: startTime,
            countdownEndTime: countdownEndTime,
            followingLyricTime: followingLyric.time,
            precedingLyricID: precedingLyricID,
            followingLyricID: followingLyric.id,
            displayBeforeLyricID: displayBeforeLyricID
        )
    }

    private static func preciseEndTime(
        for lyric: LyricLine
    ) -> TimeInterval? {
        let durationEndTime: TimeInterval? = lyric.duration.flatMap {
            duration -> TimeInterval? in
            guard duration.isFinite, duration > 0 else { return nil }
            return lyric.time + duration
        }
        let syllableEndTime = lyric.syllables
            .lazy
            .map(\.endTime)
            .filter(\.isFinite)
            .max()

        return [durationEndTime, syllableEndTime]
            .compactMap { $0 }
            .max()
    }
}
