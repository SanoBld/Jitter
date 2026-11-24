@file:OptIn(ExperimentalMaterial3Api::class)

package com.sanobld.jitter

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
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
    ModalBottomSheet(onDismissRequest = onClose) {
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
private fun ServerPicker(vm: JitterViewModel, s: Settings, onClose: () -> Unit) {
    val list = vm.servers(s)
    val cur = vm.currentServer(s)
    SheetTitle("Select server")
    ListItem(
        headlineContent = { Text("Auto-fallback") },
        supportingContent = { Text("Try the next server if the current one fails") },
        trailingContent = { Switch(checked = s.fallback, onCheckedChange = { v -> vm.set { it.copy(fallback = v) } }) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
    LazyColumn(Modifier.heightIn(max = 480.dp)) {
        items(list) { sv ->
            ListItem(
                modifier = Modifier.clickable {
                    vm.set { it.copy(serverUrl = sv.url) }
                    onClose()
                },
                leadingContent = { Text(sv.flag, fontSize = 22.sp) },
                headlineContent = { Text(sv.name) },
                supportingContent = { Text("${sv.location} · ${sv.provider} · ${sv.size}") },
                trailingContent = {
                    if (sv.url == cur.url) Icon(Icons.Filled.Check, null, tint = MaterialTheme.colorScheme.primary)
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
    Column(Modifier.padding(horizontal = 24.dp, vertical = 6.dp)) {
        Text(label, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(top = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            DURATIONS.forEach { d ->
                FilterChip(selected = value == d, onClick = { onPick(d) }, label = { Text(if (d == 0) "∞" else "${d}s") })
            }
        }
    }
}

@Composable
private fun DurationPicker(vm: JitterViewModel, s: Settings) {
    SheetTitle("Test duration")
    ListItem(
        headlineContent = { Text("Same for download and upload") },
        trailingContent = { Switch(checked = s.linked, onCheckedChange = { v -> vm.set { it.copy(linked = v, ulSecs = if (v) it.dlSecs else it.ulSecs) } }) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
    DurationRow(if (s.linked) "Download + upload" else "Download", s.dlSecs) { vm.setDuration(true, it) }
    if (!s.linked) DurationRow("Upload", s.ulSecs) { vm.setDuration(false, it) }
    Text(
        "∞ runs until you press STOP (max 10 min).",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
    )
}

@Composable
private fun UnitPicker(vm: JitterViewModel, s: Settings, onClose: () -> Unit) {
    SheetTitle("Speed unit")
    SpeedUnit.entries.forEachIndexed { i, u ->
        ListItem(
            modifier = Modifier.clickable {
                vm.set { it.copy(unit = i) }
                onClose()
            },
            leadingContent = { RadioButton(selected = s.unit == i, onClick = null) },
            headlineContent = { Text(u.label) },
            supportingContent = { Text(u.desc) },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        )
    }
}

@Composable
private fun ConnPicker(vm: JitterViewModel, s: Settings) {
    SheetTitle("Connections per test")
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 24.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        listOf(1, 2, 4, 8, 16, 32).forEach { n ->
            FilterChip(selected = s.conns == n, onClick = { vm.set { it.copy(conns = n) } }, label = { Text("${n}×") })
        }
    }
    Text(
        "More connections fill faster links. Use 8–16× with a 1 GB or 10 GB server for gigabit fiber.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp),
    )
}
