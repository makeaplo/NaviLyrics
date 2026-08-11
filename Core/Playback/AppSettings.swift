import Foundation
import Observation
import Security
import SwiftUI

// MARK: - 歌词/播放设置（对应 MeloX AppSettings 中被歌词渲染使用的成员）
// 默认值取自 MeloX 的 default* 常量，渲染层只读取这些值。

@MainActor
@Observable
final class AppSettings {
    // MARK: 歌词渲染参数（AppleMusicLyricsView 及其共享组件使用）

    // 静态调参范围（动画用）
    static let lyricsFocusPositionRange = 0.05...0.8
    static let lyricsCurrentLineScaleRange = 1.0...1.5
    static let lyricsFocusScaleBounceRange = 0.0...0.5
    static let lyricsFocusScaleBounceDurationRange = 0.15...0.8
    static let lyricsFocusColorLeadTimeRange = -0.3...0.3
    static let lyricsFocusCascadeChaseSpeedGradientRange = 0.0...1.0
    static let lyricsFocusCascadeBounceRange = 0.0...0.8
    static let lyricsFocusCascadeBounceGradientRange = 0.0...1.0

    // 布局与字体
    var lyricsFontSize: Double = 34.0 {
        didSet { defaults.set(lyricsFontSize, forKey: "lyrics.fontSize") }
    }
    var lyricsFontWeight: LyricsFontWeight = .heavy {
        didSet {
            defaults.set(
                lyricsFontWeight.rawValue,
                forKey: "lyrics.fontWeight"
            )
        }
    }
    var lyricsLineSpacing: Double = 28.0 {
        didSet {
            defaults.set(lyricsLineSpacing, forKey: "lyrics.lineSpacing")
        }
    }
    var lyricsCurrentLineScale: Double = 1.02

    // 高亮与聚焦
    var lyricsFocusPosition: Double = 0.25
    var lyricsFocusSnapThreshold: Double = 0.26
    var lyricsFocusColorLeadTime: Double = 0.0
    var lyricsFocusScaleBounceEnabled: Bool = true
    var lyricsFocusScaleBounce: Double = 0.32
    var lyricsFocusScaleBounceDuration: Double = 0.58

    // 级联动画（Apple Music 式逐行级联）
    var lyricsFocusCascadeDelay: Double = 0.021
    var lyricsFocusCascadeDelayIncrease: Double = 0.005
    var lyricsFocusCascadeFollowingDelay: Double = 0.048
    var lyricsFocusCascadeCatchUpRatio: Double = 0.97
    var lyricsFocusCascadeChaseSpeedGradient: Double = 0.70
    var lyricsFocusCascadeDuration: Double = 0.74
    var lyricsFocusCascadeBounceEnabled: Bool = true
    var lyricsFocusCascadeBounce: Double = 0.26
    var lyricsFocusCascadeBounceGradient: Double = 0.85

    // 模糊与暗化
    var lyricsBlurIntensity: Double = 0.8
    var lyricsDimAmount: Double = 1.0
    var lyricsDistanceBlurScale: Double = 1.05
    var lyricsHiddenInterfaceBlurScale: Double = 0.85
    var lyricsUsesUniformDimmingWhileBrowsing: Bool = true
    var appleMusicLyricsScrollHideThreshold: Double = 200.0

    // 辉光与长音
    var lyricsGlowEnabled: Bool = true {
        didSet {
            defaults.set(lyricsGlowEnabled, forKey: "lyrics.glowEnabled")
        }
    }
    var lyricsGlowIntensity: Double = 1.0
    var lyricsGlowLongSyllablesOnly: Bool = true
    var lyricsLongSyllableDetectionMode: LyricsLongSyllableDetectionMode = .character
    var lyricsLongSyllableDurationThreshold: Double = 0.95
    var lyricsLongToneExpansionAmount: Double = 0.05
    var lyricsHighlightGradientWidth: Double = 0.7
    var lyricsHighlightGradientReduction: Double = 0.65

    // 抬升模式与逐字
    var lyricsLiftMode: LyricsLiftMode = .character
    var lyricsWordByWord: Bool = true {
        didSet {
            defaults.set(lyricsWordByWord, forKey: "lyrics.wordByWord")
        }
    }
    var lyricsPseudoWordByWord: Bool = true {
        didSet {
            defaults.set(
                lyricsPseudoWordByWord,
                forKey: "lyrics.pseudoWordByWord"
            )
        }
    }
    var wordByWordLyricsAdvanceTime: TimeInterval = 0.0 {
        didSet {
            defaults.set(
                wordByWordLyricsAdvanceTime,
                forKey: "lyrics.wordAdvanceTime"
            )
        }
    }
    var effectiveLyricsAdvanceTime: TimeInterval = 0.0 {
        didSet {
            defaults.set(
                effectiveLyricsAdvanceTime,
                forKey: "lyrics.lineAdvanceTime"
            )
        }
    }

