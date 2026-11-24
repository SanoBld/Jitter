package com.sanobld.jitter

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.LocationOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun MapScreen(vm: JitterViewModel, dark: Boolean) {
    val h by vm.history.collectAsStateWithLifecycle()
    val s by vm.settings.collectAsStateWithLifecycle()
    val pts = h.filter { it.hasPos }
    var sel by remember { mutableStateOf<Entry?>(null) }

    if (pts.isEmpty()) {
        Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Rounded.LocationOff, null, Modifier.size(56.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(tr("map_title"), style = MaterialTheme.typography.titleLarge)
                Text(
                    tr("map_no_gps"),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
        }
        return
    }

    Box(Modifier.fillMaxSize()) {
        OsmMap(pts, dark, interactive = true, modifier = Modifier.fillMaxSize(), onSelect = { sel = it })
        Surface(
            modifier = Modifier.align(Alignment.TopCenter).padding(12.dp),
            shape = MaterialTheme.shapes.extraLarge,
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            tonalElevation = 3.dp,
        ) {
            Text(
                tr("map_count", "n" to pts.size),
                Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                style = MaterialTheme.typography.labelLarge,
            )
        }
    }
    sel?.let { e ->
        ModalBottomSheet(onDismissRequest = { sel = null }) {
            DetailSheet(e, h, unitOf(s), dark)
        }
    }
}
