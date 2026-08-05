# 架构说明

## 角色

| 角色 | App | 职责 |
|------|-----|------|
| Host | macOS | 选音频、校准时钟、分包推流、可选本机播放 |
| Speaker | iOS/iPadOS | 广播可发现、收包、按校准时间播放 |

## 连接

```
Speaker: NWListener + Bonjour _stereosync._tcp:74821
Host:    收到 NWConnection 后建立 SyncConnection
```

所有控制消息与音频帧共用一条 TCP，使用 4 字节大端长度前缀分帧。

## 控制消息

`hello / welcome / clockPing / clockPong / prepareSession / startPlayback / stopPlayback / heartbeat / goodbye`

音频帧：`[type=8][headerLen][header JSON][pcm Float32 LE]`

## 时钟

`ClockSynchronizer` 保留最近若干次 ping/pong，取最低 RTT 样本估计：

`offset ≈ speakerMid - hostMid`

Speaker 调度：`localPlayAt = hostPlayAt + offset`
