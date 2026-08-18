# NaviLyrics 项目审计与优化迭代规范

> 状态：生效中  
> 基线：`master` / `HEAD`，审计日期 2026-08-18  
> 适用范围：产品设计、架构调整、功能研发、测试、发布和文档维护  
> 文档目标：把已验证的项目事实、风险、优先级和验收标准固化为后续迭代依据

## 1. 文档规则

本文档是 NaviLyrics 的工程与产品改进基线。根目录 `README.md` 面向使用者，本文档面向维护者；当两者描述项目状态不一致时，应先核验代码和可执行结果，再同步更新两份文档。

本文档中的信息分为三类：

- **事实**：可以从源码、工程配置、Git 状态或命令结果直接验证。
- **判断**：基于事实推导出的风险或成熟度结论，必须同时给出证据。
- **规范**：后续变更必须遵循的约束；若需要例外，应在提交或评审记录中说明原因。

更新本文件时，不得把“计划实现”“本地尝试成功”写成“已经支持”。只有进入当前仓库、可以构建，并通过相应验收的能力才能进入已实现列表。

## 2. 产品定义

### 2.1 目标用户

NaviLyrics 当前服务于能够自行维护 Navidrome / OpenSubsonic 音乐库、理解服务器地址和局域网连接的中文 iPhone / iPad 用户。产品定位的直接证据是 [`README.md`](../README.md) 以及登录页手动输入服务器、用户名和密码的流程 [`Features/Authentication/LoginView.swift`](../Features/Authentication/LoginView.swift)。

### 2.2 核心任务

核心用户任务按优先级排序如下：

1. 连接一个可访问的 Navidrome / OpenSubsonic 服务器。
2. 快速找到并播放专辑、歌曲、收藏或歌单。
3. 在前台、后台、锁屏和耳机控制中连续播放。
4. 获得稳定、清晰、可交互的同步歌词体验。
5. 在本机保存播放进度、历史和可解释推荐。

这些任务分别由 `NavidromeSession`、`SubsonicClient`、`PlayerStore`、`NaviLyricsStore`、`AppleMusicLyricsView` 和本机数据 Store 实现。

### 2.3 当前明确不承诺的能力

- 离线音频下载和完整离线音乐库。
- 面向弱网的完整媒体缓存。
- 多服务器、多音源和多账号同时管理。
- 云同步、公共账号体系和社交能力。
- Navidrome 播放列表内部的拖动排序。
- App Store 正式发布质量。

未承诺的能力不得被当作缺陷；但已经暴露给用户的入口必须保持数据正确、安全提示充分、失败状态可理解。

## 3. 审计基线

### 3.1 仓库规模与工程配置

审计命令及结果：

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 跟踪文件 | 74 | `git ls-files \| wc -l` |
| Swift 文件 | 60 | `rg --files -g '*.swift' \| wc -l` |
| Swift 代码行 | 18,479 | `wc -l $(rg --files -g '*.swift')` |
| 测试代码 | 3 个文件、454 行、15 个测试方法 | [`Tests/`](../Tests) |
| Git 历史 | 38 个提交、1 名作者，集中于 2026-08-11 至 2026-08-16 | `git log` |
| 应用版本 | 0.3.0 / build 3 | [`NaviLyrics.xcodeproj/project.pbxproj`](../NaviLyrics.xcodeproj/project.pbxproj) |
| 最低系统 | iOS / iPadOS 18.0 | [`NaviLyrics.xcodeproj/project.pbxproj`](../NaviLyrics.xcodeproj/project.pbxproj) |
| Swift 配置 | Swift 6、Strict Concurrency complete、默认 MainActor | [`NaviLyrics.xcodeproj/project.pbxproj`](../NaviLyrics.xcodeproj/project.pbxproj) |
| 外部运行时依赖 | 未发现 | 源码 import 与 Xcode 工程包引用盘点 |
| CI / 格式 / 覆盖率门禁 | 未发现 | 仓库文件盘点 |

测试代码行比例只能反映测试投入规模，不能等同于语句覆盖率；当前工程没有覆盖率报告或门禁。

### 3.2 2026-08-18 验证结果

