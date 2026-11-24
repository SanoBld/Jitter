@file:OptIn(ExperimentalMaterial3Api::class)

package com.sanobld.jitter

import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlin.math.max

private val METRICS = listOf("Down", "Up", "Ping", "Jitter")

private fun metric(e: Entry, m: Int): Double = when (m) {
    0 -> e.dl
    1 -> e.ul
    2 -> e.ping.toDouble()
    else -> e.jitter.toDouble()
}

@Composable
private fun metricColor(m: Int): Color = when (m) {
    0 -> MaterialTheme.colorScheme.primary
    1 -> MaterialTheme.colorScheme.secondary
    2 -> MaterialTheme.colorScheme.tertiary
    else -> MaterialTheme.colorScheme.error
}

private fun metricText(v: Double, m: Int, unit: SpeedUnit) =
    if (m < 2) "${unit.fmt(v)} ${unit.label}" else "${v.toInt()} ms"

@Composable
fun HistoryScreen(vm: JitterViewModel) {
    val ctx = LocalContext.current
    val h by vm.history.collectAsStateWithLifecycle()
    val s by vm.settings.collectAsStateWithLifecycle()
    val unit = SpeedUnit.entries[s.unit.coerceIn(0, SpeedUnit.entries.size - 1)]
    var trend by remember { mutableStateOf(false) }
    var detail by remember { mutableStateOf<Entry?>(null) }
    var confirm by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
        Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Logs", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text("${h.size} tests", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(onClick = {
                if (h.isEmpty()) {
                    vm.toast("No data to export")
                } else {
                    val i = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_SUBJECT, "Jitter results.csv")
                        putExtra(Intent.EXTRA_TEXT, vm.exportCsv())
                    }
                    ctx.startActivity(Intent.createChooser(i, "Export CSV"))
                }
            }) { Icon(Icons.Filled.Share, "Export CSV") }
            IconButton(onClick = {
                val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val text = cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text?.toString().orEmpty()
                val n = if (text.isBlank()) 0 else vm.importCsv(text)
                vm.toast(if (n > 0) "$n result(s) imported." else "No valid CSV in clipboard.")
            }) { Icon(Icons.Filled.Add, "Import CSV from clipboard") }
            IconButton(onClick = { if (h.isNotEmpty()) confirm = true }) { Icon(Icons.Filled.Delete, "Clear all") }
        }

        if (h.size >= 2) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                SegmentedButton(selected = !trend, onClick = { trend = false }, shape = SegmentedButtonDefaults.itemShape(0, 2)) { Text("List") }
                SegmentedButton(selected = trend, onClick = { trend = true }, shape = SegmentedButtonDefaults.itemShape(1, 2)) { Text("Trend") }
            }
        }

        when {
            h.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("No tests yet", style = MaterialTheme.typography.titleMedium)
                    Text("Run a speed test to see results here.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            trend && h.size >= 2 -> TrendView(h.reversed(), unit)
            else -> LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxSize()) {
                itemsIndexed(h, key = { _, e -> e.ts + e.server + e.dl }) { _, e ->
                    val state = rememberSwipeToDismissBoxState(confirmValueChange = {
                        if (it == SwipeToDismissBoxValue.EndToStart) {
                            vm.delete(e)
                            true
                        } else false
                    })
                    SwipeToDismissBox(
                        state = state,
                        enableDismissFromStartToEnd = false,
                        backgroundContent = {
                            Box(
                                Modifier.fillMaxSize().background(MaterialTheme.colorScheme.errorContainer, RoundedCornerShape(16.dp)).padding(end = 20.dp),
                                contentAlignment = Alignment.CenterEnd,
                            ) { Icon(Icons.Filled.Delete, null, tint = MaterialTheme.colorScheme.onErrorContainer) }
                        },
                    ) { EntryCard(e, unit) { detail = e } }
                }
                item { Spacer(Modifier.height(12.dp)) }
            }
        }
    }

    if (confirm) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text("Clear all logs?") },
            text = { Text("Delete all test results? This cannot be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    vm.clearHistory()
                    confirm = false
                }) { Text("Delete all", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text("Cancel") } },
        )
    }
    detail?.let { e ->
        ModalBottomSheet(onDismissRequest = { detail = null }) { DetailSheet(e, h, unit) }
    }
}

