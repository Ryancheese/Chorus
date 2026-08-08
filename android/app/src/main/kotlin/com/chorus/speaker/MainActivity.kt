package com.chorus.speaker

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.chorus.speaker.service.SpeakerForegroundService
import com.chorus.speaker.ui.SpeakerScreen
import com.chorus.speaker.ui.theme.ChorusSpeakerTheme

class MainActivity : ComponentActivity() {
    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* proceed anyway */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        maybeRequestNotificationPermission()
        setContent {
            var darkTheme by remember { mutableStateOf(true) }
            var localTrim by remember {
                mutableStateOf(getSharedPreferences("chorus_speaker", Context.MODE_PRIVATE).getInt("sync_trim_ms", 0))
            }
            ChorusSpeakerTheme(darkTheme = darkTheme) {
                val ui by SpeakerForegroundService.uiState.collectAsStateWithLifecycle()
                val shown = if (SpeakerForegroundService.isRunning()) ui else ui.copy(syncTrimMs = localTrim)
                SpeakerScreen(
                    state = shown,
                    isServiceRunning = SpeakerForegroundService.isRunning(),
                    darkTheme = darkTheme,
                    onToggleTheme = { darkTheme = !darkTheme },
                    onStart = { SpeakerForegroundService.start(this) },
                    onStop = { SpeakerForegroundService.stop(this) },
                    onTrim = { delta ->
                        if (SpeakerForegroundService.isRunning()) {
                            SpeakerForegroundService.adjustSyncTrim(delta)
                        } else {
                            val prefs = getSharedPreferences("chorus_speaker", Context.MODE_PRIVATE)
                            val next = (prefs.getInt("sync_trim_ms", 0) + delta).coerceIn(-120, 120)
                            prefs.edit().putInt("sync_trim_ms", next).apply()
                            localTrim = next
                        }
                    },
                )
            }
        }
    }

    private fun maybeRequestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}
