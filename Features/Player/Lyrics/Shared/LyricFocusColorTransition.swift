import SwiftUI

struct LyricFocusColorTransition: Equatable, Identifiable {
    let id: UUID
    let initialProgressByID: [LyricLine.ID: CGFloat]
    let destinationLyricID: LyricLine.ID?
    let startedAt: Date
    let duration: TimeInterval

    init(
        id: UUID = UUID(),
        initialProgressByID: [LyricLine.ID: CGFloat],
        destinationLyricID: LyricLine.ID?,
        startedAt: Date,
        duration: TimeInterval
    ) {
        self.id = id
        self.initialProgressByID = initialProgressByID.mapValues {
            Self.unitProgress($0)
        }
        self.destinationLyricID = destinationLyricID
        self.startedAt = startedAt
        self.duration = duration.isFinite ? max(duration, 0) : 0
    }

    var completionDate: Date {
        startedAt.addingTimeInterval(duration)
    }

    func includes(_ lyricID: LyricLine.ID) -> Bool {
        initialProgressByID[lyricID] != nil
            || destinationLyricID == lyricID
    }

    func progress(
        for lyricID: LyricLine.ID,
        at date: Date
    ) -> CGFloat {
        let initialProgress = initialProgressByID[lyricID, default: 0]
        let destinationProgress: CGFloat =
            destinationLyricID == lyricID ? 1 : 0
        let progress = easedProgress(at: date)
        return Self.unitProgress(
            initialProgress
                + (destinationProgress - initialProgress) * progress
        )
    }

    func presentationProgressByID(
        at date: Date
    ) -> [LyricLine.ID: CGFloat] {
        var lyricIDs = Set(initialProgressByID.keys)
        if let destinationLyricID {
            lyricIDs.insert(destinationLyricID)
        }
        return lyricIDs.reduce(into: [:]) { progressByID, lyricID in
            let progress = progress(for: lyricID, at: date)
            if progress > 0 {
                progressByID[lyricID] = progress
            }
        }
    }

    private func easedProgress(at date: Date) -> CGFloat {
        guard duration > 0 else { return 1 }
        let linearProgress = Self.unitProgress(
            CGFloat(date.timeIntervalSince(startedAt) / duration)
        )
        return linearProgress * linearProgress
            * (3 - 2 * linearProgress)
    }

    private static func unitProgress(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

struct LifecycleAwareLyricFocusColor<Content: View>: View {
    let lyricID: LyricLine.ID
    let focusedLyricID: LyricLine.ID?
    let transition: LyricFocusColorTransition?
    @ViewBuilder let content: (CGFloat) -> Content

    init(
        lyricID: LyricLine.ID,
        focusedLyricID: LyricLine.ID?,
        transition: LyricFocusColorTransition?,
        @ViewBuilder content: @escaping (CGFloat) -> Content
    ) {
        self.lyricID = lyricID
        self.focusedLyricID = focusedLyricID
        self.transition = transition
        self.content = content
    }

    var body: some View {
        // Keep the same container mounted so the lyric's scale animation
        // retains its identity while color timing starts and stops.
        TimelineView(
            .animation(paused: !isTransitioning)
        ) { context in
            content(focusProgress(at: context.date))
        }
    }

    private var isTransitioning: Bool {
        transition?.includes(lyricID) == true
    }

    private func focusProgress(at date: Date) -> CGFloat {
        guard let transition, transition.includes(lyricID) else {
            return lyricID == focusedLyricID ? 1 : 0
        }
        return transition.progress(for: lyricID, at: date)
    }
}
