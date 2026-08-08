package com.chorus.core.protocol

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Length-prefixed TCP framing shared by control and audio channels:
 * `[4 byte length big-endian][payload bytes]`.
 */
object FrameIO {
    private const val MAX_FRAME = 16 * 1024 * 1024

    fun pack(payload: ByteArray): ByteArray {
        val out = ByteArray(4 + payload.size)
        ByteBuffer.wrap(out).order(ByteOrder.BIG_ENDIAN).putInt(payload.size)
        System.arraycopy(payload, 0, out, 4, payload.size)
        return out
    }

    class Unpacker {
        private val lock = ReentrantLock()
        private var buffer = ByteArray(0)
        private var length = 0

        fun append(data: ByteArray, offset: Int = 0, count: Int = data.size): List<ByteArray> {
            lock.withLock {
                ensureCapacity(count)
                System.arraycopy(data, offset, buffer, length, count)
                length += count

                val frames = ArrayList<ByteArray>()
                var pos = 0
                while (length - pos >= 4) {
                    val frameLen = ByteBuffer.wrap(buffer, pos, 4).order(ByteOrder.BIG_ENDIAN).int
                    if (frameLen < 0 || frameLen > MAX_FRAME) {
                        throw CodecException("Frame too large: $frameLen")
                    }
                    if (length - pos < 4 + frameLen) break
                    val frame = buffer.copyOfRange(pos + 4, pos + 4 + frameLen)
                    frames.add(frame)
                    pos += 4 + frameLen
                }
                if (pos > 0) {
                    val remaining = length - pos
                    if (remaining > 0) {
                        System.arraycopy(buffer, pos, buffer, 0, remaining)
                    }
                    length = remaining
                }
                return frames
            }
        }

        fun reset() {
            lock.withLock { length = 0 }
        }

        private fun ensureCapacity(incoming: Int) {
            val needed = length + incoming
            if (buffer.size >= needed) return
            var newSize = maxOf(buffer.size * 2, 8192)
            while (newSize < needed) newSize *= 2
            val newBuf = ByteArray(newSize)
            if (length > 0) {
                System.arraycopy(buffer, 0, newBuf, 0, length)
            }
            buffer = newBuf
        }
    }
}

class CodecException(message: String) : Exception(message)
