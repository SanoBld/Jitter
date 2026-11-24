package com.sanobld.jitter

import android.Manifest
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.DeleteForever
import androidx.compose.material.icons.rounded.Dns
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.FileDownload
import androidx.compose.material.icons.rounded.Palette
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Save
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.SwapVert
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.MyLocation
import androidx.compose.material.icons.rounded.LocationOn
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun SettingsScreen(vm: JitterViewModel) {
    val ctx = LocalContext.current
    val s by vm.settings.collectAsStateWithLifecycle()
    val h by vm.history.collectAsStateWithLifecycle()
    val gpsCity by vm.gpsCity.collectAsStateWithLifecycle()
    val ip by vm.ipLoc.collectAsStateWithLifecycle()
    val busy by vm.locBusy.collectAsStateWithLifecycle()
    var sheet by remember { mutableStateOf(0) }
    var customDialog by remember { mutableStateOf(false) }
    var clearDialog by remember { mutableStateOf(false) }
    val c = MaterialTheme.colorScheme

    val gpsLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { r ->
        if (r.values.any { it }) vm.setGps(true) else vm.toast("gps_denied")
    }

    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier.widthIn(max = 720.dp).fillMaxSize().verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Text(tr("settings"), style = MaterialTheme.typography.headlineMedium)

            Section(tr("s_language")) {
                ChoiceGroup(
                    LANGS.map { "${it.second} ${it.third}" },
                    LANGS.indexOfFirst { it.first == s.lang }.coerceAtLeast(0),
                    { i -> vm.set { it.copy(lang = LANGS[i].first) } },
                    Modifier.padding(12.dp),
                )
            }

            Section(tr("s_appearance")) {
                ChoiceGroup(
                    listOf(tr("system"), tr("light"), tr("dark")),
                    s.theme.coerceIn(0, 2),
                    { i -> vm.set { it.copy(theme = i) } },
                    Modifier.padding(12.dp),
                )
                val canDyn = android.os.Build.VERSION.SDK_INT >= 31
                SettingRow(
                    tr("dynamic"), if (canDyn) tr("dynamic_sub") else tr("dynamic_old"), Icons.Rounded.Palette, 1,
                    trailing = { JitterSwitch(s.dynamic && canDyn, { v -> vm.set { it.copy(dynamic = v) } }, canDyn) },
                )
                if (!(s.dynamic && canDyn)) {
                    Text(tr("accent"), Modifier.padding(start = 16.dp, top = 4.dp), style = MaterialTheme.typography.labelLarge)
                    Row(
                        Modifier.fillMaxWidth().padding(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        SEEDS.forEachIndexed { i, seed ->
                            Box(
                                Modifier.size(36.dp).clip(polygonShape(i)).background(Color(seed))
                                    .clickable { vm.set { it.copy(seed = i) } },
                                contentAlignment = Alignment.Center,
                            ) {
                                if (s.seed == i) Icon(Icons.Rounded.Check, null, tint = Color.White, modifier = Modifier.size(20.dp))
                            }
                        }
                    }
                }
            }

            Section(tr("s_test")) {
                SettingRow(tr("server"), vm.currentServer(s).let { "${it.flag} ${it.name}" }, Icons.Rounded.Dns, 2, { sheet = 1 })
                SettingRow(
                    tr("duration"),
                    if (s.dlSecs == s.ulSecs) fmtDur(s.dlSecs) else "↓ ${fmtDur(s.dlSecs)}  ↑ ${fmtDur(s.ulSecs)}",
                    Icons.Rounded.Timer, 3, { sheet = 2 },
                )
                SettingRow(tr("unit_title"), unitOf(s).label, Icons.Rounded.Speed, 4, { sheet = 3 })
                SettingRow(
                    tr("conns"),
                    if (s.conns <= 0) tr("auto") else tr("conns_parallel", "n" to s.conns),
                    Icons.Rounded.SwapVert, 5, { sheet = 4 },
                )
                SettingRow(
                    tr("auto_fallback"), tr("auto_fallback_sub"), Icons.Rounded.Tune, 0,
                    trailing = { JitterSwitch(s.fallback, { v -> vm.set { it.copy(fallback = v) } }) },
                )
                SettingRow(
                    tr("auto_save"), tr("auto_save_sub"), Icons.Rounded.Save, 1,
                    trailing = { JitterSwitch(s.autoSave, { v -> vm.set { it.copy(autoSave = v) } }) },
                )
            }

            Section(tr("s_custom")) {
                val has = s.customUrl.isNotBlank()
                SettingRow(
                    if (has) s.customName.ifBlank { "Custom" } else tr("custom_none"),
                    if (has) s.customUrl else tr("custom_hint"),
                    Icons.Rounded.Dns, 2, { customDialog = true },
                    trailing = {
                        if (has) {
                            Row {
                                IconButton(onClick = { customDialog = true }) { Icon(Icons.Rounded.Edit, tr("edit")) }
                                IconButton(onClick = { vm.removeCustomServer() }) { Icon(Icons.Rounded.Delete, tr("remove")) }
                            }
                        } else Icon(Icons.Rounded.Add, null)
                    },
                )
            }

            Section(tr("s_location")) {
                SettingRow(
                    tr("gps"), tr("gps_sub"), Icons.Rounded.MyLocation, 3,
                    trailing = {
                        JitterSwitch(s.useGps, { on ->
                            if (!on) vm.setGps(false)
                            else if (Net.hasLocationPermission(ctx)) vm.setGps(true)
                            else gpsLauncher.launch(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION))
                        })
                    },
                )
                if (s.useGps) {
                    SettingRow(tr("gps_city"), gpsCity.ifEmpty { tr("not_detected") }, Icons.Rounded.LocationOn, 4)
                }
                SettingRow(
                    tr("ip_loc"), ip.ifEmpty { tr("not_detected") }, Icons.Rounded.Public, 5,
                    trailing = { IconButton(onClick = { vm.refreshLocation() }, enabled = !busy) { Icon(Icons.Rounded.Refresh, tr("refresh")) } },
                )
            }

            Section(tr("s_history")) {
                SettingRow(tr("export_csv"), tr("export_sub"), Icons.Rounded.Share, 0, { shareCsv(ctx, vm) })
                SettingRow(
                    tr("clear_all"), tr("clear_sub"), Icons.Rounded.DeleteForever, 1,
                    { if (h.isNotEmpty()) clearDialog = true },
                )
            }

            Text(
                tr("footer"),
                Modifier.fillMaxWidth().padding(bottom = 16.dp),
                style = MaterialTheme.typography.labelMedium,
                color = c.onSurfaceVariant,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }

    if (sheet != 0) Pickers(vm, sheet) { sheet = 0 }

    if (customDialog) {
        var name by remember { mutableStateOf(s.customName) }
        var url by remember { mutableStateOf(s.customUrl) }
        AlertDialog(
            onDismissRequest = { customDialog = false },
            title = { Text(tr("s_custom")) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedTextField(
                        name, { name = it }, label = { Text(tr("srv_name")) },
                        singleLine = true, shape = MaterialTheme.shapes.large,
                    )
                    OutlinedTextField(
                        url, { url = it }, label = { Text(tr("srv_url")) },
                        singleLine = true, shape = MaterialTheme.shapes.large,
                    )
                    Text(tr("custom_hint"), style = MaterialTheme.typography.bodySmall, color = c.onSurfaceVariant)
                }
            },
            confirmButton = { TextButton(onClick = { if (vm.saveCustomServer(name, url)) customDialog = false }) { Text(tr("save")) } },
            dismissButton = { TextButton(onClick = { customDialog = false }) { Text(tr("cancel")) } },
        )
    }

    if (clearDialog) {
        AlertDialog(
            onDismissRequest = { clearDialog = false },
            title = { Text(tr("clear_title")) },
            text = { Text(tr("clear_body")) },
            confirmButton = { TextButton(onClick = { vm.clearHistory(); clearDialog = false }) { Text(tr("delete_all")) } },
            dismissButton = { TextButton(onClick = { clearDialog = false }) { Text(tr("cancel")) } },
        )
    }
}
