# StereoSync

Mac 播音频，同一 Wi‑Fi 下 iPhone / iPad 近同步同播的 Demo。

## 功能（Phase 1）

- Bonjour 局域网发现（`_stereosync._tcp`）
- TCP 信令 + 分帧音频传输
- NTP 风格时钟校准
- 按统一时间线调度 PCM 播放
- Mac 可选本机同时播放
- 内置测试音调（无需音乐文件）

## 环境要求

- macOS 14+
- iOS / iPadOS 17+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）
- Mac 与手机/平板在同一 Wi‑Fi（勿开 VPN/隔离 AP）

## 快速开始

```bash
git clone <your-repo-url> StereoSync
cd StereoSync
chmod +x scripts/generate-xcode.sh
./scripts/generate-xcode.sh
open StereoSync.xcodeproj
```

1. 选 **Speaker** scheme → 真机运行，点「开始广播」
2. 选 **Host** scheme → My Mac 运行，等待设备出现
3. 点「加载测试音调」或选择音频文件 →「同步播放」

首次运行 iOS 会弹出本地网络权限，请允许。

## 仓库结构

```
StereoSync/
├── Package.swift                 # 共享库 StereoSyncCore
├── Sources/StereoSyncCore/       # 协议 / 发现 / 时钟 / 音频 / 会话
├── Apps/Host/                    # macOS 主机 App
├── Apps/Speaker/                 # iOS 扬声器 App
├── Tests/StereoSyncCoreTests/
├── project.yml                   # XcodeGen 工程描述
└── scripts/generate-xcode.sh
```

## 同步原理（简版）

1. Speaker 广播 Bonjour 服务，Host 连入
2. Host 周期性发送 `clockPing`，Speaker 回 `clockPong`，估 RTT / 时钟偏移
3. Host 下发 `prepareSession` + `startPlayback(hostPlayAt)`
4. 音频切成带 `hostPlayAt` 的 PCM 块发出
5. Speaker 用 `localPlayAt = hostPlayAt + offset`，经 `AVAudioPlayerNode` 精确起播

预期同网延迟大约几十毫秒量级；不保证口型级视频同步或严格左右立体声。

## 已知限制

- 不抓系统音频（先播本地文件 / 测试音调）
- 偏移估计偏简，弱网会漂
- 需在 Apple 设备上用 Xcode 编译（本仓库可在 Linux 编辑，不能在此机跑 App）

## 下一步

- 多 Speaker 并发
- 断线重连与缓冲自适应
- 可选 L/R 分轨实验
- 系统音频捕获（需额外权限方案）
