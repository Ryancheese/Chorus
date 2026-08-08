package com.chorus.speaker.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Speaker
import androidx.compose.material.icons.outlined.Tonality
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chorus.speaker.session.SpeakerPhase
import com.chorus.speaker.session.SpeakerUiState
import com.chorus.speaker.ui.theme.GlassAccent
import com.chorus.speaker.ui.theme.GlassAccentSoft
import com.chorus.speaker.ui.theme.GlassMint
import kotlin.math.cos
import kotlin.math.sin

@Composable
fun SpeakerScreen(
    state: SpeakerUiState,
    isServiceRunning: Boolean,
    darkTheme: Boolean,
    onToggleTheme: () -> Unit,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onTrim: (Int) -> Unit,
) {
    var appeared by remember { mutableStateOf(false) }
    var showHelp by remember { mutableStateOf(false) }
    var langMenu by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { appeared = true }
    val contentAlpha by animateFloatAsState(
        targetValue = if (appeared) 1f else 0f,
        animationSpec = tween(700),
        label = "fade",
    )

    val broadcasting = isServiceRunning && state.phase != SpeakerPhase.IDLE
    val playing = state.phase == SpeakerPhase.PLAYING
    val showClockChip = state.clockOffset != null && state.phase != SpeakerPhase.IDLE

    Box(modifier = Modifier.fillMaxSize()) {
        LiquidGlassBackground(darkTheme = darkTheme)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 22.dp)
                .alpha(contentAlpha),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.weight(0.35f))

            PulsingOrb(active = broadcasting, playing = playing)
            Spacer(modifier = Modifier.height(14.dp))
            Text(
                text = "Chorus",
                fontSize = 36.sp,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onBackground,
            )
            Text(
                text = "扬声器",
                fontSize = 17.sp,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.55f),
            )

            Spacer(modifier = Modifier.height(24.dp))

            GlassStatusCard(
                state = state,
                broadcasting = broadcasting,
                showClockChip = showClockChip,
            )

            Spacer(modifier = Modifier.weight(0.65f))

            // Match iPhone screenshot: utility row sits just above the CTA, trailing.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 12.dp),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box {
                    UtilityLink(
                        icon = {
                            Icon(
                                Icons.Outlined.Language,
                                null,
                                tint = GlassAccentSoft,
                                modifier = Modifier.size(16.dp),
                            )
                        },
                        label = "语言",
                        onClick = { langMenu = true },
                    )
                    DropdownMenu(expanded = langMenu, onDismissRequest = { langMenu = false }) {
                        DropdownMenuItem(
                            text = { Text("简体中文") },
                            onClick = { langMenu = false },
                        )
                    }
                }
                Spacer(modifier = Modifier.width(12.dp))
                UtilityLink(
                    icon = {
                        Icon(
                            Icons.Outlined.Tonality,
                            null,
                            tint = GlassAccentSoft,
                            modifier = Modifier.size(16.dp),
                        )
                    },
                    label = "外观",
                    onClick = onToggleTheme,
                )
                Spacer(modifier = Modifier.width(12.dp))
                Icon(
                    imageVector = Icons.AutoMirrored.Outlined.HelpOutline,
                    contentDescription = "帮助",
                    tint = GlassAccentSoft,
                    modifier = Modifier
                        .size(22.dp)
                        .clickable(
                            indication = null,
                            interactionSource = remember { MutableInteractionSource() },
                        ) { showHelp = true },
                )
            }

            PrimaryBroadcastButton(
                broadcasting = broadcasting,
                onClick = { if (broadcasting) onStop() else onStart() },
            )
            Spacer(modifier = Modifier.height(18.dp))
        }
    }

    if (showHelp) {
        AlertDialog(
            onDismissRequest = { showHelp = false },
            title = { Text("使用帮助") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        "Chorus Speaker 1.0.5\n\n" +
                            "1. 与 Mac / Windows Host 同一 Wi-Fi（关闭 VPN）。\n" +
                            "2. 点「开始广播」。\n" +
                            "3. Host 发现本机，或手动填 IP:17482。\n" +
                            "4. 若仍有轻微快慢，用下方微调（正数=手机提前）。",
                    )
                    Text("同步微调：${state.syncTrimMs} ms", fontWeight = FontWeight.SemiBold)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton(onClick = { onTrim(-10) }) { Text("手机慢了 -10") }
                        TextButton(onClick = { onTrim(+10) }) { Text("手机快了 +10") }
                    }
                    Text(
                        "提示：Mac 偏快时点「手机慢了」；Windows 上手机偏快时点「手机快了」。多播几次会自动学习。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = { showHelp = false }) { Text("关闭") }
            },
        )
    }
}

@Composable
private fun LiquidGlassBackground(darkTheme: Boolean) {
    val infinite = rememberInfiniteTransition(label = "bg")
    val phase by infinite.animateFloat(
        initialValue = 0f,
        targetValue = (Math.PI * 2).toFloat(),
        animationSpec = infiniteRepeatable(
            animation = tween(8000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "phase",
    )
    val top = if (darkTheme) Color(0xFF0A0F1A) else Color(0xFFE6F0F8)
    val mid = if (darkTheme) Color(0xFF121C2E) else Color(0xFFDBE6F2)
    val bottom = if (darkTheme) Color(0xFF0D1420) else Color(0xFFEBEFF5)

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.linearGradient(listOf(top, mid, bottom))),
    ) {
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .blur(60.dp),
        ) {
            val w = size.width
            val h = size.height
            drawCircle(
                color = GlassAccentSoft.copy(alpha = if (darkTheme) 0.38f else 0.42f),
                radius = 180.dp.toPx(),
                center = Offset(
                    w * 0.20f + 18f * sin(phase),
                    h * 0.16f + 12f * cos(phase * 0.8f),
                ),
            )
            drawCircle(
                color = GlassMint.copy(alpha = if (darkTheme) 0.30f else 0.34f),
                radius = 150.dp.toPx(),
                center = Offset(
                    w * 0.82f + 14f * cos(phase * 1.1f),
                    h * 0.40f + 16f * sin(phase * 0.7f),
                ),
            )
            drawCircle(
                color = (if (darkTheme) Color(0xFF2E3A52) else Color.White)
                    .copy(alpha = if (darkTheme) 0.42f else 0.55f),
                radius = 120.dp.toPx(),
                center = Offset(w * 0.5f, h * 0.80f + 10f * sin(phase * 1.3f)),
            )
        }
    }
}

