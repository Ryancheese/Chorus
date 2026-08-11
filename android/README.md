# Chorus Speaker（Android）

局域网扬声器端：广播 `_chorus._tcp:17482`，接受 Mac / Windows Host 的双路 TCP，校准时钟后近同步播放 PCM。

协议与 [Windows ChorusNet](../../ChorusForWin/ChorusNet) / Apple `ChorusCore` **字节级兼容**。

## 下载安装包

预编译 APK：

- [ChorusSpeaker-1.0.5.apk](https://github.com/Ryancheese/Chorus/releases/download/android-v1.0.5/ChorusSpeaker-1.0.5.apk)

手机下载后直接安装；若系统拦截，允许「未知来源」。与 Host 同一 Wi‑Fi，关闭 VPN。

## 环境

- Android Studio Ladybug+（或兼容 AGP 8.7 的版本）
- JDK 17
- Android SDK 35
- 真机建议 Android 8.0+（minSdk 26）

## 打开与运行

```bash
cd android
# 若尚无 local.properties，由 Android Studio 自动生成，或：
# copy local.properties.example local.properties 并填写 sdk.dir
```

1. 用 Android Studio 打开 `android/` 目录
2. Sync Gradle → 选真机 → Run `app`
3. 点「开始广播」，允许通知权限（Android 13+）
4. 在 Mac Host 或 Windows Chorus Host 上发现设备，或手动填手机显示的 `IP:17482`
5. Host 侧播放测试音调 / 音频文件

请与 Host 同一 Wi‑Fi，关闭 VPN；公司/访客网常有客户端隔离，请改用个人热点。

## 模块

```
android/
├── app/                 # Compose UI + 前台 Service + SpeakerSession + NSD
└── core/
    ├── protocol/        # 常量 / DTO / FrameIO / MessageCodec
    ├── network/         # SyncConnection / SpeakerListener / LocalAddress
    ├── sync/            # HostTime / ClockSynchronizer / JitterBuffer
    └── audio/           # SyncAudioPlayer（AudioTrack）
```

## 协议单测（无需设备）

```bash
cd android
./gradlew :core:protocol:test :core:sync:test
```

## 联调检查

本机已跑通协议/jitter 单测：`./gradlew :core:protocol:test :core:sync:test`。

真机联调（需 Android Studio / SDK）：

- [ ] Host 列表出现 Android Speaker，或手动 IP 可连
- [ ] hello/welcome 后状态变为就绪，时钟偏移有数值
- [ ] 测试音调两端可闻、大致对齐（Mac Host 与 Windows Host 各一次）
- [ ] 停止播放后可再次起播；停止广播后通知消失
