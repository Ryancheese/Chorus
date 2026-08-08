package com.chorus.core.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTimestamp
import android.media.AudioTrack
import android.os.Build
import android.os.Process
import android.os.SystemClock
import android.util.Log
import com.chorus.core.protocol.SyncProtocol
import com.chorus.core.sync.HostTime
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread
import kotlin.math.max

/**
 * Continuous-stream player (iOS-like): lock the first sample's audible time,
 * then append without mid-stream skips/pads (those cause crackles).
 */
class SyncAudioPlayer(
    private var sampleRate: Double = SyncProtocol.SAMPLE_RATE,
) : AutoCloseable {
    private data class ScheduledChunk(
        val pcm: ShortArray,
        val playAtLocalUptime: Double,
        val isFirst: Boolean,
    )

    private val queue = LinkedBlockingQueue<ScheduledChunk>()
    private val running = AtomicBoolean(false)
    private var track: AudioTrack? = null
    private var worker: Thread? = null
    private var hasStartedAudio = false
    private var trackStarted = false

    @Volatile
    var outputLatencySec: Double = 0.06
        private set

    @Volatile
    var manualTrimSec: Double = 0.0

    @Volatile
    var adaptiveTrimSec: Double = 0.0

    val totalCompensationSec: Double
        get() = (outputLatencySec + manualTrimSec + adaptiveTrimSec).coerceIn(0.015, 0.20)

    @Volatile
    var isPlaying: Boolean = false
        private set

    fun prepareSession(sampleRate: Double) {
        stop(keepAdaptive = true)
        this.sampleRate = sampleRate
        val rate = sampleRate.toInt()
        val probe = buildTrack(rate, forProbe = true)
        outputLatencySec = calibrateLatency(probe, rate)
        releaseTrack(probe)
        track = buildTrack(rate, forProbe = false)
        Log.i(
            TAG,
            "ready latencyMs=${ms(outputLatencySec)} adaptiveMs=${ms(adaptiveTrimSec)} manualMs=${ms(manualTrimSec)}",
        )
        running.set(true)
        hasStartedAudio = false
        trackStarted = false
        worker = thread(name = "chorus-audio-player", isDaemon = true, priority = Thread.MAX_PRIORITY) {
            try {
                Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            } catch (_: Exception) {
            }
            playbackLoop()
        }
    }

    fun scheduleChunk(pcmFloatLe: ByteArray, playAtLocalUptime: Double, sampleIndex: Long = 0L) {
        if (!running.get()) return
        val first = !hasStartedAudio
        if (first) hasStartedAudio = true
        queue.offer(ScheduledChunk(floatLeToPcm16(pcmFloatLe), playAtLocalUptime, first))
    }

    private fun buildTrack(rate: Int, forProbe: Boolean): AudioTrack {
        val minBuf = AudioTrack.getMinBufferSize(
            rate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        // Comfortable buffer prevents underrun crackles; timing is on first write only.
        val bufferSize = if (forProbe) {
            max(minBuf, rate / 10 * 2)
        } else {
            max(minBuf * 3, (rate * 0.35).toInt() * 2) // ~350ms int16 mono
        }
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
        val format = AudioFormat.Builder()
            .setSampleRate(rate)
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
            .build()
        val builder = AudioTrack.Builder()
            .setAudioAttributes(attrs)
            .setAudioFormat(format)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(bufferSize)
        if (!forProbe) {
            builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
        }
        return builder.build()
    }

    private fun calibrateLatency(audioTrack: AudioTrack, rate: Int): Double {
        val fallback = fallbackLatency(audioTrack, rate)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.KITKAT) return fallback
        return try {
            val probeFrames = max(rate / 20, 1024)
            val silence = ShortArray(probeFrames)
            val tWrite = HostTime.now()
            audioTrack.write(silence, 0, silence.size)
            audioTrack.play()
            var latency = fallback
            val deadline = SystemClock.uptimeMillis() + 300
            val ts = AudioTimestamp()
            while (SystemClock.uptimeMillis() < deadline) {
                if (audioTrack.getTimestamp(ts) && ts.framePosition > 32) {
                    val hostNow = HostTime.now()
                    val monoNow = System.nanoTime()
                    val presented = hostNow - (monoNow - ts.nanoTime) / 1_000_000_000.0
                    val measured = presented - tWrite - ts.framePosition.toDouble() / rate
                    if (measured in 0.015..0.18) {
                        latency = measured
                        break
                    }
                }
                SystemClock.sleep(4)
            }
            releaseTrack(audioTrack)
            Log.i(TAG, "calibrated latencyMs=${ms(latency)} fallbackMs=${ms(fallback)}")
            // Persist mild EMA into adaptive for next prepare (does not edit mid-stream).
            adaptiveTrimSec = (adaptiveTrimSec * 0.5 + (latency - fallback) * 0.15).coerceIn(-0.04, 0.08)
            latency
        } catch (ex: Exception) {
            Log.w(TAG, "calibrate failed: ${ex.message}")
            fallback
        }
    }

    private fun playbackLoop() {
        val audioTrack = track ?: return
        try {
            isPlaying = true
            while (running.get()) {
                val chunk = queue.poll(100, java.util.concurrent.TimeUnit.MILLISECONDS) ?: continue
                if (chunk.isFirst) {
                    val writeAt = chunk.playAtLocalUptime - totalCompensationSec
                    waitUntilPrecise(writeAt)
                }
                writeFully(audioTrack, chunk.pcm)
                if (!trackStarted) {
                    audioTrack.play()
                    trackStarted = true
                }
            }
        } catch (_: InterruptedException) {
        } catch (ex: Exception) {
            Log.w(TAG, "playbackLoop: ${ex.message}")
        } finally {
            try {
                if (trackStarted) audioTrack.pause()
                audioTrack.flush()
                audioTrack.stop()
            } catch (_: Exception) {
            }
            isPlaying = false
        }
    }

    private fun writeFully(audioTrack: AudioTrack, pcm: ShortArray) {
        var offset = 0
        while (offset < pcm.size && running.get()) {
            val written = audioTrack.write(pcm, offset, pcm.size - offset)
            if (written < 0) break
            if (written == 0) {
                SystemClock.sleep(1)
                continue
            }
            offset += written
        }
    }

    private fun waitUntilPrecise(localWriteAt: Double) {
        while (running.get()) {
            val wait = localWriteAt - HostTime.now()
            when {
                wait <= 0.0003 -> return
                wait > 3.0 -> {
                    Log.w(TAG, "wait too large, start now")
                    return
                }
                wait > 0.006 -> SystemClock.sleep(((wait - 0.003) * 1000).toLong().coerceAtLeast(1))
                else -> {
                    val end = System.nanoTime() + (wait * 1_000_000_000L).toLong()
                    while (System.nanoTime() < end && running.get()) {
                        // spin
                    }
                    return
                }
            }
        }
    }

    private fun fallbackLatency(audioTrack: AudioTrack, rate: Int): Double {
        var latencyMs = 0
        try {
            latencyMs = AudioTrack::class.java.getMethod("getLatency").invoke(audioTrack) as Int
        } catch (_: Exception) {
        }
        if (latencyMs <= 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            latencyMs = ((audioTrack.bufferSizeInFrames * 500.0) / rate).toInt() // ~half buffer
        }
        if (latencyMs <= 0) latencyMs = 60
        return (latencyMs / 1000.0).coerceIn(0.025, 0.16)
    }

    private fun floatLeToPcm16(pcmFloatLe: ByteArray): ShortArray {
        val n = pcmFloatLe.size / 4
        val out = ShortArray(n)
        val buf = ByteBuffer.wrap(pcmFloatLe).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
        for (i in 0 until n) {
            // Soft clip to avoid harsh PCM wrap distortion.
            var f = buf.get()
            if (f > 1f) f = 1f
            if (f < -1f) f = -1f
            out[i] = (f * 32767f).toInt().toShort()
        }
        return out
    }

    private fun releaseTrack(audioTrack: AudioTrack) {
        try {
            audioTrack.pause()
            audioTrack.flush()
            audioTrack.stop()
            audioTrack.release()
        } catch (_: Exception) {
        }
    }

    fun stop(keepAdaptive: Boolean = false) {
        running.set(false)
        queue.clear()
        worker?.interrupt()
        worker = null
        track?.let { releaseTrack(it) }
        track = null
        hasStartedAudio = false
        trackStarted = false
        isPlaying = false
    }

    override fun close() {
        adaptiveTrimSec = 0.0
        stop(keepAdaptive = false)
    }

    private fun ms(sec: Double): Int = (sec * 1000).toInt()

    companion object {
        private const val TAG = "ChorusAudio"
    }
}
