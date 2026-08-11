# NaviLyrics

NaviLyrics 是一个自用的 iOS Navidrome / OpenSubsonic 客户端，重点提供接近 Apple Music 的同步歌词体验。

## 当前可用功能

- 连接局域网或公网 Navidrome 服务器
- 阻断式登录：验证服务器和音乐库成功后才进入主界面
- 浏览最新专辑与专辑曲目
- 搜索歌曲、专辑和艺人
- 同步 Navidrome 的歌曲收藏与取消收藏
- 查看、创建、重命名和删除播放列表，并添加或移除其中的歌曲
- 原格式串流 FLAC、MP3 等音频
- 专辑/播放列表播放、随机播放、播放队列、上一首、下一首及自动切歌
- 迷你播放器、播放进度拖动、封面背景与后台音频
- 播放状态恢复、队列编辑、失败重试、音频中断与耳机拔出处理
- 系统锁屏媒体信息、专辑封面、耳机和控制中心播放控制
- LRC 逐行歌词
- OpenSubsonic 结构化歌词和逐字时间
- 翻译、罗马音、逐字辉光、长音强调、级联滚动和间奏倒计时
- 点击歌词跳转播放位置
- 可持久化的歌词外观、动画、性能和交互设置

## 系统要求

- macOS 上安装 Xcode 26 或更新版本
- iPhone / iPad 使用 iOS 18 或更新版本
- NAS 上运行 Navidrome，并确保手机能够访问服务器地址

## 最快使用方式

项目已经包含可直接打开的 `NaviLyrics.xcodeproj`，不需要再手动新建工程或拖入源码。

1. 用 Xcode 打开 `NaviLyrics.xcodeproj`。
2. 选择 NaviLyrics target → Signing & Capabilities。
3. 选择自己的 Personal Team；如有冲突，可修改 Bundle Identifier。
4. 连接 iPhone，选择该设备并运行。
5. 首次打开后在登录页填写服务器地址、用户名和密码；验证成功后才会进入音乐库。

服务器地址示例：

```text
http://192.168.31.125:4533
https://music.example.com
```

工程已声明本地网络权限，并允许访问使用 HTTP 的局域网服务器。

登录凭据会优先保存在系统 Keychain。极少数不支持 Keychain 的运行环境会回退到本地存储，并在设置页显示安全提示。

## 生成 LiveContainer IPA

如果使用 LiveContainer，可以运行：

```bash
chmod +x build_ios_unsigned.sh
./build_ios_unsigned.sh
```

产物位于：

```text
build/NaviLyrics-iOS18-LiveContainer.ipa
```

如果命令行当前选中的 Xcode 不完整，可以明确指定另一个 Xcode 的 `xcodebuild`：

```bash
XCODEBUILD_BIN=/path/to/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  ./build_ios_unsigned.sh
```

### 导入到 LiveContainer

`.ipa` 不能在 iPhone 的“文件”App 中直接运行；点开只显示分享菜单是正常现象。

1. 打开 LiveContainer，使用右上角的添加/导入按钮选择 IPA；也可以在“文件”的分享菜单里选择 LiveContainer。
2. 导入后长按 NaviLyrics 卡片，进入 Settings，执行 `Force Re-sign App`。
3. 这个 App 是原生 Swift 程序，不需要开启 `Launch with JIT`。
4. 返回 LiveContainer，点 NaviLyrics 卡片启动。

## 歌词说明

NaviLyrics 会优先调用 `getLyricsBySongId` 获取 OpenSubsonic 结构化歌词和逐字时间。如果服务器版本不支持，会自动回退到传统 `getLyrics` 接口读取 LRC 或纯文本歌词。

为了得到最佳效果，建议音乐文件内嵌同步歌词，或者在歌曲旁放置同名 `.lrc` 文件，并让 Navidrome 完成重新扫描。

## 当前限制

- 暂无离线下载和本地缓存
- 播放列表暂不支持拖动排序

这些限制不影响连接 NAS、连续播放专辑和同步歌词这条核心链路。

## 测试

工程包含 `NaviLyricsTests` 测试 target，覆盖重复时间戳歌词、歌词身份稳定性、播放时间线、鉴权 URL 和异常时长等核心回归场景。在安装了匹配 iOS Simulator runtime 的 Xcode 中可直接按 `Command-U` 运行。
