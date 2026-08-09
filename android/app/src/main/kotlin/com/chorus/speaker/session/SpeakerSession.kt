package com.chorus.speaker.session

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.util.Log
import com.chorus.core.audio.SyncAudioPlayer
import com.chorus.core.network.SpeakerListener
import com.chorus.core.network.SyncConnection
import com.chorus.core.network.SyncConnectionEvent
import com.chorus.core.protocol.ControlPayload
import com.chorus.core.protocol.DeviceInfo
import com.chorus.core.protocol.DeviceRole
import com.chorus.core.protocol.SyncBonjour
import com.chorus.core.protocol.SyncProtocol
import com.chorus.core.sync.AudioJitterBuffer
import com.chorus.core.sync.HostTime
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

enum class SpeakerPhase {
    IDLE,
    ADVERTISING,
    CONNECTED,
    READY,
    PLAYING,
    ERROR,
}

data class SpeakerUiState(
    val phase: SpeakerPhase = SpeakerPhase.IDLE,
    val status: String = "点击开始广播",
    val localAddress: String? = null,
    val hostName: String? = null,
    val sessionTitle: String? = null,
    val clockOffset: Double? = null,
    val errorMessage: String? = null,
    /** Manual sync trim in milliseconds. Positive = phone plays earlier. */
    val syncTrimMs: Int = 0,
)

/**
 * Speaker-side session: advertise via NSD, accept dual TCP, sync clock, play PCM.
 * Ported from Windows Chorus.Speaker.SpeakerSession with iOS-style per-chunk scheduling.
 */
