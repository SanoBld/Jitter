@file:OptIn(ExperimentalMaterial3Api::class)

package com.sanobld.jitter

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.foundation.text.KeyboardOptions

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column {
        Text(
            title,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(start = 4.dp, bottom = 8.dp),
        )
        Card(
            shape = RoundedCornerShape(20.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
        ) { Column(Modifier.fillMaxWidth()) { content() } }
    }
}

@Composable
private fun Row2(
    title: String,
    sub: String? = null,
    onClick: (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    ListItem(
        modifier = if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier,
        headlineContent = { Text(title) },
        supportingContent = if (sub != null) { { Text(sub) } } else null,
        trailingContent = trailing,
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}

@Composable
fun SettingsScreen(vm: JitterViewModel) {
    val ctx = LocalContext.current
    val s by vm.settings.collectAsStateWithLifecycle()
    val ip by vm.ipLoc.collectAsStateWithLifecycle()
    val isp by vm.isp.collectAsStateWithLifecycle()
    val gps by vm.gpsCity.collectAsStateWithLifecycle()
    val busy by vm.locBusy.collectAsStateWithLifecycle()
    var sheet by remember { mutableIntStateOf(0) }
    val unit = SpeedUnit.entries[s.unit.coerceIn(0, SpeedUnit.entries.size - 1)]
    val server = vm.currentServer(s)
    val canDynamic = Build.VERSION.SDK_INT >= 31

    val gpsLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) {
            vm.set { it.copy(useGps = true) }
            vm.refreshLocation()
        } else {
            vm.toast("Location permission denied.")
        }
    }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Text("Settings", style = MaterialTheme.typography.headlineSmall)

        Section("APPEARANCE") {
            Column(Modifier.padding(16.dp)) {
                Text("Theme", style = MaterialTheme.typography.bodyLarge)
                Spacer(Modifier.height(8.dp))
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    listOf("System", "Light", "Dark").forEachIndexed { i, l ->
                        SegmentedButton(
                            selected = s.theme == i,
                            onClick = { vm.set { it.copy(theme = i) } },
                            shape = SegmentedButtonDefaults.itemShape(i, 3),
                        ) { Text(l) }
                    }
                }
            }
            HorizontalDivider()
            Row2(
                "Dynamic color",
                if (canDynamic) "Follow your wallpaper colors" else "Needs Android 12 or newer",
            ) {
                Switch(checked = s.dynamic && canDynamic, enabled = canDynamic, onCheckedChange = { v -> vm.set { it.copy(dynamic = v) } })
            }
            HorizontalDivider()
            val off = s.dynamic && canDynamic
            Column(Modifier.padding(16.dp).alpha(if (off) 0.38f else 1f)) {
                Text("Accent color", style = MaterialTheme.typography.bodyLarge)
                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    SEEDS.forEachIndexed { i, c ->
                        val sel = s.seed == i
                        Box(
                            Modifier.size(36.dp).background(Color(c), CircleShape)
                                .border(if (sel) 3.dp else 0.dp, MaterialTheme.colorScheme.onSurface, CircleShape)
                                .clickable(enabled = !off) { vm.set { it.copy(seed = i) } },
                            contentAlignment = Alignment.Center,
                        ) { if (sel) Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(18.dp)) }
                    }
                }
            }
        }

        Section("TEST") {
            Row2("Server", "${server.flag} ${server.name} · ${server.provider} · ${server.size}", onClick = { sheet = 1 })
            HorizontalDivider()
            Row2("Auto-fallback", "Try the next server if the current one fails") {
                Switch(checked = s.fallback, onCheckedChange = { v -> vm.set { it.copy(fallback = v) } })
            }
            HorizontalDivider()
            Row2("Connections per test", "${s.conns}× parallel", onClick = { sheet = 4 })
            HorizontalDivider()
            Row2(
                "Duration",
                if (s.linked) fmtDur(s.dlSecs) + " for download and upload" else "↓ ${fmtDur(s.dlSecs)}  ↑ ${fmtDur(s.ulSecs)}",
                onClick = { sheet = 2 },
            )
            HorizontalDivider()
            Row2("Speed unit", "${unit.label} · ${unit.desc}", onClick = { sheet = 3 })
        }

        CustomServer(vm, s)

        Section("LOCATION") {
            Row2("GPS location", "Use your device to show the city name") {
                Switch(checked = s.useGps, onCheckedChange = { on ->
                    if (!on) {
                        vm.set { it.copy(useGps = false) }
                    } else if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
                        vm.set { it.copy(useGps = true) }
                        vm.refreshLocation()
                    } else {
                        gpsLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
                    }
                })
            }
            if (s.useGps) Row2("GPS city", if (gps.isEmpty()) "Not detected" else gps)
            HorizontalDivider()
            Row2(
                "IP location",
                if (busy) "Detecting…" else (ip.ifEmpty { "Not detected" } + if (isp.isNotEmpty()) "\n$isp" else ""),
            ) {
                IconButton(onClick = { vm.refreshLocation() }, enabled = !busy) { Icon(Icons.Filled.Refresh, "Refresh") }
            }
        }

        Section("HISTORY") {
            Row2("Auto-save results", "Add each test to the logs") {
                Switch(checked = s.autoSave, onCheckedChange = { v -> vm.set { it.copy(autoSave = v) } })
            }
        }

        Text(
            "Jitter v1.0.0",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
    }
    Pickers(vm, sheet) { sheet = 0 }
}

@Composable
private fun CustomServer(vm: JitterViewModel, s: Settings) {
    var name by remember(s.customName) { mutableStateOf(s.customName) }
    var url by remember(s.customUrl) { mutableStateOf(s.customUrl) }
    Section("CUSTOM SERVER") {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                "Any direct download URL, for example http://192.168.1.10/file.bin",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(name, { name = it }, Modifier.fillMaxWidth(), label = { Text("Server name") }, singleLine = true)
            OutlinedTextField(
                url, { url = it }, Modifier.fillMaxWidth(),
                label = { Text("Download URL") }, singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                if (s.customUrl.isNotBlank()) {
                    OutlinedButton(onClick = {
                        vm.set { it.copy(customName = "", customUrl = "", serverUrl = "") }
                        vm.toast("Custom server removed.")
                    }) { Text("Remove") }
                }
                Button(onClick = {
                    val u = url.trim()
                    if (u.startsWith("http://") || u.startsWith("https://")) {
                        vm.set { it.copy(customName = name.trim(), customUrl = u, serverUrl = u) }
                        vm.toast("Custom server saved.")
                    } else {
                        vm.toast("URL must start with http:// or https://")
                    }
                }) { Text("Save") }
            }
        }
    }
}
