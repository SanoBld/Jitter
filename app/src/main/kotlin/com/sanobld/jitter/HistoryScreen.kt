package com.sanobld.jitter

import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.DeleteForever
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.FileDownload
import androidx.compose.material.icons.rounded.FormatListBulleted
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.LocationOn
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material.icons.rounded.ShowChart
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearWavyProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlin.math.max

fun shareCsv(ctx: Context, vm: JitterViewModel) {
    if (vm.history.value.isEmpty()) {
        vm.toast("export_empty")
        return
    }
    val i = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, "Jitter results.csv")
        putExtra(Intent.EXTRA_TEXT, vm.exportCsv())
    }
    ctx.startActivity(Intent.createChooser(i, null))
}

@Composable
fun HistoryScreen(vm: JitterViewModel, dark: Boolean) {
    val ctx = LocalContext.current
    val h by vm.history.collectAsStateWithLifecycle()
    val s by vm.settings.collectAsStateWithLifecycle()
    val unit = unitOf(s)
    var trend by remember { mutableStateOf(false) }
    var detail by remember { mutableStateOf<Entry?>(null) }
    var confirm by remember { mutableStateOf(false) }
    var importing by remember { mutableStateOf(false) }
    val groups = h.groupBy { it.userLoc.ifEmpty { "" } }

    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = 720.dp).fillMaxSize().padding(horizontal = 16.dp)) {
            Row(Modifier.padding(top = 12.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(tr("logs_title"), style = MaterialTheme.typography.headlineMedium)
                    Text(
                        tr("tests_count", "n" to h.size, "m" to groups.size),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                FilledTonalIconButton(onClick = { shareCsv(ctx, vm) }) { Icon(Icons.Rounded.Share, tr("export_csv")) }
                FilledTonalIconButton(onClick = { importing = true }) { Icon(Icons.Rounded.FileDownload, tr("import_csv")) }
                FilledTonalIconButton(onClick = { if (h.isNotEmpty()) confirm = true }) { Icon(Icons.Rounded.DeleteForever, tr("clear_all")) }
            }

            if (h.size >= 2) {
                ChoiceGroup(
                    listOf(tr("list"), tr("trend")),
                    if (trend) 1 else 0,
                    { trend = it == 1 },
                    Modifier.padding(bottom = 8.dp),
                )
            }

            when {
                h.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        ShapeBadge(
                            3, Icons.Rounded.History,
                            MaterialTheme.colorScheme.secondaryContainer, MaterialTheme.colorScheme.onSecondaryContainer, 96.dp,
                        )
                        Text(tr("no_tests"), style = MaterialTheme.typography.titleLarge)
                        Text(tr("no_tests_hint"), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                trend && h.size >= 2 -> TrendView(h.reversed(), unit)
                else -> LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxSize()) {
                    groups.forEach { (loc, list) ->
                        item(key = "h:$loc") {
                            Row(
                                Modifier.fillMaxWidth().padding(top = 8.dp, start = 4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Icon(Icons.Rounded.LocationOn, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
                                Spacer(Modifier.size(6.dp))
                                Text(
                                    loc.ifEmpty { tr("unknown_loc") },
                                    style = MaterialTheme.typography.titleSmall,
                                    color = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.weight(1f),
                                )
                                Text(
                                    "${list.size}",
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                        items(list, key = { it.ts + "|" + it.server + "|" + it.dl }) { e ->
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
                                        Modifier.fillMaxSize()
                                            .background(MaterialTheme.colorScheme.errorContainer, MaterialTheme.shapes.large)
                                            .padding(end = 24.dp),
                                        contentAlignment = Alignment.CenterEnd,
                                    ) { Icon(Icons.Rounded.Delete, null, tint = MaterialTheme.colorScheme.onErrorContainer) }
                                },
                            ) { EntryCard(e, unit) { detail = e } }
                        }
                    }
                    item { Spacer(Modifier.height(16.dp)) }
                }
            }
        }
    }

    if (confirm) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            icon = { Icon(Icons.Rounded.DeleteForever, null) },
            title = { Text(tr("clear_title")) },
            text = { Text(tr("clear_body")) },
            confirmButton = {
                TextButton(onClick = {
                    vm.clearHistory()
                    confirm = false
                }) { Text(tr("delete_all"), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text(tr("cancel")) } },
        )
    }
    if (importing) ImportDialog(vm) { importing = false }
    detail?.let { e ->
        ModalBottomSheet(
            onDismissRequest = { detail = null },
            shape = RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp),
        ) { DetailSheet(e, h, unit, dark) }
    }
}

@Composable
private fun ImportDialog(vm: JitterViewModel, onClose: () -> Unit) {
    val ctx = LocalContext.current
    fun clip(): String {
        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        return cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text?.toString().orEmpty()
    }
    var text by remember {
        mutableStateOf(clip().let { if (it.contains("download_mbps") || it.contains("timestamp")) it else "" })
    }
    AlertDialog(
        onDismissRequest = onClose,
        icon = { Icon(Icons.Rounded.FileDownload, null) },
        title = { Text(tr("import_csv")) },
        text = {
            Column {
                Text(tr("import_hint"), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 4,
                    maxLines = 6,
                    textStyle = TextStyle(fontSize = 11.sp, fontFamily = FontFamily.Monospace),
                    shape = MaterialTheme.shapes.large,
                    keyboardOptions = KeyboardOptions.Default,
                )
                TextButton(onClick = { text = clip() }) { Text(tr("paste")) }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val n = if (text.isBlank()) 0 else vm.importCsv(text)
                if (n > 0) vm.toast("imported", n.toString()) else vm.toast("import_none")
                onClose()
            }) { Text(tr("import")) }
        },
        dismissButton = { TextButton(onClick = onClose) { Text(tr("cancel")) } },
    )
}

