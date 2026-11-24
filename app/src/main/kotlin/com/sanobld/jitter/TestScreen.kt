@file:OptIn(ExperimentalMaterial3Api::class)

package com.sanobld.jitter

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlin.math.ln
import kotlin.math.max

private fun gaugeFrac(mbps: Double) = (ln(1 + mbps) / ln(2001.0)).toFloat().coerceIn(0f, 1f)

@Composable
fun TestScreen(vm: JitterViewModel) {
    val t by vm.test.collectAsStateWithLifecycle()
    val s by vm.settings.collectAsStateWithLifecycle()
    val ip by vm.ipLoc.collectAsStateWithLifecycle()
    val isp by vm.isp.collectAsStateWithLifecycle()
    val gps by vm.gpsCity.collectAsStateWithLifecycle()
    val busy by vm.locBusy.collectAsStateWithLifecycle()
    var sheet by remember { mutableIntStateOf(0) }
    val unit = SpeedUnit.entries[s.unit.coerceIn(0, SpeedUnit.entries.size - 1)]
    val server = vm.currentServer(s)
    val where = if (s.useGps && gps.isNotEmpty()) gps else ip

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AssistChip(
                onClick = { vm.refreshLocation() },
                label = { Text(if (busy) "Detecting…" else where.ifEmpty { "Unknown location" }) },
                leadingIcon = { Icon(Icons.Filled.Place, null, Modifier.size(18.dp)) },
            )
            if (isp.isNotEmpty()) AssistChip(onClick = {}, label = { Text(isp) })
            if (t.conn.isNotEmpty()) AssistChip(onClick = {}, label = { Text(t.conn) })
        }

        t.error?.let { Banner(it, error = true) }
        t.warning?.let { Banner(it, error = false) }

        Gauge(t.gauge, unit, if (t.phase == Phase.DONE) gradeFor(t.dl) else null, server)
        PhaseBar(t)
        LiveChart(
            t.points,
            if (t.phase == Phase.UPLOAD) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.primary,
            Modifier.fillMaxWidth().height(56.dp),
        )

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            StatCard("↓ DOWN", unit.fmt(t.dl), unit.label, MaterialTheme.colorScheme.primary, Modifier.weight(1f))
            StatCard("↑ UP", unit.fmt(t.ul), unit.label, MaterialTheme.colorScheme.secondary, Modifier.weight(1f))
            StatCard("PING", "${t.ping}", "ms", MaterialTheme.colorScheme.tertiary, Modifier.weight(1f))
            StatCard("JITTER", "${t.jitter}", "ms", MaterialTheme.colorScheme.error, Modifier.weight(1f))
        }

        if (!t.testing) {
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AssistChip(onClick = { sheet = 1 }, label = { Text("${server.flag} ${server.name}") })
                AssistChip(
                    onClick = { sheet = 2 },
                    label = { Text(if (s.linked) fmtDur(s.dlSecs) else "↓${fmtDur(s.dlSecs)} ↑${fmtDur(s.ulSecs)}") },
                )
                AssistChip(onClick = { sheet = 3 }, label = { Text(unit.label) })
                AssistChip(onClick = { sheet = 4 }, label = { Text("${s.conns}× conns") })
            }
        }

        if (t.testing) {
            FilledTonalButton(
                onClick = { vm.stop() },
                modifier = Modifier.fillMaxWidth().height(56.dp),
                colors = ButtonDefaults.filledTonalButtonColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer,
                    contentColor = MaterialTheme.colorScheme.onErrorContainer,
                ),
            ) {
                Icon(Icons.Filled.Close, null)
                Spacer(Modifier.width(8.dp))
                Text("STOP", fontWeight = FontWeight.Bold)
            }
        } else {
            Button(onClick = { vm.start() }, modifier = Modifier.fillMaxWidth().height(56.dp)) {
                Icon(Icons.Filled.PlayArrow, null)
                Spacer(Modifier.width(8.dp))
                Text("START TEST", fontWeight = FontWeight.Bold)
            }
        }
    }
    Pickers(vm, sheet) { sheet = 0 }
}

