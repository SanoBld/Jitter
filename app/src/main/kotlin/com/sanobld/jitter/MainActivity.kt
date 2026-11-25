package com.sanobld.jitter

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Map
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val vm: JitterViewModel = viewModel()
            val s by vm.settings.collectAsStateWithLifecycle()
            CompositionLocalProvider(LocalLang provides s.lang) {
                JitterTheme(s) { AppRoot(vm, s) }
            }
        }
    }
}

@Composable
fun AppRoot(vm: JitterViewModel, s: Settings) {
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val crashPrefs = remember { ctx.getSharedPreferences("jitter_crash", android.content.Context.MODE_PRIVATE) }
    var crash by remember { mutableStateOf(crashPrefs.getString("trace", null)) }
    crash?.let { trace ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { },
            title = { Text(tr("crash_title")) },
            text = {
                Text(
                    trace,
                    Modifier.heightIn(max = 320.dp).verticalScroll(rememberScrollState()),
                    style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                )
            },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = {
                    val cm = ctx.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                    cm.setPrimaryClip(android.content.ClipData.newPlainText("crash", trace))
                }) { Text(tr("crash_copy")) }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = {
                    crashPrefs.edit().remove("trace").apply()
                    crash = null
                }) { Text(tr("crash_close")) }
            },
        )
    }
    var tab by rememberSaveable { mutableIntStateOf(0) }
    val snack = remember { SnackbarHostState() }
    LaunchedEffect(s.lang) {
        vm.message.collect { snack.showSnackbar(L.msg(it, s.lang)) }
    }
    val items = listOf(
        "nav_test" to Icons.Rounded.Speed,
        "nav_logs" to Icons.Rounded.History,
        "nav_map" to Icons.Rounded.Map,
        "nav_settings" to Icons.Rounded.Settings,
    )
    NavigationSuiteScaffold(
        navigationSuiteItems = {
            items.forEachIndexed { i, (key, icon) ->
                item(
                    selected = tab == i,
                    onClick = { tab = i },
                    icon = { Icon(icon, null) },
                    label = { Text(tr(key)) },
                )
            }
        },
    ) {
        Scaffold(snackbarHost = { SnackbarHost(snack) }) { pad ->
            Box(Modifier.padding(pad).fillMaxSize()) {
                when (tab) {
                    0 -> TestScreen(vm)
                    1 -> HistoryScreen(vm, isDarkTheme(s))
                    2 -> MapScreen(vm, isDarkTheme(s))
                    else -> SettingsScreen(vm)
                }
            }
        }
    }
}