    // 翻译与罗马音
    var lyricsTranslationEnabled: Bool = true {
        didSet {
            defaults.set(
                lyricsTranslationEnabled,
                forKey: "lyrics.translationEnabled"
            )
        }
    }
    var lyricsTranslationDisplayMode: LyricsTranslationDisplayMode = .focusedLine {
        didSet {
            defaults.set(
                lyricsTranslationDisplayMode.rawValue,
                forKey: "lyrics.translationDisplayMode"
            )
        }
    }
    var lyricsTranslationFontScale: Double = 0.65
    var lyricsTranslationOpacity: Double = 0.9
    var lyricsRomanizationEnabled: Bool = true {
        didSet {
            defaults.set(
                lyricsRomanizationEnabled,
                forKey: "lyrics.romanizationEnabled"
            )
        }
    }
    var lyricsRomanizationDisplayMode: LyricsTranslationDisplayMode = .focusedLine {
        didSet {
            defaults.set(
                lyricsRomanizationDisplayMode.rawValue,
                forKey: "lyrics.romanizationDisplayMode"
            )
        }
    }
    var lyricsRomanizationFontScale: Double = 0.65
    var lyricsRomanizationOpacity: Double = 0.9

    // 交互
    var lyricsAutoFollow: Bool = true {
        didSet {
            defaults.set(lyricsAutoFollow, forKey: "lyrics.autoFollow")
        }
    }
    var lyricsFollowDelay: Double = 0.35
    var lyricsTapToSeek: Bool = true {
        didSet {
            defaults.set(lyricsTapToSeek, forKey: "lyrics.tapToSeek")
        }
    }
    var lyricsLongPressToShare: Bool = false {
        didSet {
            defaults.set(
                lyricsLongPressToShare,
                forKey: "lyrics.longPressToShare"
            )
        }
    }
    var lyricsInterludeCountdownEnabled: Bool = true {
        didSet {
            defaults.set(
                lyricsInterludeCountdownEnabled,
                forKey: "lyrics.interludeCountdown"
            )
        }
    }
    var lyricsHighFrameRateEnabled: Bool = true {
        didSet {
            defaults.set(
                lyricsHighFrameRateEnabled,
                forKey: "lyrics.highFrameRate"
            )
        }
    }

    // MARK: 服务器

    var serverURL = ""
    var username = ""
    var password = ""
    private(set) var usesInsecureCredentialFallback = false

    // MARK: 持久化

    private let defaults = UserDefaults.standard

    init() {
        load()
        loadLyricsPreferences()
    }

    func save() {
        defaults.set(serverURL, forKey: "serverURL")
        defaults.set(username, forKey: "username")
        if PasswordKeychain.save(password) {
            defaults.removeObject(forKey: "password")
            usesInsecureCredentialFallback = false
        } else {
            // Unsigned simulator builds can reject Keychain access. Retain a
            // compatibility fallback so automatic login never loses an
            // already-saved password.
            defaults.set(password, forKey: "password")
            usesInsecureCredentialFallback = true
        }
    }

    func load() {
        serverURL = defaults.string(forKey: "serverURL") ?? ""
        username = defaults.string(forKey: "username") ?? ""
        if let savedPassword = PasswordKeychain.load() {
            password = savedPassword
            usesInsecureCredentialFallback = false
        } else if let legacyPassword = defaults.string(forKey: "password"),
                  !legacyPassword.isEmpty {
            // Migrate existing installations without asking the user to
            // enter the NAS password again.
            password = legacyPassword
            if PasswordKeychain.save(legacyPassword) {
                defaults.removeObject(forKey: "password")
                usesInsecureCredentialFallback = false
            } else {
                usesInsecureCredentialFallback = true
            }
        } else {
            password = ""
            usesInsecureCredentialFallback = false
        }
    }

    var hasSavedConnection: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    func updateConnection(
        serverURL: String,
        username: String,
        password: String
    ) {
        self.serverURL = serverURL
        self.username = username
        self.password = password
        save()
    }

    func clearConnection() {
        serverURL = ""
        username = ""
        password = ""
        usesInsecureCredentialFallback = false
        defaults.removeObject(forKey: "serverURL")
        defaults.removeObject(forKey: "username")
        defaults.removeObject(forKey: "password")
        PasswordKeychain.delete()
    }

