import Foundation
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(NavidromeSession.self) private var session
    @Environment(PlayerStore.self) private var player
    @Environment(ListeningHistoryStore.self) private var history
    @Environment(\.dismiss) private var dismiss
    @State private var showSignOutConfirmation = false
    @State private var showResetConfirmation = false
    @State private var showHistoryClearConfirmation = false

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                connectionSection

                Section("歌词外观") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent(
                            "字号",
                            value: "\(Int(settings.lyricsFontSize)) pt"
                        )
                        Slider(
                            value: $settings.lyricsFontSize,
                            in: 24...48,
                            step: 1
                        )
                        .accessibilityLabel("歌词字号")
                    }

                    Picker(
                        "字重",
                        selection: $settings.lyricsFontWeight
                    ) {
                        ForEach(LyricsFontWeight.allCases) { weight in
                            Text(weight.title).tag(weight)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent(
                            "行间距",
                            value: "\(Int(settings.lyricsLineSpacing)) pt"
                        )
                        Slider(
                            value: $settings.lyricsLineSpacing,
                            in: 12...40,
                            step: 1
                        )
                        .accessibilityLabel("歌词行间距")
                    }
                }

                Section("歌词内容") {
                    Toggle(
                        "显示翻译",
                        isOn: $settings.lyricsTranslationEnabled
                    )
                    if settings.lyricsTranslationEnabled {
                        Picker(
                            "翻译显示",
                            selection:
                                $settings.lyricsTranslationDisplayMode
                        ) {
                            ForEach(
                                LyricsTranslationDisplayMode.allCases
                            ) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                    }

                    Toggle(
                        "显示罗马音",
                        isOn: $settings.lyricsRomanizationEnabled
                    )
                    if settings.lyricsRomanizationEnabled {
                        Picker(
                            "罗马音显示",
                            selection:
                                $settings.lyricsRomanizationDisplayMode
                        ) {
                            ForEach(
                                LyricsTranslationDisplayMode.allCases
                            ) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                    }
                }

                Section {
                    timingSlider(
                        title: "逐行歌词",
                        value: $settings.effectiveLyricsAdvanceTime
                    )
                    timingSlider(
                        title: "逐字歌词",
                        value: $settings.wordByWordLyricsAdvanceTime
                    )
                } header: {
                    Text("歌词同步")
                } footer: {
                    Text("正值会让高亮更早出现，负值会让高亮更晚出现。")
                }

                Section {
                    Toggle(
                        "逐字高亮",
                        isOn: $settings.lyricsWordByWord
                    )
                    Toggle(
                        "普通歌词模拟逐字",
                        isOn: $settings.lyricsPseudoWordByWord
                    )
                    .disabled(!settings.lyricsWordByWord)
                    Toggle(
                        "歌词辉光",
                        isOn: $settings.lyricsGlowEnabled
                    )
                    Toggle(
                        "间奏倒计时",
                        isOn: $settings.lyricsInterludeCountdownEnabled
                    )
                    Toggle(
                        "高帧率动画",
                        isOn: $settings.lyricsHighFrameRateEnabled
                    )
                } header: {
                    Text("动画与性能")
                } footer: {
                    Text(
                        "关闭高帧率后歌词动画以 30 帧刷新，可降低旧设备的发热与内存压力。"
                    )
                }

                Section("歌词交互") {
                    Toggle(
                        "滚动后自动跟随播放",
                        isOn: $settings.lyricsAutoFollow
                    )
                    Toggle(
                        "点击歌词跳转",
                        isOn: $settings.lyricsTapToSeek
                    )
                    Toggle(
                        "长按歌词分享",
                        isOn: $settings.lyricsLongPressToShare
                    )
                }

                Section {
                    Button("恢复默认歌词设置") {
                        showResetConfirmation = true
                    }
                }

                historySection

                accountActionsSection
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog(
                "恢复默认歌词设置？",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("恢复默认设置", role: .destructive) {
                    settings.resetLyricsPreferences()
                }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog(
                session.isDemoMode ? "退出开发演示？" : "退出当前音乐库？",
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    session.isDemoMode ? "退出演示" : "退出并清除账号",
                    role: .destructive
                ) {
                    history.clearCurrentServerHistory()
                    if session.isDemoMode {
                        player.reset()
                        session.requireSignIn()
                    } else {
                        player.reset(clearsPersistedState: true)
                        session.signOut(settings: settings)
                    }
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(
                    session.isDemoMode
                        ? "将返回连接页，已保存的真实服务器账号不会被清除。"
                        : "之后必须重新验证服务器才能使用 NaviLyrics。"
                )
            }
            .confirmationDialog(
                "清除本机播放记录？",
                isPresented: $showHistoryClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("清除播放记录", role: .destructive) {
                    history.clearCurrentServerHistory()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这只会清除当前 Navidrome 服务器在本机的播放记录。")
            }
        }
    }

    private var connectionSection: some View {
        Section("当前音乐库") {
            if session.isDemoMode {
                Label("开发演示模式", systemImage: "hammer.fill")
                    .foregroundStyle(.orange)
                Text("当前使用本地虚拟音乐库，不连接 NAS，不会修改真实服务器数据。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("服务器") {
                Text(
                    session.isDemoMode
                        ? "本地演示数据"
                        : settings.serverURL
                )
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            if !session.isDemoMode {
                LabeledContent("用户名", value: settings.username)
                Label("连接正常", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if !session.isDemoMode,
               settings.usesInsecureCredentialFallback {
                Label(
                    "当前安装环境无法使用钥匙串，密码仅保存在本机偏好设置中",
                    systemImage: "exclamationmark.shield.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
        }
    }

    private var historySection: some View {
        Section {
            LabeledContent("已记录歌曲", value: historyCountText)
            Button("清除本机播放记录", role: .destructive) {
                showHistoryClearConfirmation = true
            }
            .disabled(history.items.isEmpty)
        } header: {
            Text("本机播放记录")
        } footer: {
            Text("播放记录只保存在本机，不会上传到 Navidrome。")
        }
    }

    private var historyCountText: String {
        String(history.items.count) + " 首"
    }

    private func timingSlider(
        title: String,
        value: Binding<TimeInterval>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(
                title,
                value: String(format: "%+.2f 秒", value.wrappedValue)
            )
            Slider(value: value, in: -1...1, step: 0.05)
                .accessibilityLabel("\(title)时间校准")
                .accessibilityValue(
                    String(format: "%+.2f 秒", value.wrappedValue)
                )
        }
    }

    private var accountActionsSection: some View {
        Section {
            Button("更换服务器或账号") {
                player.reset()
                session.requireSignIn()
                dismiss()
            }

            Button("退出登录", role: .destructive) {
                showSignOutConfirmation = true
            }
        } footer: {
            Text(
                session.isDemoMode
                    ? "演示数据只保存在本次运行中；退出演示不会清除已保存的真实连接。"
                    : "更换连接会返回登录页并保留当前内容供修改；退出登录会清除账号与播放记录。"
            )
        }
    }
}
