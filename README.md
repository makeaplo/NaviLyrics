# NaviLyrics

NaviLyrics 是一个面向个人使用的原生 iOS / iPadOS Navidrome、OpenSubsonic 音乐播放器，重点提供接近 Apple Music 的同步歌词、连续播放和本机音乐行为体验。

> **项目状态：实验性、自用开发中。** 本机已完成 Xcode 27 / iOS 27 Simulator 的完整单元测试和 iOS Release 构建；远端 CI、真实 Navidrome 和真机验收仍待完成。

- [快速开始](#快速开始)
- [已实现能力](#已实现能力)
- [当前限制和已知问题](#当前限制和已知问题)
- [测试状态](#测试状态)
- [审计与优化规范](docs/PROJECT-AUDIT-AND-IMPROVEMENT-SPEC.md)
- [Mac、真机与 LiveContainer 说明](README-MAC.md)

## 项目概览

| 项目 | 当前状态 |
| --- | --- |
| 当前版本 | `0.3.0`，build `3` |
| 最低系统 | iOS / iPadOS 18.0 |
| 开发环境 | Xcode 26 或更新版本、Swift 6 |
| UI 技术 | SwiftUI、Observation |
| 播放能力 | AVFoundation、MediaPlayer、后台音频 |
| 服务端 | Navidrome / OpenSubsonic，客户端请求 API `1.16.1` |
| 外部运行时依赖 | 无；只使用 Apple 系统框架 |
| 产品语言 | 当前为中文 |
| 项目成熟度 | 实验性、自用开发中 |
| 自动化测试 | 本机完整单元测试与 Release 构建通过；远端 CI 待验证 |
| 开源许可 | 仓库当前未提供 `LICENSE` 文件 |

最后一次项目状态核验：2026-09-21。状态变化必须同步更新本 README 和[项目审计与优化迭代规范](docs/PROJECT-AUDIT-AND-IMPROVEMENT-SPEC.md)。

## 适合什么场景

NaviLyrics 当前适合以下用户：

- 已经在 NAS、家庭服务器或公网服务器上运行 Navidrome。
- 能够提供服务器地址、用户名和密码。
- 主要在家庭局域网或稳定网络中串流自己的音乐库。
- 重视同步歌词、翻译、罗马音和逐字视觉效果。
- 接受项目目前仍处于实验性阶段。

当前不以离线播放器、弱网缓存、多音乐源、多人账号管理、云同步或社交音乐服务为目标。

## 已实现能力

### 连接与账号

- 支持 `http://`、`https://`、域名和局域网 IP 地址。
- 登录时先调用 Subsonic `ping` 验证服务器，再加载音乐库。
- 保存一个当前服务器、用户名和密码，并在下次启动时恢复连接。
- 真机密码优先保存在系统 Keychain。
- Keychain 不可用时回退到本机偏好设置，并在设置页显示安全警告。
- 支持更换服务器或账号、退出登录和清除本机连接信息。
- 历史、行为、推荐缓存、收藏状态和恢复队列按“规范化服务器地址 + 用户名”隔离；用户名区分大小写。
- 更换连接保留各账号自己的记录；清除播放记录同时清除当前账号的历史、偏好和推荐缓存；退出登录还会清除当前账号的恢复队列。

升级说明：旧版只按服务器保存的数据没有账号归属，保留在本机但不自动迁移或显示给任何账号。升级后历史和推荐从当前账号重新积累，旧恢复队列不会自动恢复；服务器上的收藏和歌单不受影响。

### 音乐库与搜索

- 首页展示最近加载的专辑和音乐库入口。
- 专辑支持网格/列表布局，以及按最近添加、标题、艺术家和年份排序。
- 支持浏览艺术家及其专辑。
- 搜索同时返回歌曲、专辑、艺术家和播放列表，并支持类型筛选。
- 搜索结果歌曲可以直接播放、收藏或加入队列/歌单。
- 支持查看和同步 Navidrome 收藏歌曲。
- 支持查看、新建、重命名、删除播放列表，以及添加或移除歌曲。

专辑目录每页读取 300 张，直到服务器返回空页或不足一页。连接和刷新显示已读取数量并支持取消；刷新失败保留上一份完整目录。重复分页会报错，避免无限加载。

### 播放器

- 原格式串流 Navidrome 返回的音频，例如 FLAC、MP3。
- 支持单曲、专辑、歌单、搜索结果和收藏列表播放。
- 支持上一首、下一首、自动切歌、重新播放和进度拖动。
- 支持播放队列查看、删除、拖动排序、清空待播内容和保存为歌单。
- 保存真实服务器的当前队列、歌曲和播放进度，并在下次连接时尝试恢复。
- 支持播放失败提示和重试。
- 支持后台音频、锁屏信息、控制中心和耳机媒体控制。
- 处理系统音频中断和耳机/输出设备断开。
- 提供底部迷你播放器和全屏播放页。

### 同步歌词

歌词加载顺序如下：

1. 优先请求 OpenSubsonic `getLyricsBySongId` 结构化歌词和逐字时间。
2. 服务器不支持时回退到传统 `getLyrics`。
3. 支持逐行 LRC；无法解析时间时按纯文本歌词展示。

歌词界面已支持：

- 根据播放进度自动滚动和高亮当前歌词。
- 结构化逐字高亮、辉光和长音强调。
- 普通逐行歌词的模拟逐字效果。
- 翻译和罗马音，可选择当前行或全部显示。
- 间奏倒计时。
- 点击歌词跳转到对应播放位置。
- 手动滚动后恢复自动跟随。
- 可选的歌词分享入口。
- 字号、字重、行距、时间校准、动画和交互设置。
- VoiceOver 标签、操作提示和“减弱动态效果”适配。

### 本机历史与推荐

- 播放达到有效时长后记录最近播放和播放次数。
- “为你”页面展示继续播放、最近播放、本机常听和推荐。
- 使用收藏、有效播放、完整听完和主动跳过作为本机推荐信号。
- 推荐规则考虑艺术家、专辑、播放次数、完成次数、跳过次数和距上次播放时间。
- 推荐卡片显示可解释理由。
- 行为与推荐数据只保存在本机，不上传到 Navidrome 或第三方服务。

当前推荐是本地启发式规则，不是云端模型、音频相似度模型或协同过滤系统。

### Debug 演示模式

Debug 构建包含一个隐藏的本地演示入口：

1. 打开连接页。
2. 连续轻点 `NaviLyrics` 标题 7 次。
3. 确认进入“开发演示模式”。

演示模式提供本地虚拟专辑、歌曲、歌单和结构化歌词，不连接真实 NAS，也不播放真实音频。它适合查看导航、搜索、队列和歌词 UI，但当前不能完整验证“有效播放记录”链路。

## 当前限制和已知问题

以下内容是当前真实状态，不是未来能力承诺：

| 优先级 | 限制或问题 | 用户影响 |
| --- | --- | --- |
| P0 | `REL-001` 本机完整测试与构建已通过，远端 CI 待验证 | 真实服务器和真机发布验收仍未闭环 |
| P1 | 首次推荐仍需逐专辑聚合曲目，现最多并发 4 个请求 | 已消除串行等待，但请求总量仍随专辑数增长；真实 NAS 耗时和内存待测 |
| P1 | App 允许全局 HTTP 连接 | HTTP 下的 Subsonic 鉴权 query 可能被局域网观察和重放 |
| P2 | 演示播放不累计有效播放时间 | 演示模式不能完整验证最近播放和推荐信号 |
| P2 | 只有部分换歌入口记录主动跳过 | 推荐中的负反馈可能不完整 |
| P2 | 搜索固定请求最多 100 首歌曲、50 张专辑、50 位艺术家 | 大型音乐库的搜索结果可能被截断且没有继续加载 |
| P2 | 播放列表搜索失败会被当成空结果 | 用户无法区分无匹配和部分请求失败 |
| P2 | UI 文案为中文硬编码 | 当前不支持完整本地化 |

产品范围内还明确不支持：

- 离线音频下载和完整本地音乐缓存。
- 面向弱网的复杂缓存与断点恢复。
- 多服务器、多音源或多账号同时管理。
- Navidrome 播放列表内部的拖动排序。
- App Store 正式发布流程。

每项问题的代码证据、验收条件和实施顺序见[项目审计与优化迭代规范](docs/PROJECT-AUDIT-AND-IMPROVEMENT-SPEC.md)。

## 快速开始

### 环境要求

- macOS。
- Xcode 26 或更新版本，并安装与所选 SDK 匹配的 iOS Platform / Simulator Runtime。
- iPhone 或 iPad，系统为 iOS / iPadOS 18.0 或更新版本。
- 一个手机可以访问的 Navidrome / OpenSubsonic 服务器。

项目包含完整的 `NaviLyrics.xcodeproj`，不需要创建新工程或安装依赖。

### 使用 Xcode 运行

1. 用 Xcode 打开 `NaviLyrics.xcodeproj`。
2. 选择 `NaviLyrics` Scheme。
3. 在 NaviLyrics Target 的 Signing & Capabilities 中选择自己的 Apple Developer Team。
4. 如果 Bundle Identifier 冲突，改成自己的唯一标识符。
5. 连接并解锁 iPhone/iPad，选择设备后运行。
6. 首次进入连接页，填写服务器地址、用户名和密码。

服务器地址示例：

```text
http://192.168.31.125:4533
https://music.example.com
```

登录成功要求 `ping` 和初始专辑请求都成功；大型或响应较慢的服务器可能需要等待。家庭 NAS 用户应确认手机与 NAS 网络互通、Navidrome 监听地址允许手机访问，并已允许 App 的本地网络权限。

### 安全建议

优先使用有效 HTTPS。项目为了兼容家庭 NAS 支持 HTTP，但 HTTP 与 HTTPS 不具有相同的传输安全性；Subsonic 请求中的用户名、认证 token 和 salt 位于 URL query，明文网络中的其他设备可能观察或重放这些参数。

## 生成 LiveContainer IPA

仓库提供无签名 Release IPA 构建脚本：

```bash
chmod +x build_ios_unsigned.sh
./build_ios_unsigned.sh
```

默认产物：

```text
build/NaviLyrics-iOS18-LiveContainer.ipa
```

脚本会先在可用的 iOS Simulator 上运行单元测试；只有测试成功，才继续执行 Release Build、ad-hoc 签名和 IPA 校验。没有匹配 Runtime 或测试失败时不会生成新的 IPA。可通过 `TEST_DESTINATION` 指定测试目标。

导入、重签和 Xcode 选择说明见 [README-MAC.md](README-MAC.md)。

## 测试状态

工程 Scheme 包含 `NaviLyricsTests` Unit Test Target，共 5 个文件、29 个测试方法。新增网络 transport 测试替身，覆盖专辑分页、重复页、取消、刷新失败、推荐并发上限、重复 ID、账号切换及队列持久化。

截至 2026-09-21：

- Xcode 27.0（27A266a）配合 iOS 27.0 Simulator 完整执行 29 项单元测试，全部通过；命令和产物见审计文档第 12 节。
- 无签名的 iOS Release 构建通过。
- [`.github/workflows/ci.yml`](.github/workflows/ci.yml) 保留原有配置，本次未推送或验证远端运行。
- 当前没有 UI Test Target 或覆盖率门禁，真实 Navidrome、真机后台播放及弱网性能仍待验收。

在安装匹配 Runtime 的机器上，测试命令为：

```bash
xcodebuild \
  -project NaviLyrics.xcodeproj \
  -scheme NaviLyrics \
  -destination 'platform=iOS Simulator,name=<已安装的模拟器>' \
  test
```

单元测试使用模拟响应，不等同于真实 Navidrome 集成或真机验收。本次未打包或发布 IPA。

## 工程结构

```text
App/                     应用入口、根导航和全局状态装配
Core/Subsonic/           Navidrome/OpenSubsonic 客户端与会话
Core/Playback/           播放器、队列、设置、历史和行为
Core/Lyrics/             歌词模型、解析、时间线和对齐
Core/Library/            收藏与本机推荐
Features/Authentication/ 登录流程
Features/Library/        音乐库、搜索、专辑、艺术家、收藏和歌单
Features/Player/         播放页、队列和同步歌词 UI
Features/Settings/       连接、歌词和本机记录设置
Shared/Components/       封面、歌曲行、收藏按钮等共享组件
Tests/                   Unit Test 源码
Config/Info.plist        网络、后台音频和设备配置
docs/                    审计、规范和后续迭代依据
```

应用入口创建并注入设置、播放器、连接会话、历史、行为、收藏和推荐缓存；`RootView` 根据连接状态切换登录与主界面，并把播放事件传给本机历史和推荐信号。

## 数据与隐私

- 密码真机优先保存在 Keychain；特殊环境可能降级到 UserDefaults，界面会提示。
- 播放历史、行为摘要和推荐快照保存在 UserDefaults。
- 播放状态只持久化歌曲和封面标识，不保存完整鉴权媒体 URL。
- 行为和推荐不会上传到 Navidrome 或第三方服务。
- 本机数据按服务器地址与用户名共同隔离；旧版无账号归属的数据不自动迁移。

## 项目文档

- [项目审计与优化迭代规范](docs/PROJECT-AUDIT-AND-IMPROVEMENT-SPEC.md)：客观基线、问题编号、研发规范、测试策略和发布门禁。
- [Mac、真机与 LiveContainer 说明](README-MAC.md)：Xcode 运行、IPA 导入和重签补充说明。

下一步应验证远端 CI，并在真实 Navidrome 和真机上验收分页、账号切换与推荐耗时；更大范围的架构重构和离线能力另行迭代。