| 验证对象 | 结果 | 结论边界 |
| --- | --- | --- |
| `HEAD` 应用 Swift 源码独立类型检查 | 通过 | 仅证明 Swift 类型检查，不包含资源、签名、链接和运行时行为 |
| 当前工作区应用 Swift 源码独立类型检查 | 通过 | 包含当前未提交的两个歌词 `Text` 拼接改动 |
| `NaviLyricsCoreTests.swift` 类型检查 | 失败 | 当前工作区存在未知属性 `@MainActorx` |
| `PersonalizedRecommendationEngineTests.swift` 类型检查 | 失败 | 3 处把 `SubsonicSong` 传给只接受 `NowPlayingSong` 的初始化器；问题已存在于 `HEAD` |
| `PlaybackBehaviorStoreTests.swift` 类型检查 | 通过 | 只代表该测试源文件可编译，不代表测试已运行 |
| `xcodebuild build-for-testing` | 未执行到构建 | 审计机器缺少匹配的 iOS 26.5 Platform / Simulator Runtime，退出码 70 |
| 真实 Navidrome 集成 | 未验证 | 审计环境没有接入真实服务器和真实媒体库 |

不得基于上述结果宣称“所有测试通过”或“真机运行已验证”。完整验证必须在安装匹配 Platform / Simulator Runtime 的 Xcode 上执行。

### 3.3 当前工作区状态

审计时存在三个未提交修改：

- `Features/Player/Lyrics/Shared/LyricRubyTextBuilder.swift`
- `Features/Player/Lyrics/Shared/TimedLyricTextBuilder.swift`
- `Tests/NaviLyricsCoreTests.swift`

前两个文件把字符串插值式 `Text` 拼接改为 `Text + Text`；第三个文件把合法的 `@MainActor` 改成了错误的 `@MainActorx`。后续修复必须区分原有工作区修改和新增修改，避免覆盖未确认的用户工作。

## 4. 多视角审计结论

### 4.1 架构视角

**正面结论**：App、Core、Features、Shared 的目录边界直观；连接、播放、歌词和本机推荐具备各自的核心对象。会话刷新会保留旧内容，播放状态避免持久化完整鉴权 URL，歌词输入有明确上限。证据包括 [`App/NaviLyricsApp.swift`](../App/NaviLyricsApp.swift)、[`Core/Subsonic/NavidromeSession.swift`](../Core/Subsonic/NavidromeSession.swift)、[`Core/Playback/PlayerStore.swift`](../Core/Playback/PlayerStore.swift) 和 [`Core/Lyrics/NaviLyricsStore.swift`](../Core/Lyrics/NaviLyricsStore.swift)。

**风险结论**：七个全局 Store、承担多重职责的 `RootView`、大型 `AppleMusicLyricsView` / `PlayerStore` / `SubsonicClient`，以及直接依赖 `URLSession.shared`，使依赖关系、并发边界和自动化测试成本偏高。证据包括 [`App/RootView.swift`](../App/RootView.swift)、[`Features/Player/Lyrics/AppleMusic/AppleMusicLyricsView.swift`](../Features/Player/Lyrics/AppleMusic/AppleMusicLyricsView.swift) 和 [`Core/Subsonic/SubsonicClient.swift`](../Core/Subsonic/SubsonicClient.swift)。

### 4.2 研发视角

**正面结论**：工程采用 Swift 6、完整并发检查、文件系统同步 Group 和纯 Apple 框架依赖；API 层有类型化错误，主要异步页面具备取消或旧结果保护。证据是 [`NaviLyrics.xcodeproj/project.pbxproj`](../NaviLyrics.xcodeproj/project.pbxproj)、[`Core/Subsonic/SubsonicClient.swift`](../Core/Subsonic/SubsonicClient.swift) 和 [`Features/Library/ContentView.swift`](../Features/Library/ContentView.swift)。

**风险结论**：仓库没有 CI、格式化或覆盖率门禁，发布脚本只构建和打包，不执行测试；测试从已提交版本开始就存在编译错误。38 个提交均来自一名作者且集中在六天内，由此判断当前研发速度快，但质量反馈和知识沉淀不足。证据是 [`build_ios_unsigned.sh`](../build_ios_unsigned.sh)、[`Tests/PersonalizedRecommendationEngineTests.swift`](../Tests/PersonalizedRecommendationEngineTests.swift) 及 Git 历史。

### 4.3 产品视角

**正面结论**：连接 NAS、浏览、搜索、收藏、歌单、连续播放、同步歌词、历史和本机推荐已经形成完整闭环；离线、弱网、多服务器和公共账号等非目标也有明确边界。功能入口可以从 [`App/RootView.swift`](../App/RootView.swift) 和 [`Features/`](../Features) 验证。

