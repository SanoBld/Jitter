package com.sanobld.jitter

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.graphics.ColorUtils
import androidx.core.view.WindowCompat

private fun tone(h: Float, s: Float, l: Float) = Color(ColorUtils.HSLToColor(floatArrayOf(h, s, l)))

private fun seedScheme(seed: Color, dark: Boolean): ColorScheme {
    val hsl = FloatArray(3)
    ColorUtils.colorToHSL(seed.toArgb(), hsl)
    val h = hsl[0]
    val th = (h + 60f) % 360f
    return if (!dark) lightColorScheme(
        primary = tone(h, .6f, .40f), onPrimary = Color.White,
        primaryContainer = tone(h, .7f, .90f), onPrimaryContainer = tone(h, .7f, .12f),
        secondary = tone(h, .25f, .40f), onSecondary = Color.White,
        secondaryContainer = tone(h, .3f, .90f), onSecondaryContainer = tone(h, .3f, .12f),
        tertiary = tone(th, .35f, .40f), onTertiary = Color.White,
        tertiaryContainer = tone(th, .4f, .90f), onTertiaryContainer = tone(th, .4f, .12f),
        background = tone(h, .2f, .98f), onBackground = tone(h, .1f, .10f),
        surface = tone(h, .2f, .98f), onSurface = tone(h, .1f, .10f),
        surfaceVariant = tone(h, .2f, .90f), onSurfaceVariant = tone(h, .1f, .30f),
        outline = tone(h, .08f, .50f), outlineVariant = tone(h, .15f, .80f),
        surfaceContainerLowest = Color.White, surfaceContainerLow = tone(h, .2f, .96f),
        surfaceContainer = tone(h, .2f, .94f), surfaceContainerHigh = tone(h, .2f, .92f),
        surfaceContainerHighest = tone(h, .2f, .90f),
    ) else darkColorScheme(
        primary = tone(h, .8f, .80f), onPrimary = tone(h, .7f, .20f),
        primaryContainer = tone(h, .5f, .30f), onPrimaryContainer = tone(h, .8f, .90f),
        secondary = tone(h, .3f, .78f), onSecondary = tone(h, .3f, .20f),
        secondaryContainer = tone(h, .2f, .30f), onSecondaryContainer = tone(h, .3f, .90f),
        tertiary = tone(th, .5f, .80f), onTertiary = tone(th, .4f, .20f),
        tertiaryContainer = tone(th, .3f, .30f), onTertiaryContainer = tone(th, .5f, .90f),
        background = tone(h, .12f, .08f), onBackground = tone(h, .1f, .90f),
        surface = tone(h, .12f, .08f), onSurface = tone(h, .1f, .90f),
        surfaceVariant = tone(h, .12f, .28f), onSurfaceVariant = tone(h, .1f, .80f),
        outline = tone(h, .08f, .60f), outlineVariant = tone(h, .12f, .28f),
        surfaceContainerLowest = tone(h, .12f, .05f), surfaceContainerLow = tone(h, .12f, .10f),
        surfaceContainer = tone(h, .12f, .12f), surfaceContainerHigh = tone(h, .12f, .16f),
        surfaceContainerHighest = tone(h, .12f, .20f),
    )
}

@Composable
fun JitterTheme(s: Settings, content: @Composable () -> Unit) {
    val dark = when (s.theme) {
        1 -> false
        2 -> true
        else -> isSystemInDarkTheme()
    }
    val ctx = LocalContext.current
    val scheme = if (s.dynamic && Build.VERSION.SDK_INT >= 31) {
        if (dark) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)
    } else {
        seedScheme(Color(SEEDS[s.seed.coerceIn(0, SEEDS.size - 1)]), dark)
    }
    val view = LocalView.current
    SideEffect {
        (view.context as? Activity)?.window?.let { w ->
            val c = WindowCompat.getInsetsController(w, view)
            c.isAppearanceLightStatusBars = !dark
            c.isAppearanceLightNavigationBars = !dark
        }
    }
    MaterialTheme(colorScheme = scheme, typography = Typography(), content = content)
}
