# NaviLyrics

NaviLyrics 是一个面向个人使用的原生 iOS / iPadOS Navidrome、OpenSubsonic 音乐播放器，重点提供接近 Apple Music 的同步歌词、连续播放和本机音乐行为体验。

> **项目状态：实验性、自用开发中。** 核心应用源码可以通过 Swift 6 类型检查，主要产品链路已经实现；但当前测试 Target 存在已知编译问题，完整 Xcode 测试尚未通过，因此目前不应视为稳定发布版。

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
| 自动化测试 | 测试 Target 已存在，但当前不能完整编译和运行 |
| 开源许可 | 仓库当前未提供 `LICENSE` 文件 |

最后一次项目状态核验：2026-08-18。状态变化必须同步更新本 README 和[项目审计与优化迭代规范](docs/PROJECT-AUDIT-AND-IMPROVEMENT-SPEC.md)。

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

### 音乐库与搜索

- 首页展示最近加载的专辑和音乐库入口。
- 专辑支持网格/列表布局，以及按最近添加、标题、艺术家和年份排序。
- 支持浏览艺术家及其专辑。
- 搜索同时返回歌曲、专辑、艺术家和播放列表，并支持类型筛选。
- 搜索结果歌曲可以直接播放、收藏或加入队列/歌单。
- 支持查看和同步 Navidrome 收藏歌曲。
- 支持查看、新建、重命名、删除播放列表，以及添加或移除歌曲。

注意：当前专辑目录一次只加载最近 300 张，并不等同于服务器中的完整专辑集合；详见[已知问题](#当前限制和已知问题)。

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
| P0 | 测试 Target 当前无法编译 | 无法证明现有自动化测试通过，也不具备可信发布基线 |
| P1 | 专辑登录/刷新只请求一次最近 300 张 | 超过 300 张专辑时，“专辑目录”和推荐候选不完整 |
| P1 | 历史、行为和推荐缓存只按服务器地址隔离 | 同一服务器切换不同账号时可能复用上一账号的本机数据 |
| P1 | 首次推荐会逐张专辑串行请求曲目 | 大型音乐库中推荐加载可能很慢并产生大量请求 |
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

当前脚本只执行 Release Build、ad-hoc 签名和 IPA 校验，**不会运行单元测试**。在测试门禁修复前，成功生成 IPA 不代表测试通过。

导入、重签和 Xcode 选择说明见 [README-MAC.md](README-MAC.md)。

## 测试状态

工程 Scheme 包含 `NaviLyricsTests` Unit Test Target，共有 3 个测试文件和 15 个测试方法，覆盖部分歌词、历史、行为和推荐逻辑。

截至 2026-08-18：

- `HEAD` 应用 Swift 源码独立类型检查通过。
- 当前工作区应用 Swift 源码独立类型检查通过。
- 推荐测试存在 3 处 `SubsonicSong` / `NowPlayingSong` 类型不匹配，问题已存在于 `HEAD`。
- 当前工作区的核心测试另有一个 `@MainActorx` 拼写错误。
- 行为 Store 测试文件可独立类型检查。
- 审计机器缺少 iOS 26.5 Platform / Simulator Runtime，完整 `xcodebuild test` 未能开始构建。
- 当前没有 UI Test Target、CI 或覆盖率门禁。

在修复已知编译问题并安装匹配 Runtime 后，预期测试命令为：

```bash
xcodebuild \
  -project NaviLyrics.xcodeproj \
  -scheme NaviLyrics \
  -destination 'platform=iOS Simulator,name=<已安装的模拟器>' \
  test
```

不要把普通 App Run、IPA 构建或单个 Swift 文件类型检查当作完整测试通过。

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
- 当前本机数据只按服务器地址而不是服务器+用户名隔离，这是已登记问题。

## 项目文档

- [项目审计与优化迭代规范](docs/PROJECT-AUDIT-AND-IMPROVEMENT-SPEC.md)：客观基线、问题编号、研发规范、测试策略和发布门禁。
- [Mac、真机与 LiveContainer 说明](README-MAC.md)：Xcode 运行、IPA 导入和重签补充说明。

如果准备继续开发，请先处理规范中的 `REL-001`，恢复测试 Target 和可信构建基线；随后依次处理专辑分页、账号数据隔离和推荐请求性能。
