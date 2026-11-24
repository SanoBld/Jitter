package com.sanobld.jitter

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Business
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Devices
import androidx.compose.material.icons.rounded.Dns
import androidx.compose.material.icons.rounded.Lan
import androidx.compose.material.icons.rounded.LocationOn
import androidx.compose.material.icons.rounded.MyLocation
import androidx.compose.material.icons.rounded.NetworkCheck
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.SignalCellularAlt
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material.icons.rounded.Wifi
import androidx.compose.material.icons.rounded.Sensors
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearWavyProgressIndicator
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun TestScreen(vm: JitterViewModel) {
    val t by vm.test.collectAsStateWithLifecycle()
    val s by vm.settings.collectAsStateWithLifecycle()
    val ip by vm.ipLoc.collectAsStateWithLifecycle()
    val isp by vm.isp.collectAsStateWithLifecycle()
    val gps by vm.gpsCity.collectAsStateWithLifecycle()
    val net by vm.net.collectAsStateWithLifecycle()
    val busy by vm.locBusy.collectAsStateWithLifecycle()
    var sheet by remember { mutableIntStateOf(0) }
    val unit = unitOf(s)
    val server = vm.currentServer(s)
    val gpsActive = s.useGps && gps.isNotEmpty()
    val where = if (gpsActive) gps else ip
    val c = MaterialTheme.colorScheme

    val view = LocalView.current
    DisposableEffect(t.testing) {
        view.keepScreenOn = t.testing
        onDispose { view.keepScreenOn = false }
    }
    LaunchedEffect(Unit) { vm.refreshNet() }

    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = 600.dp).fillMaxHeight()) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                AssistChip(
                    onClick = { vm.refreshLocation() },
                    shape = MaterialTheme.shapes.large,
                    label = { Text(if (busy) tr("detecting") else where.ifEmpty { tr("unknown_loc") }) },
                    leadingIcon = { Icon(if (gpsActive) Icons.Rounded.MyLocation else Icons.Rounded.LocationOn, null, Modifier.size(18.dp)) },
                )
                if (isp.isNotEmpty()) {
                    AssistChip(
                        onClick = {}, shape = MaterialTheme.shapes.large, label = { Text(isp) },
                        leadingIcon = { Icon(Icons.Rounded.Business, null, Modifier.size(18.dp)) },
                    )
                }
                if (net.conn.isNotEmpty()) {
                    val (label, icon) = when (net.conn) {
                        "wifi" -> tr("conn_wifi") to Icons.Rounded.Wifi
                        "mobile" -> tr("conn_mobile") to Icons.Rounded.SignalCellularAlt
                        else -> tr("conn_eth") to Icons.Rounded.Lan
                    }
                    AssistChip(
                        onClick = {}, shape = MaterialTheme.shapes.large, label = { Text(label) },
                        leadingIcon = { Icon(icon, null, Modifier.size(18.dp)) },
                    )
                }
                if (net.localIp.isNotEmpty()) {
                    AssistChip(
                        onClick = {}, shape = MaterialTheme.shapes.large, label = { Text(net.localIp) },
                        leadingIcon = { Icon(Icons.Rounded.Devices, null, Modifier.size(18.dp)) },
                    )
                }
            }

            t.error?.let { Banner(tr(it), error = true) }
            t.warning?.let { Banner(tr(it), error = false) }

            SpeedGauge(
                mbps = t.gauge,
                unit = unit,
                grade = if (t.phase == Phase.DONE) gradeFor(t.dl) else null,
                serverLine = "${server.flag} ${server.location}",
            )

            PhaseIndicator(t)

            Surface(shape = MaterialTheme.shapes.extraLarge, color = c.surfaceContainer, modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(tr("chart_title"), style = MaterialTheme.typography.labelLarge, color = c.primary)
                        val top = (t.dlPoints + t.points).maxOrNull() ?: 0.0
                        Text("max ${unit.fmt(top)} ${unit.label}", style = MaterialTheme.typography.labelMedium, color = c.onSurfaceVariant)
                    }
                    LiveChart(
                        t.points,
                        if (t.phase == Phase.UPLOAD) c.secondary else c.primary,
                        Modifier.fillMaxWidth().height(140.dp).padding(top = 8.dp),
                        ghost = t.dlPoints,
                        ghostColor = c.primary.copy(alpha = 0.5f),
                        grid = c.outlineVariant,
                    )
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    StatCard(
                        0, Icons.Rounded.ArrowDownward, tr("down"), unit.fmt(t.dl), unit.label,
                        c.primaryContainer, c.onPrimaryContainer, c.primary, c.onPrimary,
                        RoundedCornerShape(topStart = 44.dp, topEnd = 16.dp, bottomEnd = 16.dp, bottomStart = 16.dp),
                        Modifier.weight(1f),
                    )
                    StatCard(
                        1, Icons.Rounded.ArrowUpward, tr("up"), unit.fmt(t.ul), unit.label,
                        c.secondaryContainer, c.onSecondaryContainer, c.secondary, c.onSecondary,
                        RoundedCornerShape(topStart = 16.dp, topEnd = 44.dp, bottomEnd = 16.dp, bottomStart = 16.dp),
                        Modifier.weight(1f),
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    StatCard(
                        2, Icons.Rounded.NetworkCheck, tr("ping"), "${t.ping}", "ms",
                        c.tertiaryContainer, c.onTertiaryContainer, c.tertiary, c.onTertiary,
                        RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp, bottomEnd = 16.dp, bottomStart = 44.dp),
                        Modifier.weight(1f),
                    )
                    StatCard(
                        3, Icons.Rounded.Sensors, tr("jitter"), "${t.jitter}", "ms",
                        c.surfaceContainerHigh, c.onSurface, c.error, c.onError,
                        RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp, bottomEnd = 44.dp, bottomStart = 16.dp),
                        Modifier.weight(1f),
                    )
                }
            }

            if (!t.testing) {
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    AssistChip(
                        onClick = { sheet = 1 }, shape = MaterialTheme.shapes.large,
                        label = { Text("${server.flag} ${server.name}") },
                        leadingIcon = { Icon(Icons.Rounded.Dns, null, Modifier.size(18.dp)) },
                    )
                    AssistChip(
                        onClick = { sheet = 2 }, shape = MaterialTheme.shapes.large,
                        label = { Text(if (s.linked) fmtDur(s.dlSecs) else "↓${fmtDur(s.dlSecs)} ↑${fmtDur(s.ulSecs)}") },
                        leadingIcon = { Icon(Icons.Rounded.Timer, null, Modifier.size(18.dp)) },
                    )
                    AssistChip(
                        onClick = { sheet = 3 }, shape = MaterialTheme.shapes.large,
                        label = { Text(unit.label) },
                        leadingIcon = { Icon(Icons.Rounded.Speed, null, Modifier.size(18.dp)) },
                    )
                    AssistChip(
                        onClick = { sheet = 4 }, shape = MaterialTheme.shapes.large,
                        label = { Text(if (s.conns <= 0) tr("auto") else "${s.conns}×") },
                        leadingIcon = { Icon(Icons.Rounded.Tune, null, Modifier.size(18.dp)) },
                    )
                }
            }

        }
        Surface(color = c.surface, tonalElevation = 2.dp) {
            Column(Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
            if (t.testing) {
                Button(
                    onClick = { vm.stop() },
                    shapes = ButtonDefaults.shapes(),
                    modifier = Modifier.fillMaxWidth().height(64.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = c.errorContainer, contentColor = c.onErrorContainer),
                ) {
                    Icon(Icons.Rounded.Close, null)
                    Spacer(Modifier.width(8.dp))
                    Text(tr("stop"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                }
            } else {
                Button(
                    onClick = { vm.start() },
                    shapes = ButtonDefaults.shapes(),
                    modifier = Modifier.fillMaxWidth().height(64.dp),
                ) {
                    Icon(Icons.Rounded.PlayArrow, null)
                    Spacer(Modifier.width(8.dp))
                    Text(tr("start"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                }
            }
            }
        }
        }
    }
    Pickers(vm, sheet) { sheet = 0 }
}

@Composable
private fun Banner(text: String, error: Boolean) {
    val c = MaterialTheme.colorScheme
    Surface(
        Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        color = if (error) c.errorContainer else c.tertiaryContainer,
        contentColor = if (error) c.onErrorContainer else c.onTertiaryContainer,
    ) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Warning, null, Modifier.size(20.dp))
            Spacer(Modifier.width(10.dp))
            Text(text, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun PhaseIndicator(t: TestState) {
    val c = MaterialTheme.colorScheme
    val live = t.phase == Phase.DOWNLOAD || t.phase == Phase.UPLOAD
    val working = t.testing && !live
    val step = when (t.phase) {
        Phase.PING -> 0
        Phase.DOWNLOAD -> 1
        Phase.UPLOAD -> 2
        Phase.DONE -> 3
        else -> -1
    }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        LinearWavyProgressIndicator(progress = { t.progress }, modifier = Modifier.fillMaxWidth())
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            listOf("phase_ping", "phase_download", "phase_upload").forEachIndexed { i, key ->
                val active = step == i
                val done = step > i
                Text(
                    tr(key),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = if (active || done) FontWeight.ExtraBold else FontWeight.Medium,
                    color = if (active) c.primary else if (done) c.onSurface else c.onSurfaceVariant.copy(alpha = 0.6f),
                )
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            if (working) {
                LoadingIndicator(Modifier.size(32.dp))
                Spacer(Modifier.width(8.dp))
            }
            val time = "%02d:%02d".format(t.elapsed / 60, t.elapsed % 60)
            Text(
                if (live) "${tr(t.phase.key)}  $time" else tr(t.phase.key),
                style = MaterialTheme.typography.labelLarge,
                color = c.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun StatCard(
    kind: Int,
    icon: ImageVector,
    label: String,
    value: String,
    unit: String,
    container: Color,
    onContainer: Color,
    badge: Color,
    onBadge: Color,
    shape: Shape,
    modifier: Modifier,
) {
    Surface(modifier, shape = shape, color = container, contentColor = onContainer) {
        Column(Modifier.fillMaxWidth().padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                ShapeBadge(kind, icon, badge, onBadge, 36.dp)
                Text(label, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
            }
            Spacer(Modifier.height(10.dp))
            Text(value, style = MaterialTheme.typography.headlineMedium, maxLines = 1)
            Text(unit, style = MaterialTheme.typography.labelMedium, color = onContainer.copy(alpha = 0.7f))
        }
    }
}
