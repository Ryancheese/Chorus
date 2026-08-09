package com.chorus.core.protocol

data class DeviceInfo(
    val id: String,
    val name: String,
    val role: DeviceRole,
    val protocolVersion: Int = SyncProtocol.VERSION,
    /** Optional platform hint: ios / android / windows / macos. */
    val platform: String? = null,
    /** Optional hardware model, e.g. "Pixel 8". */
    val model: String? = null,
) {
    val platformLabel: String
        get() = when (platform?.trim()?.lowercase()) {
            "ios" -> "iPhone"
            "ipados" -> "iPad"
            "android" -> "Android"
            "windows" -> "Windows"
            "macos", "mac" -> "Mac"
            else -> if (role == DeviceRole.HOST) "Host" else "Speaker"
        }

    val displayName: String
        get() {
            val trimmed = model?.trim().orEmpty()
            if (trimmed.isEmpty()) return name
            if (name.contains(trimmed, ignoreCase = true)) return name
            return "$name · $trimmed"
        }
}

data class ClockPingData(
    val pingId: String,
    val hostSendTime: Double,
)

data class ClockPongData(
    val pingId: String,
    val hostSendTime: Double,
    val speakerReceiveTime: Double,
    val speakerSendTime: Double,
)

data class PrepareSessionData(
    val sessionId: String,
    val sampleRate: Double,
    val channels: Int,
    val title: String,
)

data class StartPlaybackData(
    val sessionId: String,
    val hostPlayAt: Double,
    val leadTime: Double,
)

data class AudioChunkHeader(
    val sessionId: String,
    val sequence: Long,
    val sampleIndex: Long,
    val sampleCount: Long,
    val hostPlayAt: Double,
)

sealed class ControlPayload {
    abstract val type: MessageType

    data class Hello(val info: DeviceInfo) : ControlPayload() {
        override val type = MessageType.HELLO
    }

    data class Welcome(val info: DeviceInfo) : ControlPayload() {
        override val type = MessageType.WELCOME
    }

    data class ClockPing(val ping: ClockPingData) : ControlPayload() {
        override val type = MessageType.CLOCK_PING
    }

    data class ClockPong(val pong: ClockPongData) : ControlPayload() {
        override val type = MessageType.CLOCK_PONG
    }

    data class PrepareSession(val session: PrepareSessionData) : ControlPayload() {
        override val type = MessageType.PREPARE_SESSION
    }

    data class StartPlayback(val start: StartPlaybackData) : ControlPayload() {
        override val type = MessageType.START_PLAYBACK
    }

    data class StopPlayback(val sessionId: String) : ControlPayload() {
        override val type = MessageType.STOP_PLAYBACK
    }

    data class AudioChannelHello(val deviceId: String) : ControlPayload() {
        override val type = MessageType.AUDIO_CHANNEL_HELLO
    }

    data class StopAcknowledged(val sessionId: String) : ControlPayload() {
        override val type = MessageType.STOP_ACKNOWLEDGED
    }

    data class ClockOffset(val seconds: Double) : ControlPayload() {
        override val type = MessageType.CLOCK_OFFSET
    }

    data class Heartbeat(val deviceId: String) : ControlPayload() {
        override val type = MessageType.HEARTBEAT
    }

    data class Goodbye(val deviceId: String) : ControlPayload() {
        override val type = MessageType.GOODBYE
    }
}
