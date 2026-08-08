package com.chorus.core.network

import com.chorus.core.protocol.SyncBonjour
import java.net.ServerSocket
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * TCP listener that accepts Host connections on the Chorus control port.
 * Pairing of control vs audio sockets is handled by SpeakerSession.
 */
class SpeakerListener : AutoCloseable {
    private var serverSocket: ServerSocket? = null
    private val running = AtomicBoolean(false)
    private var acceptThread: Thread? = null

    var listeningPort: Int = SyncBonjour.CONTROL_PORT
        private set
    var localIPv4: String? = null
        private set

    var onConnectionAccepted: ((SyncConnection) -> Unit)? = null

    fun start(port: Int = SyncBonjour.CONTROL_PORT) {
        stop()
        listeningPort = port
        localIPv4 = LocalAddress.primaryIPv4()
        val server = ServerSocket(port)
        server.reuseAddress = true
        serverSocket = server
        running.set(true)
        acceptThread = thread(name = "chorus-speaker-accept", isDaemon = true) {
            acceptLoop(server)
        }
    }

    private fun acceptLoop(server: ServerSocket) {
        while (running.get()) {
            try {
                val socket = server.accept()
                socket.tcpNoDelay = true
                val label = socket.remoteSocketAddress?.toString() ?: "peer"
                val conn = SyncConnection(socket, label)
                onConnectionAccepted?.invoke(conn)
            } catch (_: Exception) {
                if (!running.get()) break
            }
        }
    }

    fun stop() {
        running.set(false)
        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }
        serverSocket = null
        acceptThread?.interrupt()
        acceptThread = null
    }

    override fun close() = stop()
}