fun fmtDur(s: Int) = if (s == 0) "∞" else if (s >= 60) "${s / 60}m" else "${s}s"

@Composable
private fun Banner(text: String, error: Boolean) {
    val c = MaterialTheme.colorScheme
    Card(
        Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = if (error) c.errorContainer else c.tertiaryContainer,
            contentColor = if (error) c.onErrorContainer else c.onTertiaryContainer,
        ),
    ) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Warning, null, Modifier.size(20.dp))
            Spacer(Modifier.width(10.dp))
            Text(text, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun Gauge(mbps: Double, unit: SpeedUnit, grade: Grade?, server: SpeedServer) {
    val frac by animateFloatAsState(gaugeFrac(mbps), tween(350), label = "gauge")
    val track = MaterialTheme.colorScheme.surfaceContainerHighest
    val color = MaterialTheme.colorScheme.primary
    Box(Modifier.size(260.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val sw = 18.dp.toPx()
            val inset = sw / 2 + 4.dp.toPx()
            val topLeft = Offset(inset, inset)
            val sz = Size(size.width - 2 * inset, size.height - 2 * inset)
            drawArc(track, 150f, 240f, false, topLeft, sz, style = Stroke(sw, cap = StrokeCap.Round))
            if (frac > 0.003f) {
                drawArc(color, 150f, 240f * frac, false, topLeft, sz, style = Stroke(sw, cap = StrokeCap.Round))
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(unit.fmt(mbps), style = MaterialTheme.typography.displayLarge, fontWeight = FontWeight.Bold)
            Text(unit.label, style = MaterialTheme.typography.titleMedium, color = color)
            Spacer(Modifier.height(8.dp))
            Text(
                "${server.flag} ${server.location}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
            if (grade != null) {
                Spacer(Modifier.height(6.dp))
                Text(grade.label, color = grade.color, fontWeight = FontWeight.ExtraBold, style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

@Composable
private fun PhaseBar(t: TestState) {
    val dlDone = t.phase == Phase.UPLOAD || t.phase == Phase.DONE
    val pingDone = dlDone || t.phase == Phase.DOWNLOAD
    val pingP = if (pingDone) 1f else if (t.phase == Phase.PING) 0.5f else 0f
    val dlP = if (dlDone) 1f else if (t.phase == Phase.DOWNLOAD) ((t.progress - 0.08f) / 0.46f).coerceIn(0f, 1f) else 0f
    val ulP = if (t.phase == Phase.DONE) 1f else if (t.phase == Phase.UPLOAD) ((t.progress - 0.54f) / 0.46f).coerceIn(0f, 1f) else 0f
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            LinearProgressIndicator({ pingP }, Modifier.weight(1f).height(6.dp), color = MaterialTheme.colorScheme.tertiary, strokeCap = StrokeCap.Round)
            LinearProgressIndicator({ dlP }, Modifier.weight(5f).height(6.dp), color = MaterialTheme.colorScheme.primary, strokeCap = StrokeCap.Round)
            LinearProgressIndicator({ ulP }, Modifier.weight(5f).height(6.dp), color = MaterialTheme.colorScheme.secondary, strokeCap = StrokeCap.Round)
        }
        val live = t.phase == Phase.DOWNLOAD || t.phase == Phase.UPLOAD
        val time = "%02d:%02d".format(t.elapsed / 60, t.elapsed % 60)
        Text(
            if (live) "${t.phase.label}  $time" else t.phase.label,
            Modifier.fillMaxWidth(),
            textAlign = TextAlign.Center,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
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
            moveTo(pt(0).x, pt(0).y)
            for (i in 1 until points.size) lineTo(pt(i).x, pt(i).y)
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

@Composable
private fun StatCard(label: String, value: String, unit: String, color: Color, modifier: Modifier) {
    Card(
        modifier,
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
    ) {
        Column(Modifier.padding(horizontal = 8.dp, vertical = 12.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(label, style = MaterialTheme.typography.labelSmall, color = color, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(4.dp))
            Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.ExtraBold, maxLines = 1)
            Text(unit, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
