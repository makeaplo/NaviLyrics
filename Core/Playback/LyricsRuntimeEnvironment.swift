import Foundation
import SwiftUI

/// TimelineView 使用的歌词刷新率。默认 60 Hz，在高刷新率设备上仍由系统合并实际绘制。
struct LyricsRefreshRate: Equatable, Sendable {
    let framesPerSecond: Int

    var minimumInterval: TimeInterval {
        1.0 / Double(max(framesPerSecond, 1))
    }

    static let standard = LyricsRefreshRate(framesPerSecond: 60)
    static let efficient = LyricsRefreshRate(framesPerSecond: 30)
}

private struct EffectiveLyricsRefreshRateKey: EnvironmentKey {
    static let defaultValue = LyricsRefreshRate.standard
}

extension EnvironmentValues {
    var effectiveLyricsRefreshRate: LyricsRefreshRate {
        get { self[EffectiveLyricsRefreshRateKey.self] }
        set { self[EffectiveLyricsRefreshRateKey.self] = newValue }
    }
}
