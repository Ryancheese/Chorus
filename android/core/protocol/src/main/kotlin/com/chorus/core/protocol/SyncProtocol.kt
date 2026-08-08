package com.chorus.core.protocol

/** Bonjour/mDNS service parameters — must match Mac / Windows ChorusCore. */
object SyncBonjour {
    const val TYPE = "_chorus._tcp"
    const val DOMAIN = "local."
    const val CONTROL_PORT: Int = 17_482
}

/** Wire protocol constants. Bump [VERSION] when message layout changes. */
object SyncProtocol {
    const val VERSION: Int = 1
    const val DEFAULT_LEAD_TIME: Double = 1.2
    const val SAMPLE_RATE: Double = 44_100.0
    const val CHANNELS: Int = 1
    const val BYTES_PER_SAMPLE: Int = 4
}

enum class MessageType(val code: Int) {
    HELLO(1),
    WELCOME(2),
    CLOCK_PING(3),
    CLOCK_PONG(4),
    PREPARE_SESSION(5),
    START_PLAYBACK(6),
    STOP_PLAYBACK(7),
    AUDIO_CHUNK(8),
    HEARTBEAT(9),
    GOODBYE(10),
    AUDIO_CHANNEL_HELLO(11),
    STOP_ACKNOWLEDGED(12),
    CLOCK_OFFSET(13);

    companion object {
        fun fromCode(code: Int): MessageType =
            entries.firstOrNull { it.code == code }
                ?: throw IllegalArgumentException("Unknown message type $code")
    }
}

enum class DeviceRole(val wire: String) {
    HOST("host"),
    SPEAKER("speaker");

    companion object {
        fun fromWire(value: String): DeviceRole =
            entries.firstOrNull { it.wire == value.trim().lowercase() }
                ?: throw IllegalArgumentException("Unknown DeviceRole '$value'")
    }
}
