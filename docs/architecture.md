# 架构说明

## 角色

| 角色 | App | 职责 |
|------|-----|------|
| Host | macOS | 选音频、校准时钟、分包推流、可选本机播放 |
| Speaker | iOS/iPadOS | 广播可发现、收包、按校准时间播放 |

## 连接

```
Speaker: NWListener + Bonjour _stereosync._tcp:17482
Host:    收到 NWConnection 后建立 SyncConnection
```

Host 会向同一个监听端口建立两条 TCP：控制通道只传状态与时钟消息，音频通道只传 PCM 帧。
两条通道都使用 4 字节大端长度前缀分帧；音频通道通过 `audioChannelHello` 完成标识。

## 控制消息

`hello / welcome / audioChannelHello / clockPing / clockPong / prepareSession / startPlayback / stopPlayback / stopAcknowledged / heartbeat / goodbye`

音频帧：`[type=8][headerLen][header JSON][pcm Float32 LE]`

## 时钟

`ClockSynchronizer` 保留最近若干次 ping/pong，取最低 RTT 样本估计：

`offset ≈ speakerMid - hostMid`

Speaker 调度：`localPlayAt = hostPlayAt + offset`

Speaker 会先累积约 800 ms 的连续音频块再开始调度；Host 以 1.2–1.5 秒自适应前置时间发送，以吸收 Wi‑Fi 抖动。

## 系统音频转播

统一延迟模式使用 BlackHole 2ch 作为 macOS 系统默认输出。Host 从 BlackHole 读取 PCM 后，使用同一 `hostPlayAt` 同时输出到 Mac 实体扬声器与 iPhone，避免 Mac 原声直出造成不同步。

开始转播时，Host 自动将 macOS 系统输入与输出切到仅 BlackHole 2ch，并在停止时恢复用户原来的设备。不能使用 Multi-Output Device；Host 输出只指向实体设备，避免回写 BlackHole 形成反馈。该能力需要 macOS 音频输入权限；受 DRM 保护的流媒体若被系统限制采集，将不会被绕过。
