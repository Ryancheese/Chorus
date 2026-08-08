package com.chorus.core.network

import com.chorus.core.protocol.AudioChunkHeader
import com.chorus.core.protocol.ControlPayload
import com.chorus.core.protocol.FrameIO
import com.chorus.core.protocol.MessageCodec
import com.chorus.core.protocol.MessageType
import java.io.BufferedInputStream
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

sealed class SyncConnectionEvent {
    data object Connected : SyncConnectionEvent()
    data class Control(val payload: ControlPayload) : SyncConnectionEvent()
    data class Audio(val header: AudioChunkHeader, val pcm: ByteArray) : SyncConnectionEvent()
    data class Disconnected(val reason: String?) : SyncConnectionEvent()
}

/**
 * Bidirectional framed TCP session used by both host and speaker.
 */
class SyncConnection(
    private val socket: Socket,
    val remoteLabel: String = "peer",
) : AutoCloseable {
    private val unpacker = FrameIO.Unpacker()
    private val writeLock = Any()
    private val closed = AtomicBoolean(false)
    private var onEvent: ((SyncConnectionEvent) -> Unit)? = null
    private var readerThread: Thread? = null

    fun start(onEvent: (SyncConnectionEvent) -> Unit) {
        this.onEvent = onEvent
        emit(SyncConnectionEvent.Connected)
        readerThread = thread(name = "chorus-sync-$remoteLabel", isDaemon = true) {
            receiveLoop()
        }
    }

    fun sendControl(payload: ControlPayload) {
        try {
            sendFrame(MessageCodec.encodeControl(payload))
        } catch (ex: Exception) {
            emit(SyncConnectionEvent.Disconnected("encode control failed: ${ex.message}"))
        }
    }

    fun sendAudio(header: AudioChunkHeader, pcm: ByteArray) {
        try {
            sendFrame(MessageCodec.encodeAudioFrame(header, pcm))
        } catch (ex: Exception) {
            emit(SyncConnectionEvent.Disconnected("encode audio failed: ${ex.message}"))
        }
    }

    private fun sendFrame(payload: ByteArray) {
        val framed = FrameIO.pack(payload)
        synchronized(writeLock) {
            val out = socket.getOutputStream()
            out.write(framed)
            out.flush()
        }
    }

    private fun receiveLoop() {
        try {
            val input = BufferedInputStream(socket.getInputStream(), 256 * 1024)
            val buffer = ByteArray(256 * 1024)
            while (!closed.get()) {
                val read = input.read(buffer)
                if (read < 0) {
                    emit(SyncConnectionEvent.Disconnected(null))
                    return
                }
                if (read == 0) continue
                val frames = unpacker.append(buffer, 0, read)
                for (frame in frames) {
                    handleFrame(frame)
                }
            }
        } catch (_: InterruptedException) {
            // shutdown
        } catch (ex: Exception) {
            if (!closed.get()) {
                emit(SyncConnectionEvent.Disconnected(ex.message))
            }
        }
    }

    private fun handleFrame(frame: ByteArray) {
        if (frame.isEmpty()) return
        if ((frame[0].toInt() and 0xFF) == MessageType.AUDIO_CHUNK.code) {
            try {
                val (header, pcm) = MessageCodec.decodeAudioFrame(frame)
                emit(SyncConnectionEvent.Audio(header, pcm))
            } catch (ex: Exception) {
                emit(SyncConnectionEvent.Disconnected("bad audio frame: ${ex.message}"))
            }
            return
        }
        try {
            emit(SyncConnectionEvent.Control(MessageCodec.decodeControl(frame)))
        } catch (ex: Exception) {
            emit(SyncConnectionEvent.Disconnected("bad control frame: ${ex.message}"))
        }
    }

    private fun emit(event: SyncConnectionEvent) {
        onEvent?.invoke(event)
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        try {
            socket.close()
        } catch (_: Exception) {
        }
        readerThread?.interrupt()
    }
}