class SpeakerSession(
    private val appContext: Context,
    private val onStateChanged: (SpeakerUiState) -> Unit,
) : AutoCloseable {
    private val localDevice = DeviceInfo(
        id = UUID.randomUUID().toString(),
        name = Build.MODEL.ifBlank { "Android" },
        role = DeviceRole.SPEAKER,
        platform = "android",
        model = listOf(Build.MANUFACTURER, Build.MODEL)
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinctBy { it.lowercase() }
            .joinToString(" ")
            .ifBlank { null },
    )

    private val lock = Any()
    private var control: SyncConnection? = null
    private var audio: SyncConnection? = null
    private var clockOffset: Double = 0.0
    private var jitter: AudioJitterBuffer? = null
    private var player: SyncAudioPlayer? = null
    private var sessionId: String? = null
    private var sessionSampleRate: Double = SyncProtocol.SAMPLE_RATE
    private var playArmed = false
    private var firstChunkScheduled = false

    private var listener: SpeakerListener? = null
    private var nsdManager: NsdManager? = null
    private var nsdListener: NsdManager.RegistrationListener? = null
    private var registeredServiceName: String? = null
    private val disposed = AtomicBoolean(false)
    private val wantAdvertising = AtomicBoolean(false)
    private val prefs = appContext.getSharedPreferences("chorus_speaker", Context.MODE_PRIVATE)

    /** Positive ms → write earlier (phone was late). Persisted across runs. */
    private var syncTrimMs: Int = prefs.getInt(PREF_SYNC_TRIM_MS, 0)

    @Volatile
    private var state = SpeakerUiState(syncTrimMs = syncTrimMs)

    fun adjustSyncTrimMs(deltaMs: Int) {
        syncTrimMs = (syncTrimMs + deltaMs).coerceIn(-120, 120)
        prefs.edit().putInt(PREF_SYNC_TRIM_MS, syncTrimMs).apply()
        player?.manualTrimSec = syncTrimMs / 1000.0
        publish(state.copy(syncTrimMs = syncTrimMs, status = "同步微调：${syncTrimMs} ms"))
        Log.i(TAG, "syncTrimMs=$syncTrimMs")
    }

    fun startAdvertising(port: Int = SyncBonjour.CONTROL_PORT) {
        wantAdvertising.set(true)
        stopAdvertisingInternal(restarting = false)
        val speakerListener = SpeakerListener()
        speakerListener.onConnectionAccepted = { conn -> onInboundConnection(conn) }
        try {
            speakerListener.start(port)
        } catch (ex: Exception) {
            publish(
                state.copy(
                    phase = SpeakerPhase.ERROR,
                    status = "无法监听端口 $port",
                    errorMessage = ex.message,
                ),
            )
            return
        }
        listener = speakerListener
        val ip = speakerListener.localIPv4
        registerNsd(speakerListener.listeningPort)
        publish(
            SpeakerUiState(
                phase = SpeakerPhase.ADVERTISING,
                status = "等待主机连接…",
                localAddress = ip?.let { "$it:${speakerListener.listeningPort}" },
                syncTrimMs = syncTrimMs,
            ),
        )
    }

    fun stopAdvertising() {
        wantAdvertising.set(false)
        persistAdaptiveTrim()
        stopAdvertisingInternal(restarting = false)
        publish(
            SpeakerUiState(
                phase = SpeakerPhase.IDLE,
                status = "已停止",
                syncTrimMs = syncTrimMs,
            ),
        )
    }

    private fun stopAdvertisingInternal(restarting: Boolean) {
        unregisterNsd()
        try {
            listener?.close()
        } catch (_: Exception) {
        }
        listener = null
        stopPlaying()
        try {
            audio?.close()
        } catch (_: Exception) {
        }
        try {
            control?.close()
        } catch (_: Exception) {
        }
        audio = null
        control = null
        sessionId = null
        clockOffset = 0.0
        if (!restarting) {
            // keep state update to caller
        }
    }

    private fun registerNsd(port: Int) {
        val manager = appContext.getSystemService(Context.NSD_SERVICE) as NsdManager
        nsdManager = manager
        val serviceInfo = NsdServiceInfo().apply {
            serviceName = "Chorus-Speaker-${Build.MODEL}"
            serviceType = "${SyncBonjour.TYPE}."
            setPort(port)
        }
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) {
                registeredServiceName = info.serviceName
                Log.i(TAG, "NSD registered: ${info.serviceName}")
            }

            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                Log.w(TAG, "NSD registration failed: $errorCode")
                // Manual IP still works.
            }

            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {
                Log.i(TAG, "NSD unregistered")
            }

            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                Log.w(TAG, "NSD unregistration failed: $errorCode")
            }
        }
        nsdListener = listener
        try {
            manager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (ex: Exception) {
            Log.w(TAG, "NSD register threw: ${ex.message}")
        }
    }

    private fun unregisterNsd() {
        val manager = nsdManager
        val listener = nsdListener
        if (manager != null && listener != null) {
            try {
                manager.unregisterService(listener)
            } catch (_: Exception) {
            }
        }
        nsdManager = null
        nsdListener = null
        registeredServiceName = null
    }

    private fun onInboundConnection(conn: SyncConnection) {
        synchronized(lock) {
            if (control == null) {
                control = conn
                conn.start { evt -> handleControlEvent(evt, conn) }
                publish(
                    state.copy(
                        phase = SpeakerPhase.CONNECTED,
                        status = "Host 控制通道已连入，握手中…",
                    ),
                )
                return
            }
            if (audio == null) {
                audio = conn
                conn.start { evt -> handleAudioEvent(evt, conn) }
                Log.i(TAG, "第二条 TCP 已连入（待 audioChannelHello）")
                return
            }
            Log.w(TAG, "忽略多余入站连接")
            try {
                conn.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun handleControlEvent(evt: SyncConnectionEvent, conn: SyncConnection) {
        if (conn !== control) return
        when (evt) {
            is SyncConnectionEvent.Connected -> Unit
            is SyncConnectionEvent.Control -> {
                if (evt.payload is ControlPayload.AudioChannelHello) {
                    synchronized(lock) {
                        if (audio == null) audio = conn
                    }
                    Log.i(TAG, "在控制通道收到 audioChannelHello（单连接兼容）")
                } else {
                    handleControl(evt.payload)
                }
            }
            is SyncConnectionEvent.Audio -> {
                if (audio == null || audio === conn) {
                    handleAudio(evt.header, evt.pcm)
                }
            }
            is SyncConnectionEvent.Disconnected -> onControlDisconnected(evt.reason)
        }
    }

    private fun handleAudioEvent(evt: SyncConnectionEvent, conn: SyncConnection) {
        if (conn !== audio) return
        when (evt) {
            is SyncConnectionEvent.Control -> {
                if (evt.payload is ControlPayload.AudioChannelHello) {
                    val connected = state.hostName?.let { "已连接 $it" } ?: "双通道已就绪"
                    publish(state.copy(phase = SpeakerPhase.READY, status = connected))
                }
            }
            is SyncConnectionEvent.Audio -> handleAudio(evt.header, evt.pcm)
            is SyncConnectionEvent.Disconnected -> {
                Log.w(TAG, "音频通道断开：${evt.reason}")
                synchronized(lock) {
                    audio = null
                    val c = control
                    control = null
                    try {
                        c?.close()
                    } catch (_: Exception) {
                    }
                }
                onSessionLost("音频通道已断开")
            }
            is SyncConnectionEvent.Connected -> Unit
        }
    }

    private fun onControlDisconnected(reason: String?) {
        stopPlaying()
        synchronized(lock) {
            try {
                audio?.close()
            } catch (_: Exception) {
            }
            audio = null
            control = null
        }
        onSessionLost(reason)
    }

    private fun onSessionLost(reason: String?) {
        val port = listener?.listeningPort ?: SyncBonjour.CONTROL_PORT
        unregisterNsd()
        try {
            listener?.close()
        } catch (_: Exception) {
        }
        listener = null
        publish(
            state.copy(
                phase = SpeakerPhase.ADVERTISING,
                status = "断开：${reason ?: "未知"}，重新广播中…",
                hostName = null,
                sessionTitle = null,
                clockOffset = null,
            ),
        )
        Thread {
            try {
                Thread.sleep(1000)
            } catch (_: InterruptedException) {
                return@Thread
            }
            if (disposed.get() || !wantAdvertising.get()) return@Thread
            startAdvertising(port)
        }.start()
    }

    private fun handleControl(payload: ControlPayload) {
        when (payload) {
            is ControlPayload.Hello -> {
                control?.sendControl(ControlPayload.Welcome(localDevice))
                publish(
                    state.copy(
                        phase = SpeakerPhase.READY,
                        status = "已连接 ${payload.info.name}",
                        hostName = payload.info.name,
                    ),
                )
            }
            is ControlPayload.Welcome -> {
                publish(
                    state.copy(
                        phase = SpeakerPhase.READY,
                        status = "已连接 ${payload.info.name}",
                        hostName = payload.info.name,
                    ),
                )
            }
            is ControlPayload.ClockPing -> {
                val recv = HostTime.now()
                val send = HostTime.now()
                control?.sendControl(
                    ControlPayload.ClockPong(
                        com.chorus.core.protocol.ClockPongData(
                            pingId = payload.ping.pingId,
                            hostSendTime = payload.ping.hostSendTime,
                            speakerReceiveTime = recv,
                            speakerSendTime = send,
                        ),
                    ),
                )
            }
            is ControlPayload.ClockOffset -> {
                clockOffset = payload.seconds
                publish(state.copy(clockOffset = payload.seconds, status = state.status))
                Log.i(TAG, "时钟偏移更新：${payload.seconds}")
            }
            is ControlPayload.PrepareSession -> {
                stopPlaying(keepPlayerAdaptive = true)
                sessionId = payload.session.sessionId
                sessionSampleRate = payload.session.sampleRate
                jitter = AudioJitterBuffer(sessionSampleRate)
                val p = player ?: SyncAudioPlayer(sessionSampleRate)
                p.manualTrimSec = syncTrimMs / 1000.0
                p.adaptiveTrimSec = prefs.getFloat(PREF_ADAPTIVE_TRIM, 0f).toDouble()
                p.prepareSession(sessionSampleRate)
                player = p
                playArmed = false
                firstChunkScheduled = false
                publish(
                    state.copy(
                        phase = SpeakerPhase.READY,
                        status = "准备播放：${payload.session.title}",
                        sessionTitle = payload.session.title,
                        syncTrimMs = syncTrimMs,
                    ),
                )
            }
            is ControlPayload.StartPlayback -> {
                if (player == null) {
                    val p = SyncAudioPlayer(sessionSampleRate)
                    p.manualTrimSec = syncTrimMs / 1000.0
                    p.adaptiveTrimSec = prefs.getFloat(PREF_ADAPTIVE_TRIM, 0f).toDouble()
                    p.prepareSession(sessionSampleRate)
                    player = p
                }
                if (jitter == null) {
                    jitter = AudioJitterBuffer(sessionSampleRate)
                }
                playArmed = true
                firstChunkScheduled = false
                publish(
                    state.copy(
                        phase = SpeakerPhase.READY,
                        status = "即将同步起播…",
                        syncTrimMs = syncTrimMs,
                    ),
                )
                Log.i(
                    TAG,
                    "StartPlayback hostPlayAt=${payload.start.hostPlayAt} offset=$clockOffset trimMs=$syncTrimMs",
                )
            }
            is ControlPayload.StopPlayback -> {
                stopPlaying()
                control?.sendControl(
                    ControlPayload.StopAcknowledged(sessionId ?: payload.sessionId),
                )
                publish(
                    state.copy(
                        phase = SpeakerPhase.READY,
                        status = "已停止",
                        sessionTitle = state.sessionTitle,
                    ),
                )
            }
            is ControlPayload.Goodbye -> {
                stopPlaying()
                publish(state.copy(phase = SpeakerPhase.ADVERTISING, status = "Host 已断开"))
            }
            else -> Unit
        }
    }

    private fun handleAudio(header: com.chorus.core.protocol.AudioChunkHeader, pcm: ByteArray) {
        val currentSession = sessionId
        val currentJitter = jitter
        if (currentSession == null || currentSession != header.sessionId || currentJitter == null) {
            return
        }
        val ready = currentJitter.append(header, pcm)
        if (!playArmed) return
        val p = player ?: return
        for (chunk in ready) {
            var localPlayAt = chunk.header.hostPlayAt + clockOffset
            if (!firstChunkScheduled) {
                firstChunkScheduled = true
                val writeDeadline = localPlayAt - p.totalCompensationSec
                // Only rebase when hopelessly late (>400ms). Mild lateness is handled
                // by SyncAudioPlayer hard-correct — rebasing destroys absolute sync.
                if (writeDeadline < HostTime.now() - 0.40) {
                    val adjusted = HostTime.now() + 0.12
                    clockOffset += adjusted - localPlayAt
                    localPlayAt = adjusted
                    Log.w(TAG, "first chunk hopelessly late — rebase")
                }
                Log.i(
                    TAG,
                    "first chunk playAt=$localPlayAt compMs=${(p.totalCompensationSec * 1000).toInt()}",
                )
                publish(
                    state.copy(
                        phase = SpeakerPhase.PLAYING,
                        status = state.sessionTitle?.let { "播放中：$it" } ?: "播放中",
                        clockOffset = clockOffset,
                    ),
                )
            }
            p.scheduleChunk(chunk.pcm, localPlayAt, chunk.header.sampleIndex)
        }
    }

    private fun stopPlaying(keepPlayerAdaptive: Boolean = false) {
        playArmed = false
        firstChunkScheduled = false
        persistAdaptiveTrim()
        try {
            player?.stop(keepAdaptive = keepPlayerAdaptive)
        } catch (_: Exception) {
        }
        if (!keepPlayerAdaptive) {
            player = null
        }
        jitter?.reset()
    }

    private fun persistAdaptiveTrim() {
        val adaptive = player?.adaptiveTrimSec ?: return
        prefs.edit().putFloat(PREF_ADAPTIVE_TRIM, adaptive.toFloat()).apply()
    }

    private fun publish(next: SpeakerUiState) {
        state = next
        onStateChanged(next)
    }

    override fun close() {
        if (!disposed.compareAndSet(false, true)) return
        wantAdvertising.set(false)
        stopAdvertisingInternal(restarting = false)
    }

    companion object {
        private const val TAG = "ChorusSpeaker"
        private const val PREF_SYNC_TRIM_MS = "sync_trim_ms"
        private const val PREF_ADAPTIVE_TRIM = "adaptive_trim_sec"
    }
}
