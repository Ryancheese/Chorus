package com.chorus.speaker.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// Matches iOS GlassTheme
val GlassAccent = Color(0xFF2E85DB)
val GlassAccentSoft = Color(0xFF59B8EB)
val GlassMint = Color(0xFF73D1C7)
val GlassBrand = Color(0xFF1F242E)

private val DarkColors = darkColorScheme(
    primary = GlassAccent,
    onPrimary = Color.White,
    secondary = GlassAccentSoft,
    background = Color(0xFF0A0F1A),
    onBackground = Color.White,
    surface = Color(0xFF141A24),
    onSurface = Color.White,
)

private val LightColors = lightColorScheme(
    primary = GlassAccent,
    onPrimary = Color.White,
    secondary = Color(0xFF3A7AB8),
    background = Color(0xFFE6F0F8),
    onBackground = Color(0xFF1A1A1A),
    surface = Color(0xFFF0F5FA),
    onSurface = Color(0xFF1A1A1A),
)

// Sized to match iOS Speaker compact layout (.system 42 / title3 / title2).
private val AppTypography = Typography(
    displayLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Bold,
        fontSize = 36.sp,
        letterSpacing = (-0.4).sp,
    ),
    headlineMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 20.sp,
    ),
    titleMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Medium,
        fontSize = 17.sp,
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 15.sp,
        lineHeight = 20.sp,
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 13.sp,
    ),
    labelLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 16.sp,
    ),
    labelSmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 11.sp,
    ),
)

@Composable
fun ChorusSpeakerTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = AppTypography,
        content = content,
    )
}