**风险结论**：“全部专辑”与实际单次 300 张请求不一致；搜索结果有固定上限；推荐首次生成可能逐专辑串行请求；播放列表搜索失败被转换为空结果。这些问题会让大型音乐库出现功能完整性和性能落差。证据是 [`Core/Subsonic/NavidromeSession.swift`](../Core/Subsonic/NavidromeSession.swift)、[`Core/Subsonic/SubsonicClient.swift`](../Core/Subsonic/SubsonicClient.swift) 和 [`Features/Library/ForYouView.swift`](../Features/Library/ForYouView.swift)。

### 4.4 用户视角

**正面结论**：项目对中文自建音乐库用户的任务聚焦明确；登录、空状态、重试、收藏失败、歌词设置、VoiceOver 和 Reduce Motion 已有实际实现。证据是 [`Features/Authentication/LoginView.swift`](../Features/Authentication/LoginView.swift)、[`Features/Library/FavoritesView.swift`](../Features/Library/FavoritesView.swift)、[`Features/Settings/SettingsView.swift`](../Features/Settings/SettingsView.swift) 和 [`Features/Player/Lyrics/AppleMusic/AppleMusicLyricsView.swift`](../Features/Player/Lyrics/AppleMusic/AppleMusicLyricsView.swift)。

**风险结论**：用户必须理解服务器和网络配置；HTTP 连接存在可感知的安全差异；同一服务器切换账号可能复用旧账号本机数据；UI 尚未本地化；大型音乐库结果被截断时缺乏明确提示。证据是 [`Config/Info.plist`](../Config/Info.plist)、[`Core/Playback/ListeningHistoryStore.swift`](../Core/Playback/ListeningHistoryStore.swift)、[`Core/Library/PersonalizedRecommendationEngine.swift`](../Core/Library/PersonalizedRecommendationEngine.swift) 和 [`Features/Library/ContentView.swift`](../Features/Library/ContentView.swift)。

### 4.5 测试视角

**正面结论**：现有 15 个测试方法已经触及歌词身份、LRC 异常输入、时间线、历史、行为和推荐缓存，不是完全没有回归意识。证据是 [`Tests/`](../Tests)。

**风险结论**：测试 Target 当前不可编译；没有 UI Test Target、网络集成测试、真实服务冒烟自动化、覆盖率和 CI。播放器事件、队列恢复、结构化歌词、账号隔离、网络错误和歌词 UI 是主要空白。工程 Target 定义见 [`NaviLyrics.xcodeproj/project.pbxproj`](../NaviLyrics.xcodeproj/project.pbxproj)。

## 5. 当前架构

```text
NaviLyricsApp
  └─ 注入 AppSettings / Player / Session / History / Behavior / Favorites / RecommendationCache
      └─ RootView
          ├─ LoginView → NavidromeSession → SubsonicClient → Navidrome
          ├─ Library / ForYou / Favorites / Playlists
          ├─ PlayerStore → AVPlayer / MediaPlayer / 本机播放状态
          ├─ 播放事件 → History + Behavior → RecommendationEngine
          └─ 当前歌曲 → NaviLyricsStore → 解析/时间线 → AppleMusicLyricsView
```

### 5.1 已确认的架构优点

- 目录按 App、Core、Features、Shared 和 Tests 分层，职责名称清晰。
- `NavidromeSession` 使用显式连接状态，并在刷新失败时保留已加载内容。
- `PlayerStore` 覆盖后台播放、系统媒体控制、音频中断和播放状态恢复。
- 持久化播放状态不再保存带认证参数的完整媒体 URL。
- 歌词输入有原始字符数、行数、单行 syllable 数和文本缓存上限。
- 生产源码只依赖 Apple 系统框架，部署依赖简单。

### 5.2 已确认的架构风险

- `NaviLyricsApp` 注入七个全局可观察对象，跨模块依赖多为隐式 Environment 依赖。
- `RootView` 同时承担认证路由、导航、播放器呈现、生命周期和播放事件分发。
- `AppleMusicLyricsView`、`PlayerStore`、`SubsonicClient` 和 `PlaylistsView` 体积较大。
- 网络请求直接依赖 `URLSession.shared`，没有可注入 transport。
- 应用默认 MainActor，网络解码、整库聚合和推荐计算存在主线程压力风险。
- 列表封面、播放器封面和播放页背景使用三套加载/缓存路径。

## 6. 问题登记与验收标准

优先级定义：

- **P0**：阻断可信构建、测试或发布。
- **P1**：可能造成用户数据错误、核心功能不完整、明显安全或性能问题。
- **P2**：中期可维护性、体验一致性或扩展性问题。

