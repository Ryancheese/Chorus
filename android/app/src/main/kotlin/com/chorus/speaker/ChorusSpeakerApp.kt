package com.chorus.speaker

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.SystemClock
import com.chorus.core.sync.HostTime

class ChorusSpeakerApp : Application() {
    override fun onCreate() {
        super.onCreate()
        HostTime.install { SystemClock.elapsedRealtimeNanos() / 1_000_000_000.0 }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.notification_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = getString(R.string.notification_channel_desc)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    companion object {
        const val CHANNEL_ID = "chorus_speaker"
    }
}
