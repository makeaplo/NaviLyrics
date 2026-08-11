import SwiftUI

struct LyricSharePresentation: Identifiable, Hashable {
    let song: NowPlayingSong
    let lyric: LyricLine

    var id: String {
        "\(song.id)-\(lyric.id)"
    }
}

struct LyricPressInteraction<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    private let content: (Double) -> Content

    @State private var suppressesTap = false
    @State private var feedbackTrigger = 0

    init(
        isSelected: Bool,
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void,
        @ViewBuilder content: @escaping (Double) -> Content
    ) {
        self.isSelected = isSelected
        self.onTap = onTap
        self.onLongPress = onLongPress
        self.content = content
    }

    var body: some View {
        Button(action: performTap) {
            LyricPressLabel(
                content: content
            )
            .contentShape(.rect)
        }
        .buttonStyle(
            LyricPressButtonStyle(
                isSelected: isSelected,
                reducesMotion: accessibilityReduceMotion
            )
        )
        .simultaneousGesture(
            LongPressGesture(
                minimumDuration: 0.48,
                maximumDistance: 18
            )
            .onEnded { didComplete in
                guard didComplete else { return }
                suppressesTap = true
                feedbackTrigger &+= 1
                onLongPress()
            }
        )
        .sensoryFeedback(
            .impact(weight: .medium),
            trigger: feedbackTrigger
        )
        .task(id: suppressesTap) {
            guard suppressesTap else { return }
            do {
                try await Task.sleep(for: .seconds(0.8))
            } catch {
                return
            }
            suppressesTap = false
        }
    }

    private func performTap() {
        guard !suppressesTap else {
            suppressesTap = false
            return
        }
        onTap()
    }
}

private struct LyricPressLabel<Content: View>: View {
    @Environment(\.lyricPressBackgroundProgress)
    private var backgroundProgress

    let content: (Double) -> Content

    var body: some View {
        content(backgroundProgress)
    }
}

private struct LyricPressButtonStyle: ButtonStyle {
    let isSelected: Bool
    let reducesMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        LyricPressButtonStyleBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isSelected: isSelected,
            reducesMotion: reducesMotion
        )
    }
}

private struct LyricPressButtonStyleBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let isSelected: Bool
    let reducesMotion: Bool

    @State private var scale: CGFloat = 1
    @State private var backgroundProgress = 0.0

    var body: some View {
        label
            .environment(
                \.lyricPressBackgroundProgress,
                isSelected ? 1 : backgroundProgress
            )
            .scaleEffect(scale, anchor: .center)
            .onAppear {
                updatePressedState(isPressed, animated: false)
            }
            .onChange(of: isPressed) { _, isPressed in
                updatePressedState(isPressed, animated: true)
            }
            .onChange(of: isSelected) { _, isSelected in
                updateSelectedState(isSelected)
            }
    }

    private func updatePressedState(
        _ isPressed: Bool,
        animated: Bool
    ) {
        guard animated, !reducesMotion else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                scale =
                    isPressed
                        ? LyricPressAnimation.pressedScale
                        : 1
                backgroundProgress =
                    isPressed || isSelected
                        ? 1
                        : 0
            }
            return
        }

        if isPressed {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                backgroundProgress = 1
            }
            withAnimation(
                .easeInOut(
                    duration: LyricPressAnimation.pressDuration
                )
            ) {
                scale = LyricPressAnimation.pressedScale
            }
        } else {
            withAnimation(
                .easeInOut(
                    duration: LyricPressAnimation.releaseDuration
                )
            ) {
                scale = 1
            }
            guard !isSelected else { return }
            withAnimation(
                .easeIn(
                    duration: LyricPressAnimation
                        .backgroundReleaseDuration
                )
            ) {
                backgroundProgress = 0
            }
        }
    }

    private func updateSelectedState(_ isSelected: Bool) {
        if isSelected {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                backgroundProgress = 1
            }
        } else {
            withAnimation(
                reducesMotion
                    ? nil
                    : .easeInOut(
                        duration: LyricPressAnimation.releaseDuration
                    )
            ) {
                scale = 1
            }
            withAnimation(
                reducesMotion
                    ? nil
                    : .easeIn(
                        duration: LyricPressAnimation
                            .backgroundReleaseDuration
                    )
            ) {
                backgroundProgress = 0
            }
        }
    }
}

private enum LyricPressAnimation {
    static let pressedScale: CGFloat = 0.96
    static let pressDuration: TimeInterval = 0.10
    static let releaseDuration: TimeInterval = 0.38
    static let backgroundReleaseDuration: TimeInterval = 0.28
}

private struct LyricPressBackgroundProgressKey: EnvironmentKey {
    static let defaultValue = 0.0
}

private extension EnvironmentValues {
    var lyricPressBackgroundProgress: Double {
        get { self[LyricPressBackgroundProgressKey.self] }
        set { self[LyricPressBackgroundProgressKey.self] = newValue }
    }
}