问题状态只能使用“待处理、进行中、待验证、已完成、已接受风险”。从“待验证”改为“已完成”时，必须记录验证命令、测试结果或人工验收证据。

| ID | 优先级 | 当前状态 | 主题 |
| --- | --- | --- | --- |
| REL-001 | P0 | 待处理 | 测试 Target 无法编译 |
| LIB-001 | P1 | 待处理 | 专辑目录只有最近 300 张 |
| DAT-001 | P1 | 待处理 | 同服务器不同账号共享本机数据 |
| REC-001 | P1 | 待处理 | 推荐整库串行 N+1 请求 |
| SEC-001 | P1，可按部署场景降级 | 待处理 | HTTP 与全局 ATS 放行 |
| PLY-001 | P2 | 待处理 | 演示播放不累计有效播放时间 |
| PLY-002 | P2 | 待处理 | 跳过信号入口不一致 |
| REC-002 | P2 | 待处理 | 推荐多样性上限可被绕过 |
| ARC-001 | P2 | 待处理 | 核心对象职责过度集中 |
| MED-001 | P2 | 待处理 | 封面加载和缓存重复 |
| SEA-001 | P2 | 待处理 | 搜索上限与部分失败不透明 |
| I18N-001 | P2 | 待处理 | UI 文案不可本地化 |

### REL-001：测试 Target 无法编译（P0）

**事实**

- [`Tests/PersonalizedRecommendationEngineTests.swift`](../Tests/PersonalizedRecommendationEngineTests.swift) 使用 `SubsonicSong` 构建行为摘要。
- [`Core/Playback/PlaybackBehaviorStore.swift`](../Core/Playback/PlaybackBehaviorStore.swift) 的对应初始化器只接受 `NowPlayingSong`。
- 当前 [`Tests/NaviLyricsCoreTests.swift`](../Tests/NaviLyricsCoreTests.swift) 包含 `@MainActorx`。

**验收标准**

1. 三个测试文件均能由测试 Target 编译。
2. 在匹配的 iOS Simulator Runtime 上运行 `xcodebuild test`，所有测试通过。
3. CI 对每个合入提交执行相同测试。
4. IPA 构建流程不得绕过失败的测试门禁。

### LIB-001：专辑目录只有最近 300 张（P1）

**事实**

- `NavidromeSession.signIn` 和 `refreshLibrary` 只请求一次 `newest, size: 300`。
- `SubsonicClient.albumList` 没有 `offset` 参数。
- UI 将该数组展示为“全部专辑”。

**验收标准**

1. `getAlbumList2` 支持分页，直到服务器返回空页或不足一页。
2. 301、600、1,000 张专辑的数据集可以完整浏览。
3. 刷新有明确进度、取消和部分失败策略。
4. README 不再把有限结果称为“全部”。

### DAT-001：同服务器不同账号共享本机数据（P1）

**事实**

- 历史、行为、收藏激活状态和推荐缓存只使用规范化服务器 URL。
- “更换服务器或账号”允许用户在同一地址上输入另一个账号。
- 清除记录和退出登录不会清除推荐快照。

**验收标准**

1. 数据空间使用至少 `serverURL + username` 的稳定复合标识。
2. 提供旧版仅服务器键的可解释迁移或明确清理策略。
3. 同服务器两个账号的历史、行为、推荐和恢复队列互不影响。
4. “清除本机记录”明确列出并清除对应的所有本机行为和推荐数据。

### REC-001：推荐整库加载产生串行 N+1 请求（P1）

**事实**

- `ForYouView` 首次推荐会调用 `librarySongs(from: session.albums)`。
- `SubsonicClient.librarySongs` 对每张专辑串行调用 `getAlbum`。
- 当前专辑集合最多 300 张，因此最坏约 300 次串行请求。

**验收标准**

1. 优先评估服务器已有的随机、常听或搜索接口，避免整库逐专辑抓取。
2. 如必须聚合，使用有限并发、取消、进度和请求去重。
3. 100、300、1,000 张专辑下记录请求数、首屏耗时和内存峰值。
4. 网络失败不删除上一份有效推荐。

### SEC-001：HTTP 与全局 ATS 放行（P1，局域网自用场景可降级）

**事实**

- `Config/Info.plist` 设置 `NSAllowsArbitraryLoads = true`。
- Subsonic 用户名、token 和 salt 位于 URL query。
- 产品允许用户输入 HTTP 局域网地址。

**验收标准**

