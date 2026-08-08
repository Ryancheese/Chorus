# Chorus

Mac / Windows 播音频，同一 Wi‑Fi 下 iPhone / iPad / Android 近同步同播的 Demo。

## 功能（Phase 1）

- Bonjour / NSD 局域网发现（`_chorus._tcp`）
- TCP 信令 + 分帧音频传输
- NTP 风格时钟校准
- 按统一时间线调度 PCM 播放
- Mac 可选本机同时播放
- 内置测试音调（无需音乐文件）
- Android Speaker（Kotlin / Compose，协议兼容）

## 环境要求

- macOS 14+（Apple Host / iOS Speaker）
- iOS / iPadOS 17+
- Android 8.0+（Android Speaker，见 [`android/`](android/)）
- Xcode 15+（Apple 端）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）
- Android Studio + JDK 17（Android 端）
- 设备与 Host 在同一 Wi‑Fi（勿开 VPN；公司/访客网常有客户端隔离，发现与手动连接都会失败，请改用个人热点或家庭网络）

## 快速开始（Apple）

```bash
git clone <your-repo-url> Chorus
cd Chorus
chmod +x scripts/generate-xcode.sh
./scripts/generate-xcode.sh
open Chorus.xcodeproj
```

1. 选 **Speaker** scheme → 真机运行，点「开始广播」
2. 选 **Host** scheme → My Mac 运行，等待设备出现
3. 点「加载测试音调」或选择音频文件 →「同步播放」

首次运行 iOS 会弹出本地网络权限，请允许。

### Android Speaker

```bash
# 用 Android Studio 打开 android/ 目录，真机运行 app
# 详见 android/README.md
```

1. 安装并打开 **Chorus Speaker**，点「开始广播」
2. 在 Mac Host 或 [Windows ChorusNet Host](../ChorusForWin/ChorusNet) 上发现设备，或手动填手机显示的 `IP:17482`
3. Host 侧同步播放

协议与 Windows `ChorusNet` / Apple `ChorusCore` 字节级兼容。

### 统一转播 Mac 系统声音

此模式会让 Mac 本机与 Speaker 都延迟约 1.2–1.5 秒播放，以换取两端对齐。

1. 安装 BlackHole 2ch：`brew install blackhole-2ch`
2. 不要创建 Multi-Output Device；它会让 Mac 原声立即输出，破坏同步
3. Host 已连接扬声器后，点「统一转播系统声音」

首次使用需允许 Chorus Host 访问音频输入。开始转播时，Chorus 会自动把 macOS 的输入和输出切到 BlackHole；停止时会恢复原先的设备。

受 DRM 保护的流媒体内容可能被 macOS 静音或限制采集；Chorus 不尝试绕过该限制。

## 仓库结构

```
Chorus/
├── Package.swift                 # 共享库 ChorusCore（Apple）
├── Sources/ChorusCore/           # 协议 / 发现 / 时钟 / 音频 / 会话
├── Apps/Host/                    # macOS 主机 App
├── Apps/Speaker/                 # iOS 扬声器 App
├── android/                      # Android Speaker（Kotlin / Compose）
├── Tests/ChorusCoreTests/
├── project.yml                   # XcodeGen 工程描述
└── scripts/generate-xcode.sh
```

## 同步原理（简版）

1. Speaker 广播 Bonjour/NSD 服务，Host 连入
2. Host 周期性发送 `clockPing`，Speaker 回 `clockPong`，估 RTT / 时钟偏移
3. Host 下发 `prepareSession` + `startPlayback(hostPlayAt)`
4. 音频切成带 `hostPlayAt` 的 PCM 块发出
5. Speaker 用 `localPlayAt = hostPlayAt + offset` 精确起播

预期同网延迟大约几十毫秒量级；不保证口型级视频同步或严格左右立体声。

## 已知限制

- 不抓系统音频（先播本地文件 / 测试音调；Mac 统一转播除外）
- 偏移估计偏简，弱网会漂
- Apple 端需在 Apple 设备上用 Xcode 编译；Android 端用 Android Studio

## 下一步

- 多 Speaker 并发
- 断线重连与缓冲自适应
- 可选 L/R 分轨实验
- 系统音频捕获（需额外权限方案）
