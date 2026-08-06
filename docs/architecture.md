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