@Composable
private fun PulsingOrb(active: Boolean, playing: Boolean) {
    val infinite = rememberInfiniteTransition(label = "orb")
    val pulse by infinite.animateFloat(
        initialValue = 0.94f,
        targetValue = if (active) 1.08f else 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(if (active) 1100 else 2200),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pulse",
    )
    Box(
        modifier = Modifier.size(112.dp),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(100.dp)
                .scale(pulse)
                .clip(CircleShape)
                .background(
                    Brush.radialGradient(
                        colors = listOf(
                            GlassAccentSoft.copy(alpha = if (active) 0.60f else 0.32f),
                            GlassAccent.copy(alpha = 0.10f),
                            Color.Transparent,
                        ),
                    ),
                ),
        )
        Box(
            modifier = Modifier
                .size(74.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.07f))
                .border(1.dp, Color.White.copy(alpha = 0.40f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Outlined.Speaker,
                contentDescription = null,
                tint = GlassAccentSoft,
                modifier = Modifier.size(36.dp),
            )
        }
    }
    @Suppress("UNUSED_EXPRESSION")
    playing
}

@Composable
private fun GlassStatusCard(
    state: SpeakerUiState,
    broadcasting: Boolean,
    showClockChip: Boolean,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 420.dp)
            .clip(RoundedCornerShape(28.dp))
            .background(Color(0xFF1A1F28).copy(alpha = 0.55f))
            .border(
                width = 1.dp,
                brush = Brush.linearGradient(
                    listOf(
                        Color.White.copy(alpha = 0.55f),
                        Color.White.copy(alpha = 0.12f),
                        Color.White.copy(alpha = 0.35f),
                    ),
                ),
                shape = RoundedCornerShape(28.dp),
            )
            .padding(horizontal = 24.dp, vertical = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            text = phaseLabel(state.phase),
            fontSize = 20.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White,
            textAlign = TextAlign.Center,
        )
        Text(
            text = state.status,
            fontSize = 15.sp,
            color = Color.White.copy(alpha = 0.55f),
            textAlign = TextAlign.Center,
            modifier = Modifier.widthIn(max = 280.dp),
        )

        if (broadcasting && state.hostName == null && state.localAddress != null) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = "本机地址",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White.copy(alpha = 0.45f),
                )
                Text(
                    text = state.localAddress,
                    color = GlassAccentSoft,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center,
                )
                Text(
                    text = "企业网若无法发现，请在 Host 手动连接此地址",
                    fontSize = 13.sp,
                    color = Color.White.copy(alpha = 0.45f),
                    textAlign = TextAlign.Center,
                )
            }
        }

        if (state.hostName != null || showClockChip) {
            // Centered pair of capsules. Host name is width-capped so the clock chip
            // is never squeezed into an empty vertical sliver.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                state.hostName?.let {
                    MetricChip(title = "主机", value = it, valueMaxWidth = 148.dp)
                }
                if (showClockChip) {
                    MetricChip(title = "时钟", value = "已校准")
                }
            }
        }

        state.errorMessage?.let {
            Text(
                text = it,
                color = Color(0xFFFF8A80),
                fontSize = 13.sp,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun MetricChip(
    title: String,
    value: String,
    valueMaxWidth: Dp = Dp.Unspecified,
) {
    val shape = RoundedCornerShape(999.dp)
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .clip(shape)
            .background(Color.White.copy(alpha = 0.10f))
            .border(1.dp, Color.White.copy(alpha = 0.50f), shape)
            .padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        Text(
            text = title,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White.copy(alpha = 0.55f),
            maxLines = 1,
        )
        Text(
            text = value,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = if (valueMaxWidth != Dp.Unspecified) {
                Modifier.widthIn(max = valueMaxWidth)
            } else {
                Modifier
            },
        )
    }
}

@Composable
private fun PrimaryBroadcastButton(broadcasting: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(50.dp)
            .clip(RoundedCornerShape(50))
            .background(GlassAccent)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = if (broadcasting) "停止" else "开始广播",
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White,
        )
    }
}

@Composable
private fun UtilityLink(
    icon: @Composable () -> Unit,
    label: String,
    onClick: () -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.clickable(
            indication = null,
            interactionSource = remember { MutableInteractionSource() },
            onClick = onClick,
        ),
    ) {
        icon()
        Spacer(modifier = Modifier.size(4.dp))
        Text(label, color = GlassAccentSoft, style = MaterialTheme.typography.bodyMedium)
    }
}

private fun phaseLabel(phase: SpeakerPhase): String =
    when (phase) {
        SpeakerPhase.IDLE -> "未开始"
        SpeakerPhase.ADVERTISING -> "可发现"
        SpeakerPhase.CONNECTED -> "已连接"
        SpeakerPhase.READY -> "就绪"
        SpeakerPhase.PLAYING -> "播放中"
        SpeakerPhase.ERROR -> "错误"
    }
