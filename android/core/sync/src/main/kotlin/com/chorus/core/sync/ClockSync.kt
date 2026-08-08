package com.chorus.core.sync

import com.chorus.core.protocol.ClockPongData

data class ClockOffsetEstimate(
    val offset: Double,
    val roundTrip: Double,
    val updatedAt: Double,
) {
    fun speakerTimeForHostTime(hostTime: Double): Double = hostTime + offset
}

/**
 * Sliding-window NTP-style offset estimator (host-side samples).
 * Speakers typically apply Host-pushed [ControlPayload.ClockOffset] directly.
 */
class ClockSynchronizer(private val maxSamples: Int = 8) {
    private val lock = Any()
    private val samples = ArrayList<ClockOffsetEstimate>()

    val bestEstimate: ClockOffsetEstimate?
        get() = synchronized(lock) {
            if (samples.isEmpty()) null
            else samples.minBy { it.roundTrip }
        }

    fun recordPong(pong: ClockPongData, hostReceiveTime: Double) {
        val rtt = hostReceiveTime - pong.hostSendTime
        if (rtt < 0 || rtt >= 2.0) return
        val speakerMid = (pong.speakerReceiveTime + pong.speakerSendTime) / 2.0
        val hostMid = (pong.hostSendTime + hostReceiveTime) / 2.0
        val estimate = ClockOffsetEstimate(speakerMid - hostMid, rtt, hostReceiveTime)
        synchronized(lock) {
            samples.add(estimate)
            if (samples.size > maxSamples) {
                samples.subList(0, samples.size - maxSamples).clear()
            }
        }
    }

    fun reset() {
        synchronized(lock) { samples.clear() }
    }
}

/**
 * Monotonic clock in seconds.
 * Prefer [android.os.SystemClock.elapsedRealtimeNanos] on Android via [AndroidHostTime].
 * JVM fallback uses nanoTime for unit tests.
 */
object HostTime {
    @Volatile
    private var provider: () -> Double = { System.nanoTime() / 1_000_000_000.0 }

    fun install(provider: () -> Double) {
        this.provider = provider
    }

    fun now(): Double = provider()
}
