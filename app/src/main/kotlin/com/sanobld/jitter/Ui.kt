package com.sanobld.jitter

import android.content.Context
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.view.View
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonGroupDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialShapes
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.ToggleButton
import androidx.compose.material3.toShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.BoundingBox
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.CustomZoomButtonsController
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.CopyrightOverlay
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.TilesOverlay
import kotlin.math.ln
import kotlin.math.max

// ─────────────────────────────────────────── helpers

fun fmtDur(s: Int) = if (s == 0) "∞" else if (s >= 60 && s % 60 == 0) "${s / 60}m" else "${s}s"

fun unitOf(s: Settings): SpeedUnit = SpeedUnit.entries[s.unit.coerceIn(0, SpeedUnit.entries.size - 1)]

val METRIC_KEYS = listOf("m_down", "m_up", "m_ping", "m_jitter")

fun metric(e: Entry, m: Int): Double = when (m) {
    0 -> e.dl
    1 -> e.ul
    2 -> e.ping.toDouble()
    else -> e.jitter.toDouble()
}

@Composable
fun metricColor(m: Int): Color = when (m) {
    0 -> MaterialTheme.colorScheme.primary
    1 -> MaterialTheme.colorScheme.secondary
    2 -> MaterialTheme.colorScheme.tertiary
    else -> MaterialTheme.colorScheme.error
}

fun metricText(v: Double, m: Int, unit: SpeedUnit) =
    if (m < 2) "${unit.fmt(v)} ${unit.label}" else "${v.toInt()} ms"

// ─────────────────────────────────────────── Material 3 Expressive shapes

/** Decorative polygon shapes from the Material 3 Expressive shape library. */
@Composable
fun polygonShape(kind: Int): Shape = when (kind % 6) {
    0 -> MaterialShapes.Cookie9Sided.toShape()
    1 -> MaterialShapes.Sunny.toShape()
    2 -> MaterialShapes.Clover4Leaf.toShape()
    3 -> MaterialShapes.SoftBurst.toShape()
    4 -> MaterialShapes.Cookie12Sided.toShape()
    else -> MaterialShapes.Flower.toShape()
}

@Composable
fun ShapeBadge(kind: Int, icon: ImageVector, container: Color, content: Color, size: Dp = 44.dp, modifier: Modifier = Modifier) {
    Box(
        modifier.size(size).clip(polygonShape(kind)).background(container),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, tint = content, modifier = Modifier.size(size * 0.5f)) }
}

// ─────────────────────────────────────────── gauge + chart

private fun gaugeFrac(mbps: Double) = (ln(1 + mbps) / ln(2001.0)).toFloat().coerceIn(0f, 1f)

@Composable
fun SpeedGauge(mbps: Double, unit: SpeedUnit, grade: Grade?, serverLine: String, modifier: Modifier = Modifier) {
    val frac by animateFloatAsState(gaugeFrac(mbps), MaterialTheme.motionScheme.defaultSpatialSpec(), label = "gauge")
    val c = MaterialTheme.colorScheme
    val spin = rememberInfiniteTransition(label = "spin")
    val angle by spin.animateFloat(0f, 360f, infiniteRepeatable(tween(36000, easing = LinearEasing), RepeatMode.Restart), label = "angle")
    Box(modifier.size(300.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val sw = 22.dp.toPx()
            val inset = sw / 2 + 4.dp.toPx()
            val topLeft = Offset(inset, inset)
            val sz = Size(size.width - 2 * inset, size.height - 2 * inset)
            drawArc(c.surfaceContainerHighest, 150f, 240f, false, topLeft, sz, style = Stroke(sw, cap = StrokeCap.Round))
            val f = frac.coerceIn(0f, 1f)
            if (f > 0.004f) {
                drawArc(c.primary, 150f, 240f * f, false, topLeft, sz, style = Stroke(sw, cap = StrokeCap.Round))
            }
        }
        // Slowly rotating cookie behind the value, rotated on its own so the text stays upright.
        Box(
            Modifier.size(196.dp).rotate(angle).clip(MaterialShapes.Cookie12Sided.toShape()).background(c.primaryContainer),
        )
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                unit.fmt(mbps),
                style = MaterialTheme.typography.displayMedium,
                color = c.onPrimaryContainer,
                maxLines = 1,
                softWrap = false,
            )
            Text(unit.label, style = MaterialTheme.typography.titleMedium, color = c.onPrimaryContainer)
            Spacer(Modifier.height(4.dp))
            Text(
                serverLine,
                style = MaterialTheme.typography.labelSmall,
                color = c.onPrimaryContainer.copy(alpha = 0.7f),
                textAlign = TextAlign.Center,
                maxLines = 1,
                modifier = Modifier.padding(horizontal = 56.dp),
            )
        }
        if (grade != null) {
            Surface(
                modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 8.dp),
                shape = MaterialTheme.shapes.large,
                color = grade.color,
            ) {
                Text(
                    tr(grade.key),
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                    color = Color.White,
                    fontWeight = FontWeight.ExtraBold,
                    style = MaterialTheme.typography.labelLarge,
                )
            }
        }
    }
}