1. 默认文案推荐 HTTPS。
2. 首次连接 HTTP 服务时明确提示局域网窃听和重放风险。
3. 记录为何需要全局 ATS 放行；如系统能力允许，缩小例外范围。
4. 日志、错误和持久化内容不得输出完整鉴权 URL。

### PLY-001：演示播放不累计有效播放时间（P2）

**事实**

- 演示循环只推进 `progress`。
- 有效播放判断读取 `accumulatedPlaybackTime`。
- 该累计值仅由真实 AVPlayer 时间观察器更新。

**验收标准**

1. 演示和真实播放共用同一播放时间累计规则。
2. 演示播放达到阈值后产生一次且仅一次 `.qualified`。
3. 暂停、跳转和重复播放不虚增累计时间。
4. 使用可控时钟编写单元测试，不依赖真实等待 30 秒。

### PLY-002：跳过信号入口不一致（P2）

**事实**

- `playNext()` 发出 `.skipped`。
- `playPrevious()`、`playQueueItem` 和直接加载新队列不会发出相同事件。

**验收标准**

1. 明确定义“主动跳过”的产品规则。
2. 所有换歌入口通过统一状态机决定是否产生 skip。
3. 自动播放完成、失败换歌、短时误触和主动选歌分别有测试。

### REC-002：推荐多样性上限可被第二轮补齐绕过（P2）

**事实**

- 推荐第一轮检查同一艺术家不超过两首。
- 第二轮补齐只检查歌曲 ID，不再检查艺术家计数。

**验收标准**

1. 明确多样性是硬约束还是软约束。
2. 若为硬约束，所有补齐阶段执行同一规则。
3. 增加“所有候选来自同一艺术家”的边界测试。

### ARC-001：核心对象职责过度集中（P2）

**事实**

- `AppleMusicLyricsView` 约 2,659 行、21 个 `@State`、约 50 个私有方法。
- `PlayerStore` 约 1,239 行，同时负责队列、AVPlayer、持久化、系统控制、事件和封面。
- `SubsonicClient` 约 975 行，同时负责认证、所有端点、URL 构造、网络和解码。

**验收标准**

1. 按可测试职责拆分，不以行数拆分为唯一目标。
2. 歌词至少分离滚动协调、焦点/动画状态、行渲染和交互。
3. 播放器至少分离媒体引擎、队列、持久化和系统媒体桥接。
4. 网络至少分离 transport、请求构造和响应映射。

### MED-001：封面加载重复（P2）

**事实**

- `LibraryArtwork`、`PlayerStore` 和 `PlayerView` 分别加载相同封面。
- 前两者分别维护独立 `NSCache`，播放页背景使用 `AsyncImage`。

**验收标准**

1. 使用统一 Artwork Repository。
2. 支持请求去重、取消、像素尺寸限制、解码缩略和内存成本限制。
3. 列表、播放器和锁屏共享缓存策略。

### SEA-001：搜索结果上限与部分失败不透明（P2）

**事实**

- `search3` 固定请求 100 首歌曲、50 张专辑和 50 位艺术家。
- 播放列表请求失败时被转换为空数组。
- 歌单选歌仍调用包含专辑、艺术家和播放列表的完整搜索。

**验收标准**

1. UI 对结果上限或“继续加载”有明确表达。
2. 支持部分成功状态，不把请求失败伪装成零结果。
3. 为歌单选歌提供只搜索歌曲的轻量接口。

### I18N-001：界面文字不可本地化（P2）

**事实**

- UI 文案主要直接写在 Swift 源码中。
- 仓库没有 String Catalog 或 `Localizable.strings`。

**验收标准**

1. 当前中文用户文案进入 String Catalog。
2. 错误信息、辅助功能标签和格式化文本一并迁移。
3. 至少对中文和一种长度明显不同的测试语言做布局检查。

## 7. 研发规范

### 7.1 依赖与状态

- 新增网络能力必须通过可注入 transport；不得继续扩散 `URLSession.shared`。
- 新增持久化数据必须定义作用域：全局、服务器、账号或歌曲，并写入类型或键名。
- 跨模块事件应有明确类型和单一所有者，不使用名称与实际语义不符的事件属性。
- View 不直接承担可独立测试的推荐、网络、持久化或复杂时间线计算。

### 7.2 并发与性能

- `@MainActor` 只保护 UI 状态和确实依赖主线程的系统 API。
- JSON 解码、大数组排序、推荐评分、歌词预处理应评估移出主 Actor。
- 批量网络请求必须设置并发上限、取消、超时和部分失败策略。
- 新增缓存必须包含容量、淘汰、数据作用域和清除策略。

