package com.chorus.core.sync

import com.chorus.core.protocol.AudioChunkHeader
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

class JitterBufferTest {
    @Test
    fun buffersUntilTargetThenReleasesInOrder() {
        val sessionId = UUID.randomUUID().toString()
        // 44100 * 0.8 ≈ 35280 samples; use 10000-sample chunks → need 4 chunks to start.
        val jitter = AudioJitterBuffer(sampleRate = 44_100.0, targetDuration = 0.8)
        val pcm = ByteArray(10000 * 4)

        fun header(seq: Long) = AudioChunkHeader(
            sessionId = sessionId,
            sequence = seq,
            sampleIndex = seq * 10000,
            sampleCount = 10000,
            hostPlayAt = seq.toDouble(),
        )

        assertTrue(jitter.append(header(0), pcm).isEmpty())
        assertTrue(jitter.append(header(1), pcm).isEmpty())
        assertTrue(jitter.append(header(2), pcm).isEmpty())
        val ready = jitter.append(header(3), pcm)
        assertEquals(4, ready.size)
        assertEquals(0L, ready[0].header.sequence)
        assertEquals(3L, ready[3].header.sequence)
    }

    @Test
    fun reordersOutOfOrderChunks() {
        val sessionId = UUID.randomUUID().toString()
        val jitter = AudioJitterBuffer(sampleRate = 44_100.0, targetDuration = 0.0)
        val pcm = ByteArray(4)

        fun header(seq: Long) = AudioChunkHeader(
            sessionId = sessionId,
            sequence = seq,
            sampleIndex = seq,
            sampleCount = 1,
            hostPlayAt = 0.0,
        )

        assertTrue(jitter.append(header(1), pcm).isEmpty())
        val ready = jitter.append(header(0), pcm)
        assertEquals(2, ready.size)
        assertEquals(0L, ready[0].header.sequence)
        assertEquals(1L, ready[1].header.sequence)
    }
}