@Composable
private fun EntryCard(e: Entry, unit: SpeedUnit, onClick: () -> Unit) {
    val g = gradeFor(e.dl)
    Card(
        Modifier.fillMaxWidth().clickable(onClick = onClick),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
    ) {
        Row(Modifier.height(IntrinsicSize.Min)) {
            Box(Modifier.width(6.dp).fillMaxHeight().background(g.color))
            Column(Modifier.padding(14.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(g.label, color = g.color, fontWeight = FontWeight.ExtraBold, style = MaterialTheme.typography.labelMedium)
                    Spacer(Modifier.weight(1f))
                    Text(e.ts, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Spacer(Modifier.height(8.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Mini("↓ DOWN", "${unit.fmt(e.dl)} ${unit.label}", MaterialTheme.colorScheme.primary)
                    Mini("↑ UP", "${unit.fmt(e.ul)} ${unit.label}", MaterialTheme.colorScheme.secondary)
                    Mini("PING", "${e.ping} ms", MaterialTheme.colorScheme.tertiary)
                    Mini("JITTER", "${e.jitter} ms", MaterialTheme.colorScheme.error)
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    "${e.flag} ${e.server}" + if (e.userLoc.isNotEmpty()) "  ·  ${e.userLoc}" else "",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
private fun Mini(label: String, value: String, color: Color) {
    Column {
        Text(label, style = MaterialTheme.typography.labelSmall, color = color, fontWeight = FontWeight.Bold)
        Text(value, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun TrendView(chrono: List<Entry>, unit: SpeedUnit) {
    var m by remember { mutableIntStateOf(0) }
    val vals = chrono.map { metric(it, m) }
    val color = metricColor(m)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            METRICS.forEachIndexed { i, n -> FilterChip(selected = m == i, onClick = { m = i }, label = { Text(n) }) }
        }
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh), shape = RoundedCornerShape(16.dp)) {
            Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                Mini("AVERAGE", metricText(vals.average(), m, unit), color)
                Mini("BEST", metricText(if (m < 2) vals.max() else vals.min(), m, unit), color)
                Mini("WORST", metricText(if (m < 2) vals.min() else vals.max(), m, unit), color)
            }
        }
        LiveChart(vals, color, Modifier.fillMaxWidth().height(200.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(chrono.first().ts, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(chrono.last().ts, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun DetailSheet(e: Entry, all: List<Entry>, unit: SpeedUnit) {
    val g = gradeFor(e.dl)
    Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 32.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(e.ts, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text("${e.flag} ${e.server} · ${e.provider}", style = MaterialTheme.typography.bodyMedium)
                Text(e.serverLoc, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (e.userLoc.isNotEmpty()) Text("From: ${e.userLoc}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
            }
            Text(g.label, color = g.color, fontWeight = FontWeight.ExtraBold)
        }
        if (all.size > 1) {
            Text("VS AVERAGE", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            for (m in 0..3) {
                val vals = all.map { metric(it, m) }
                val avg = vals.average()
                val mx = max(vals.max(), 1e-9)
                val v = metric(e, m)
                Column {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(METRICS[m], style = MaterialTheme.typography.labelMedium, color = metricColor(m), fontWeight = FontWeight.Bold)
                        Text("${metricText(v, m, unit)}   (avg ${metricText(avg, m, unit)})", style = MaterialTheme.typography.labelMedium)
                    }
                    LinearProgressIndicator({ (v / mx).toFloat().coerceIn(0f, 1f) }, Modifier.fillMaxWidth().height(6.dp), color = metricColor(m), strokeCap = StrokeCap.Round)
                    Spacer(Modifier.height(3.dp))
                    LinearProgressIndicator({ (avg / mx).toFloat().coerceIn(0f, 1f) }, Modifier.fillMaxWidth().height(4.dp), color = metricColor(m).copy(alpha = 0.4f), strokeCap = StrokeCap.Round)
                }
            }
        } else {
            for (m in 0..3) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(METRICS[m], color = metricColor(m), fontWeight = FontWeight.Bold)
                    Text(metricText(metric(e, m), m, unit))
                }
            }
        }
    }
}