@Composable
fun LiveChart(points: List<Double>, color: Color, modifier: Modifier) {
    Canvas(modifier) {
        if (points.size < 2) return@Canvas
        val mx = max(points.max() * 1.2, 1.0)
        val w = size.width
        val h = size.height
        fun pt(i: Int) = Offset(w * i / (points.size - 1), (h - points[i] / mx * h * 0.9 - h * 0.05).toFloat())
        val line = Path().apply {
            val p0 = pt(0)
            moveTo(p0.x, p0.y)
            for (i in 1 until points.size) {
                val a = pt(i - 1)
                val b = pt(i)
                val mid = (a.x + b.x) / 2
                cubicTo(mid, a.y, mid, b.y, b.x, b.y)
            }
        }
        val fill = Path().apply {
            addPath(line)
            lineTo(w, h)
            lineTo(0f, h)
            close()
        }
        drawPath(fill, color.copy(alpha = 0.18f))
        drawPath(line, color, style = Stroke(3.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

// ─────────────────────────────────────────── components

/** Connected button group (Material 3 Expressive) used as a single-choice selector. */
@Composable
fun ChoiceGroup(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(ButtonGroupDefaults.ConnectedSpaceBetween)) {
        options.forEachIndexed { i, label ->
            ToggleButton(
                checked = selected == i,
                onCheckedChange = { onSelect(i) },
                modifier = Modifier.weight(1f).semantics { role = Role.RadioButton },
                shapes = when (i) {
                    0 -> ButtonGroupDefaults.connectedLeadingButtonShapes()
                    options.lastIndex -> ButtonGroupDefaults.connectedTrailingButtonShapes()
                    else -> ButtonGroupDefaults.connectedMiddleButtonShapes()
                },
            ) { Text(label, maxLines = 1) }
        }
    }
}

@Composable
fun Section(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column {
        Text(
            title,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(start = 16.dp, bottom = 8.dp),
        )
        Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainer) {
            Column(Modifier.fillMaxWidth()) { content() }
        }
    }
}

@Composable
fun SettingRow(
    title: String,
    sub: String? = null,
    icon: ImageVector? = null,
    badge: Int = 0,
    onClick: (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    val c = MaterialTheme.colorScheme
    ListItem(
        modifier = if (onClick != null) Modifier.clickableRow(onClick) else Modifier,
        headlineContent = { Text(title) },
        supportingContent = if (sub != null) { { Text(sub) } } else null,
        leadingContent = if (icon != null) { { ShapeBadge(badge, icon, c.secondaryContainer, c.onSecondaryContainer, 40.dp) } } else null,
        trailingContent = trailing,
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}

private fun Modifier.clickableRow(onClick: () -> Unit): Modifier = this.then(Modifier.clickable(onClick = onClick))

/** Switch with a check icon in the thumb when on (Material 3 Expressive style). */
@Composable
fun JitterSwitch(checked: Boolean, onChange: (Boolean) -> Unit, enabled: Boolean = true) {
    androidx.compose.material3.Switch(
        checked = checked,
        onCheckedChange = onChange,
        enabled = enabled,
        thumbContent = if (checked) {
            { Icon(Icons.Rounded.Check, null, Modifier.size(androidx.compose.material3.SwitchDefaults.IconSize)) }
        } else null,
    )
}

@Composable
fun NumberDialog(
    title: String,
    hint: String,
    initial: String,
    maxLen: Int,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
) {
    var v by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                Text(hint, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = v,
                    onValueChange = { s -> v = s.filter { it.isDigit() }.take(maxLen) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    shape = MaterialTheme.shapes.large,
                )
            }
        },
        confirmButton = { TextButton(onClick = { onConfirm(v) }) { Text(tr("ok")) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(tr("cancel")) } },
    )
}

// ─────────────────────────────────────────── OpenStreetMap

private fun dot(ctx: Context, color: Color): Drawable {
    val d = ctx.resources.displayMetrics.density
    return GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(color.toArgb())
        setStroke((3 * d).toInt(), android.graphics.Color.WHITE)
        setSize((24 * d).toInt(), (24 * d).toInt())
    }
}

/** Entries without a GPS position are ignored. [interactive] = false gives a static mini-map. */
@Composable
fun OsmMap(
    entries: List<Entry>,
    dark: Boolean,
    interactive: Boolean,
    modifier: Modifier = Modifier,
    onSelect: ((Entry) -> Unit)? = null,
) {
    val ctx = LocalContext.current
    val map = remember {
        MapView(ctx).apply {
            setTileSource(TileSourceFactory.MAPNIK)
            zoomController.setVisibility(CustomZoomButtonsController.Visibility.NEVER)
            minZoomLevel = 2.0
            controller.setZoom(3.0)
        }
    }
    val owner = LocalLifecycleOwner.current
    DisposableEffect(owner) {
        val obs = LifecycleEventObserver { _, e ->
            when (e) {
                Lifecycle.Event.ON_RESUME -> map.onResume()
                Lifecycle.Event.ON_PAUSE -> map.onPause()
                else -> {}
            }
        }
        owner.lifecycle.addObserver(obs)
        onDispose {
            owner.lifecycle.removeObserver(obs)
            map.onDetach()
        }
    }
    val applied = remember { IntArray(1) { Int.MIN_VALUE } }
    AndroidView(
        factory = { map },
        modifier = modifier,
        update = { m ->
            val key = 31 * (31 * entries.hashCode() + dark.hashCode()) + interactive.hashCode()
            if (applied[0] == key) return@AndroidView
            applied[0] = key
            m.setMultiTouchControls(interactive)
            m.setOnTouchListener(if (interactive) null else View.OnTouchListener { _, _ -> true })
            m.overlayManager.tilesOverlay.setColorFilter(if (dark) TilesOverlay.INVERT_COLORS else null)
            m.overlays.clear()
            m.overlays.add(CopyrightOverlay(ctx))
            val pts = entries.filter { it.hasPos }
            val geo = pts.map { GeoPoint(it.lat!!, it.lng!!) }
            pts.forEachIndexed { i, e ->
                m.overlays.add(
                    Marker(m).apply {
                        position = geo[i]
                        setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
                        icon = dot(ctx, gradeFor(e.dl).color)
                        setOnMarkerClickListener { _, _ ->
                            onSelect?.invoke(e)
                            true
                        }
                    }
                )
            }
            if (geo.isNotEmpty()) {
                val box = BoundingBox.fromGeoPoints(geo)
                if (geo.size == 1 || (box.latitudeSpan < 0.01 && box.longitudeSpan < 0.01)) {
                    m.controller.setZoom(12.0)
                    m.controller.setCenter(box.centerWithDateLine)
                } else {
                    m.post { m.zoomToBoundingBox(box, false, 96) }
                }
            }
            m.invalidate()
        },
    )
}
