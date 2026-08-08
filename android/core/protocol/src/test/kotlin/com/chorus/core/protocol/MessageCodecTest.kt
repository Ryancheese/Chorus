package com.chorus.core.protocol

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID

class MessageCodecTest {
    @Test
    fun encodeDecodeHelloRoundTrip() {
        val info = DeviceInfo(
            id = UUID.randomUUID().toString(),
            name = "Android-Speaker",
            role = DeviceRole.SPEAKER,
        )
        val encoded = MessageCodec.encodeControl(ControlPayload.Hello(info))
        val json = String(encoded)
        assertTrue(json.contains("\"type\":1"))
        assertTrue(json.contains("\"role\":\"speaker\""))
        val decoded = MessageCodec.decodeControl(encoded) as ControlPayload.Hello
        assertEquals(info.id, decoded.info.id)
        assertEquals(info.name, decoded.info.name)
        assertEquals(DeviceRole.SPEAKER, decoded.info.role)
    }

    @Test
    fun encodeDecodeClockOffsetBareNumber() {
        val encoded = MessageCodec.encodeControl(ControlPayload.ClockOffset(0.123))
        val json = String(encoded)
        assertTrue(json.contains("\"type\":13"))
        assertTrue(json.contains("\"payload\":0.123"))
        val decoded = MessageCodec.decodeControl(encoded) as ControlPayload.ClockOffset
        assertEquals(0.123, decoded.seconds, 1e-9)
    }

    @Test
    fun encodeDecodeStopPlaybackSessionId() {
        val sessionId = UUID.randomUUID().toString()
        val encoded = MessageCodec.encodeControl(ControlPayload.StopPlayback(sessionId))
        val decoded = MessageCodec.decodeControl(encoded) as ControlPayload.StopPlayback
        assertEquals(sessionId, decoded.sessionId)
    }

    @Test
    fun encodeDecodeAudioFrame() {
        val header = AudioChunkHeader(
            sessionId = UUID.randomUUID().toString(),
            sequence = 42,
            sampleIndex = 1000,
            sampleCount = 2,
            hostPlayAt = 12.5,
        )
        val pcm = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
            .putFloat(0.5f)
            .putFloat(-0.25f)
            .array()
        val frame = MessageCodec.encodeAudioFrame(header, pcm)
        assertEquals(MessageType.AUDIO_CHUNK.code, frame[0].toInt() and 0xFF)
        val (decodedHeader, decodedPcm) = MessageCodec.decodeAudioFrame(frame)
        assertEquals(header.sessionId, decodedHeader.sessionId)
        assertEquals(header.sequence, decodedHeader.sequence)
        assertEquals(header.hostPlayAt, decodedHeader.hostPlayAt, 1e-9)
        assertArrayEquals(pcm, decodedPcm)
    }

    @Test
    fun frameIoPackUnpack() {
        val payload = MessageCodec.encodeControl(
            ControlPayload.Welcome(
                DeviceInfo("id", "name", DeviceRole.SPEAKER),
            ),
        )
        val packed = FrameIO.pack(payload)
        val unpacker = FrameIO.Unpacker()
        // Split mid-frame to exercise streaming.
        val mid = packed.size / 2
        val frames1 = unpacker.append(packed, 0, mid)
        assertTrue(frames1.isEmpty())
        val frames2 = unpacker.append(packed, mid, packed.size - mid)
        assertEquals(1, frames2.size)
        assertArrayEquals(payload, frames2[0])
    }
}
