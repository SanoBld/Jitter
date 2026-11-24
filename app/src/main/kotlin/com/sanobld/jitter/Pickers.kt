package com.sanobld.jitter

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle

/** which: 0 none, 1 server, 2 duration, 3 unit, 4 connections */
@Composable
fun Pickers(vm: JitterViewModel, which: Int, onClose: () -> Unit) {
    if (which == 0) return
    val s by vm.settings.collectAsStateWithLifecycle()
    ModalBottomSheet(
        onDismissRequest = onClose,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = which == 1),
        shape = RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp),
    ) {
        when (which) {
            1 -> ServerPicker(vm, s, onClose)
            2 -> DurationPicker(vm, s)
            3 -> UnitPicker(vm, s, onClose)
            else -> ConnPicker(vm, s)
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun SheetTitle(text: String) {
    Text(text, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp))
}

@Composable
private fun Hint(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
    )
}

@Composable
private fun ServerPicker(vm: JitterViewModel, s: Settings, onClose: () -> Unit) {
    val list = vm.servers(s)
    val cur = vm.currentServer(s)
    SheetTitle(tr("select_server"))
    ListItem(
        headlineContent = { Text(tr("auto_fallback")) },
        supportingContent = { Text(tr("auto_fallback_sub")) },
        trailingContent = { JitterSwitch(s.fallback, { v -> vm.set { it.copy(fallback = v) } }) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
    LazyColumn(Modifier.heightIn(max = 480.dp)) {
        items(list, key = { it.url }) { sv ->
            ListItem(
                modifier = Modifier.clickable {
                    vm.set { it.copy(serverUrl = sv.url) }
                    onClose()
                },
                leadingContent = { Text(sv.flag, fontSize = 24.sp) },
                headlineContent = { Text(sv.name) },
                supportingContent = { Text("${sv.location} · ${sv.provider} · ${sv.size}") },
                trailingContent = {
                    if (sv.url == cur.url) Icon(Icons.Rounded.Check, null, tint = MaterialTheme.colorScheme.primary)
                    else if (sv.minConns >= 8) Text("${sv.minConns}×", style = MaterialTheme.typography.labelSmall)
                },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            )
        }
    }
}

private val DURATIONS = listOf(5, 10, 15, 30, 60, 0)

@Composable
private fun DurationRow(label: String, value: Int, onPick: (Int) -> Unit) {
    var dialog by remember { mutableStateOf(false) }
    Column(Modifier.padding(horizontal = 24.dp, vertical = 6.dp)) {
        Text(label, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
        FlowRow(
            Modifier.padding(top = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            DURATIONS.forEach { d ->
                FilterChip(
                    selected = value == d,
                    onClick = { onPick(d) },
                    label = { Text(if (d == 0) "∞" else "${d}s") },
                    shape = MaterialTheme.shapes.large,
                )
            }
            FilterChip(
                selected = value !in DURATIONS,
                onClick = { dialog = true },
                label = { Text(if (value !in DURATIONS) fmtDur(value) else tr("custom")) },
                shape = MaterialTheme.shapes.large,
            )
        }
    }
    if (dialog) {
        NumberDialog(
            title = tr("dur_dialog_title"),
            hint = tr("dur_dialog_hint"),
            initial = if (value in DURATIONS) "" else value.toString(),
            maxLen = 4,
            onDismiss = { dialog = false },
            onConfirm = { txt ->
                val n = txt.toIntOrNull()
                onPick(if (n == null) 0 else n.coerceIn(1, 3600))
                dialog = false
            },
        )
    }
}

@Composable
private fun DurationPicker(vm: JitterViewModel, s: Settings) {
    SheetTitle(tr("duration"))
    ListItem(
        headlineContent = { Text(tr("same_dur")) },
        trailingContent = {
            JitterSwitch(s.linked, { v -> vm.set { it.copy(linked = v, ulSecs = if (v) it.dlSecs else it.ulSecs) } })
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
    DurationRow(if (s.linked) tr("dur_both") else tr("dur_dl"), s.dlSecs) { vm.setDuration(true, it) }
    if (!s.linked) DurationRow(tr("dur_ul"), s.ulSecs) { vm.setDuration(false, it) }
    Hint(tr("dur_hint"))
}

@Composable
private fun UnitPicker(vm: JitterViewModel, s: Settings, onClose: () -> Unit) {
    SheetTitle(tr("unit_title"))
    SpeedUnit.entries.forEachIndexed { i, u ->
        ListItem(
            modifier = Modifier.clickable {
                vm.set { it.copy(unit = i) }
                onClose()
            },
            leadingContent = { RadioButton(selected = s.unit == i, onClick = null) },
            headlineContent = { Text(u.label) },
            supportingContent = { Text(tr("u$i")) },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        )
    }
}

private val CONNS = listOf(0, 1, 2, 4, 8, 16, 32, 64)

@Composable
private fun ConnPicker(vm: JitterViewModel, s: Settings) {
    var dialog by remember { mutableStateOf(false) }
    SheetTitle(tr("conns"))
    FlowRow(
        Modifier.padding(horizontal = 24.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        CONNS.forEach { n ->
            FilterChip(
                selected = s.conns == n,
                onClick = { vm.set { it.copy(conns = n) } },
                label = { Text(if (n == 0) tr("auto") else "${n}×") },
                shape = MaterialTheme.shapes.large,
            )
        }
        FilterChip(
            selected = s.conns !in CONNS,
            onClick = { dialog = true },
            label = { Text(if (s.conns !in CONNS) "${s.conns}×" else tr("custom")) },
            shape = MaterialTheme.shapes.large,
        )
    }
    Hint(tr("conns_hint"))
    if (dialog) {
        NumberDialog(
            title = tr("conns_dialog_title"),
            hint = tr("conns_dialog_hint"),
            initial = if (s.conns in CONNS) "" else s.conns.toString(),
            maxLen = 2,
            onDismiss = { dialog = false },
            onConfirm = { txt ->
                txt.toIntOrNull()?.let { n -> vm.set { it.copy(conns = n.coerceIn(1, 64)) } }
                dialog = false
            },
        )
    }
}
