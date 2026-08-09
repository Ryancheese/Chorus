package com.chorus.core.sync

import com.chorus.core.protocol.AudioChunkHeader

/**
 * Holds received PCM briefly so Wi-Fi jitter does not turn into audible gaps.
 * Reorders by sequence and releases a contiguous run once ~[targetDuration] is buffered.
 * Mid-session joiners anchor to the earliest buffered sequence (not zero).
 */
class AudioJitterBuffer(
    private val sampleRate: Double,
    private val targetDuration: Double = 0.8,
) {
    data class Chunk(val header: AudioChunkHeader, val pcm: ByteArray)

    private val pending = LinkedHashMap<Long, Chunk>()
    private var nextSequence: Long = 0
    private var bufferedSamples: Long = 0
    private var started = false

    fun reset() {
        pending.clear()
        nextSequence = 0
        bufferedSamples = 0
        started = false
    }

    fun append(header: AudioChunkHeader, pcm: ByteArray): List<Chunk> {
        val ready = ArrayList<Chunk>()
        if (pending.containsKey(header.sequence)) return ready
        if (started && header.sequence < nextSequence) return ready

        pending[header.sequence] = Chunk(header, pcm)
        bufferedSamples += header.sampleCount

        if (!started) {
            started = (bufferedSamples / sampleRate) >= targetDuration
            if (started) {
                nextSequence = pending.keys.minOrNull() ?: header.sequence
            }
        }
        if (!started) return ready

        while (true) {
            val chunk = pending.remove(nextSequence) ?: break
            bufferedSamples -= chunk.header.sampleCount
            ready.add(chunk)
            nextSequence++
        }
        return ready
    }
}
