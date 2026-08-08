package com.chorus.speaker.service

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.chorus.speaker.ChorusSpeakerApp
import com.chorus.speaker.MainActivity
import com.chorus.speaker.R
import com.chorus.speaker.session.SpeakerPhase
import com.chorus.speaker.session.SpeakerSession
import com.chorus.speaker.session.SpeakerUiState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class SpeakerForegroundService : Service() {
    private var session: SpeakerSession? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSession()
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                ensureSession()
                session?.startAdvertising()
            }
        }
        return START_STICKY
    }

    private fun ensureSession() {
        if (session != null) return
        val s = SpeakerSession(applicationContext) { ui ->
            _uiState.value = ui
            updateNotification(ui)
        }
        session = s
        instance = this
        val notification = buildNotification(_uiState.value)
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            } else {
                0
            },
        )
    }

    private fun stopSession() {
        session?.close()
        session = null
        instance = null
        _uiState.value = SpeakerUiState(phase = SpeakerPhase.IDLE, status = "已停止")
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun updateNotification(ui: SpeakerUiState) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification(ui))
    }

    private fun buildNotification(ui: SpeakerUiState): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, SpeakerForegroundService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val title = when (ui.phase) {
            SpeakerPhase.PLAYING -> getString(R.string.notif_playing)
            SpeakerPhase.ADVERTISING -> getString(R.string.notif_advertising)
            SpeakerPhase.CONNECTED, SpeakerPhase.READY -> getString(R.string.notif_connected)
            else -> getString(R.string.app_name)
        }
        return NotificationCompat.Builder(this, ChorusSpeakerApp.CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(ui.status)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(open)
            .addAction(0, getString(R.string.action_stop), stop)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    fun adjustTrim(deltaMs: Int) {
        session?.adjustSyncTrimMs(deltaMs)
    }

    override fun onDestroy() {
        stopSession()
        super.onDestroy()
    }

    companion object {
        const val ACTION_STOP = "com.chorus.speaker.STOP"
        private const val NOTIFICATION_ID = 17482

        private val _uiState = MutableStateFlow(SpeakerUiState())
        val uiState: StateFlow<SpeakerUiState> = _uiState.asStateFlow()

        @Volatile
        private var instance: SpeakerForegroundService? = null

        fun isRunning(): Boolean = instance != null

        fun start(context: Context) {
            val intent = Intent(context, SpeakerForegroundService::class.java)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, SpeakerForegroundService::class.java).setAction(ACTION_STOP)
            context.startService(intent)
        }

        fun adjustSyncTrim(deltaMs: Int) {
            instance?.adjustTrim(deltaMs)
        }
    }
}