### 7.3 安全与隐私

- 不记录、持久化或显示完整鉴权 URL、密码、token 或 salt。
- 凭据默认进入 Keychain；发生降级存储时必须向用户提示。
- 用户执行退出或清除时，界面文案必须与实际清除范围一致。
- HTTP 支持是兼容能力，不得在文档中描述成与 HTTPS 等价安全。

### 7.4 错误与可观测性

- 网络错误至少保留端点、HTTP 状态、服务端错误码和可理解的用户信息。
- 对登录、首次库加载、推荐加载和播放失败增加隐私安全的结构化日志。
- 不得静默把失败转换成空结果，除非 UI 能区分“无数据”和“部分失败”。

### 7.5 文档同步

以下变化必须同步更新 `README.md` 和本文档：

- 系统/Xcode/服务器要求变化。
- 已实现能力、产品边界或已知限制变化。
- 测试、CI、发布状态变化。
- 账号数据隔离、安全策略和持久化行为变化。
- 问题登记项完成、降级或被新方案替代。

## 8. 测试策略

### 8.1 单元测试最低覆盖面

- URL 规范化、请求参数、认证参数和响应错误映射。
- LRC、结构化歌词、逐字 cue、翻译和罗马音对齐。
- 播放队列、上一首/下一首、跳过、完成、恢复和持久化迁移。
- 历史、行为、推荐缓存的服务器及账号隔离。
- 推荐评分、近期排除、多样性、无信号和缓存失效。
- 超大、空、重复和非有限数值输入。

### 8.2 集成测试最低覆盖面

- 使用 `URLProtocol` 或可注入 transport 模拟 Navidrome 响应。
- 覆盖 ping、登录、分页专辑、搜索部分失败、收藏、歌单和歌词回退。
- 覆盖超时、取消、非 200、服务端错误、JSON 缺字段和超大响应。

### 8.3 UI 测试最低覆盖面

- 首次登录失败和成功。
- 四个一级入口、搜索、播放、歌词和设置主路径。
- VoiceOver 标签、Dynamic Type、Reduce Motion。
- iPhone 竖屏和 iPad 横竖屏。
- 空库、300+ 专辑、长标题和无封面场景。

### 8.4 完成定义

每个功能或修复只有同时满足以下条件才算完成：

- 应用和测试 Target 在干净工作区构建成功。
- 新行为有对应自动化测试；修复缺陷时先增加可复现测试。
- 不降低既有测试覆盖范围。
- 用户可见变化更新 README、空状态、错误或辅助功能文案。
- 涉及网络、缓存或渲染时记录基本性能结果。
- `git diff --check` 通过，提交不包含无关构建产物或用户修改。

## 9. 发布门禁

在标记任何可分发版本前，必须完成：

1. 干净 `HEAD` 执行 Debug Build、Release Build 和 Unit Test。
2. 至少一次真实 Navidrome 冒烟测试：登录、浏览、搜索、播放、歌词、收藏和歌单。
3. iPhone 真机验证后台、锁屏、耳机中断和局域网权限。
4. 核查 HTTP/HTTPS 提示、Keychain 降级和清除数据范围。
5. 检查 README 的版本、限制、测试状态和构建命令。
6. 构建脚本只能在测试门禁成功后生成 IPA。

在 REL-001 完成前，项目状态必须保持“实验性 / 自用开发中”，不得描述为稳定版。

## 10. 推荐实施顺序

### 阶段 0：恢复可信基线

- 完成 REL-001。
- 安装匹配的 Xcode Platform / Simulator Runtime。
- 建立最小 CI：应用构建、单元测试、差异检查。
- 让 IPA 构建依赖测试成功。

### 阶段 1：修复核心正确性

- 完成 LIB-001 和 DAT-001。
- 完成 PLY-001、PLY-002、REC-002。
- 给这些问题补充回归测试。

### 阶段 2：改善网络与性能

- 完成 REC-001、SEA-001、MED-001。
- 引入可注入 transport，迁移网络集成测试。
- 测量大音乐库的请求数、耗时、内存和滚动性能。

### 阶段 3：降低维护成本并扩展用户范围

- 完成 ARC-001、I18N-001。
- 建立 UI 测试和无障碍回归。
- 根据真实需求决定是否扩展离线、弱网或多账号能力。

## 11. 变更记录

- 2026-08-18：依据完整仓库审计创建；登记测试、分页、数据隔离、推荐性能、安全、播放事件、架构、媒体和本地化问题。