@Composable
private fun EntryCard(e: Entry, unit: SpeedUnit, onClick: () -> Unit) {
    val g = gradeFor(e.dl)
    val c = MaterialTheme.colorScheme
    Surface(
        Modifier.fillMaxWidth().clip(MaterialTheme.shapes.large).clickable(onClick = onClick),
        shape = MaterialTheme.shapes.large,
        color = c.surfaceContainerHigh,
    ) {
        Column(Modifier.padding(16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Surface(shape = MaterialTheme.shapes.medium, color = g.color) {
                    Text(
                        tr(g.key),
                        Modifier.padding(horizontal = 10.dp, vertical = 3.dp),
                        color = Color.White,
                        fontWeight = FontWeight.ExtraBold,
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
                Spacer(Modifier.weight(1f))
                if (e.hasPos) {
                    Icon(Icons.Rounded.LocationOn, null, Modifier.size(14.dp), tint = c.onSurfaceVariant)
                    Spacer(Modifier.size(4.dp))
                }
                Text(e.ts, style = MaterialTheme.typography.labelSmall, color = c.onSurfaceVariant)
            }
            Spacer(Modifier.height(10.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Mini("↓ " + tr("down"), "${unit.fmt(e.dl)} ${unit.label}", c.primary)
                Mini("↑ " + tr("up"), "${unit.fmt(e.ul)} ${unit.label}", c.secondary)
                Mini(tr("ping"), "${e.ping} ms", c.tertiary)
                Mini(tr("jitter"), "${e.jitter} ms", c.error)
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "${e.flag} ${e.server}" + if (e.userLoc.isNotEmpty()) "  ·  ${e.userLoc}" else "",
                style = MaterialTheme.typography.labelSmall,
                color = c.onSurfaceVariant,
                maxLines = 1,
            )
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
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        ChoiceGroup(METRIC_KEYS.map { tr(it) }, m, { m = it })
        Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerHigh) {
            Row(Modifier.fillMaxWidth().padding(20.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                Mini(tr("avg"), metricText(vals.average(), m, unit), color)
                Mini(tr("best"), metricText(if (m < 2) vals.max() else vals.min(), m, unit), color)
                Mini(tr("worst"), metricText(if (m < 2) vals.min() else vals.max(), m, unit), color)
            }
        }
        Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainer) {
            LiveChart(vals, color, Modifier.fillMaxWidth().height(220.dp).padding(16.dp))
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(chrono.first().ts, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(chrono.last().ts, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
fun DetailSheet(e: Entry, all: List<Entry>, unit: SpeedUnit, dark: Boolean) {
    val g = gradeFor(e.dl)
    val c = MaterialTheme.colorScheme
    Column(
        Modifier.padding(horizontal = 24.dp).padding(bottom = 32.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(tr("test_detail"), style = MaterialTheme.typography.labelLarge, color = c.primary)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(e.ts, style = MaterialTheme.typography.titleLarge)
                Text("${e.flag} ${e.server} · ${e.provider}", style = MaterialTheme.typography.bodyMedium)
                Text(e.serverLoc, style = MaterialTheme.typography.bodySmall, color = c.onSurfaceVariant)
                if (e.userLoc.isNotEmpty()) {
                    Text("${tr("from")}: ${e.userLoc}", style = MaterialTheme.typography.bodySmall, color = c.primary)
                }
            }
            Surface(shape = MaterialTheme.shapes.large, color = g.color) {
                Text(
                    tr(g.key),
                    Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                    color = Color.White,
                    fontWeight = FontWeight.ExtraBold,
                    style = MaterialTheme.typography.labelLarge,
                )
            }
        }

        if (all.size > 1) {
            Text(tr("vs_avg"), style = MaterialTheme.typography.labelLarge, color = c.primary)
            for (m in 0..3) {
                val vals = all.map { metric(it, m) }
                val avg = vals.average()
                val mx = max(vals.max(), 1e-9)
                val v = metric(e, m)
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(tr(METRIC_KEYS[m]), style = MaterialTheme.typography.labelLarge, color = metricColor(m), fontWeight = FontWeight.Bold)
                        Text(
                            "${metricText(v, m, unit)}   (${tr("avg_short")} ${metricText(avg, m, unit)})",
                            style = MaterialTheme.typography.labelMedium,
                        )
                    }
                    LinearWavyProgressIndicator(
                        progress = { (v / mx).toFloat().coerceIn(0f, 1f) },
                        modifier = Modifier.fillMaxWidth(),
                        color = metricColor(m),
                    )
                    androidx.compose.material3.LinearProgressIndicator(
                        progress = { (avg / mx).toFloat().coerceIn(0f, 1f) },
                        modifier = Modifier.fillMaxWidth().height(4.dp),
                        color = metricColor(m).copy(alpha = 0.4f),
                        strokeCap = StrokeCap.Round,
                    )
                }
            }
        } else {
            for (m in 0..3) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(tr(METRIC_KEYS[m]), color = metricColor(m), fontWeight = FontWeight.Bold)
                    Text(metricText(metric(e, m), m, unit))
                }
            }
        }

        if (e.hasPos) {
            Text(tr("map_location"), style = MaterialTheme.typography.labelLarge, color = c.primary)
            OsmMap(
                listOf(e), dark, interactive = false,
                modifier = Modifier.fillMaxWidth().height(180.dp).clip(MaterialTheme.shapes.extraLarge),
            )
        }
    }
}