    func resetLyricsPreferences() {
        lyricsFontSize = 34
        lyricsFontWeight = .heavy
        lyricsLineSpacing = 28
        lyricsGlowEnabled = true
        lyricsWordByWord = true
        lyricsPseudoWordByWord = true
        wordByWordLyricsAdvanceTime = 0
        effectiveLyricsAdvanceTime = 0
        lyricsTranslationEnabled = true
        lyricsTranslationDisplayMode = .focusedLine
        lyricsRomanizationEnabled = true
        lyricsRomanizationDisplayMode = .focusedLine
        lyricsAutoFollow = true
        lyricsTapToSeek = true
        lyricsLongPressToShare = false
        lyricsInterludeCountdownEnabled = true
        lyricsHighFrameRateEnabled = true
    }

    /// 逐字歌词和普通逐行歌词可以分别调节提前量。
    func effectiveLyricsAdvanceTime(
        hasSyllableSyncedLyrics: Bool
    ) -> TimeInterval {
        hasSyllableSyncedLyrics
            ? wordByWordLyricsAdvanceTime
            : effectiveLyricsAdvanceTime
    }

    func effectiveLyricsAdvanceTime(
        for lyrics: [LyricLine]
    ) -> TimeInterval {
        effectiveLyricsAdvanceTime(
            hasSyllableSyncedLyrics: lyrics.contains {
                $0.isSyllableSynced
            }
        )
    }

    private func loadLyricsPreferences() {
        if defaults.object(forKey: "lyrics.fontSize") != nil {
            lyricsFontSize = min(
                max(defaults.double(forKey: "lyrics.fontSize"), 24),
                48
            )
        }
        if let rawValue = defaults.string(forKey: "lyrics.fontWeight"),
           let value = LyricsFontWeight(rawValue: rawValue) {
            lyricsFontWeight = value
        }
        if defaults.object(forKey: "lyrics.lineSpacing") != nil {
            lyricsLineSpacing = min(
                max(defaults.double(forKey: "lyrics.lineSpacing"), 12),
                40
            )
        }
        if defaults.object(forKey: "lyrics.wordAdvanceTime") != nil {
            wordByWordLyricsAdvanceTime = min(
                max(defaults.double(forKey: "lyrics.wordAdvanceTime"), -1),
                1
            )
        }
        if defaults.object(forKey: "lyrics.lineAdvanceTime") != nil {
            effectiveLyricsAdvanceTime = min(
                max(defaults.double(forKey: "lyrics.lineAdvanceTime"), -1),
                1
            )
        }
        loadBoolean("lyrics.glowEnabled", into: &lyricsGlowEnabled)
        loadBoolean("lyrics.wordByWord", into: &lyricsWordByWord)
        loadBoolean(
            "lyrics.pseudoWordByWord",
            into: &lyricsPseudoWordByWord
        )
        loadBoolean(
            "lyrics.translationEnabled",
            into: &lyricsTranslationEnabled
        )
        loadBoolean(
            "lyrics.romanizationEnabled",
            into: &lyricsRomanizationEnabled
        )
        loadBoolean("lyrics.autoFollow", into: &lyricsAutoFollow)
        loadBoolean("lyrics.tapToSeek", into: &lyricsTapToSeek)
        loadBoolean(
            "lyrics.longPressToShare",
            into: &lyricsLongPressToShare
        )
        loadBoolean(
            "lyrics.interludeCountdown",
            into: &lyricsInterludeCountdownEnabled
        )
        loadBoolean(
            "lyrics.highFrameRate",
            into: &lyricsHighFrameRateEnabled
        )
        if let rawValue = defaults.string(
            forKey: "lyrics.translationDisplayMode"
        ), let value = LyricsTranslationDisplayMode(rawValue: rawValue) {
            lyricsTranslationDisplayMode = value
        }
        if let rawValue = defaults.string(
            forKey: "lyrics.romanizationDisplayMode"
        ), let value = LyricsTranslationDisplayMode(rawValue: rawValue) {
            lyricsRomanizationDisplayMode = value
        }
    }

    private func loadBoolean(_ key: String, into value: inout Bool) {
        guard defaults.object(forKey: key) != nil else { return }
        value = defaults.bool(forKey: key)
    }
}

private enum PasswordKeychain {
    private static let service = "com.makeapp.NaviLyrics.navidrome"
    private static let account = "saved-password"

    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item)
                == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ password: String) -> Bool {
        #if targetEnvironment(simulator)
        // Simulator builds may not have a stable Keychain access group,
        // especially when installed with simctl. Let AppSettings keep its
        // UserDefaults fallback there; physical devices still use Keychain.
        return false
        #else
        guard let data = password.data(using: .utf8) else { return false }
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        )
        if status == errSecSuccess {
            return true
        }
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] =
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }
        return false
        #endif
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
