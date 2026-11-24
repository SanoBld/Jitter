package com.sanobld.jitter

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.net.ssl.SSLException

class JitterViewModel(app: Application) : AndroidViewModel(app) {
    private val store = Store(app)
    val settings = MutableStateFlow(store.load())
    val history = MutableStateFlow(store.loadHistory())
    val test = MutableStateFlow(TestState())
    val ipLoc = MutableStateFlow("")
    val isp = MutableStateFlow("")
    val gpsCity = MutableStateFlow("")
    val locBusy = MutableStateFlow(false)
    val message = MutableSharedFlow<String>(extraBufferCapacity = 4)
    private var job: Job? = null

    init {
        refreshLocation()
    }

    fun toast(msg: String) {
        message.tryEmit(msg)
    }

    fun set(f: (Settings) -> Settings) {
        val n = f(settings.value)
        settings.value = n
        store.save(n)
    }

    fun setDuration(download: Boolean, secs: Int) = set {
        when {
            it.linked -> it.copy(dlSecs = secs, ulSecs = secs)
            download -> it.copy(dlSecs = secs)
            else -> it.copy(ulSecs = secs)
        }
    }

    fun servers(s: Settings = settings.value): List<SpeedServer> {
        val custom = if (s.customUrl.isNotBlank()) {
            listOf(SpeedServer(s.customName.ifBlank { "Custom" }, "Custom", "Custom", "🔧", s.customUrl.trim(), 4, "Custom URL"))
        } else emptyList()
        return custom + Servers.builtin
    }

    fun currentServer(s: Settings = settings.value): SpeedServer =
        servers(s).firstOrNull { it.url == s.serverUrl } ?: servers(s).first()

    val activeLoc: String
        get() = if (settings.value.useGps && gpsCity.value.isNotEmpty()) gpsCity.value else ipLoc.value

    fun refreshLocation() {
        viewModelScope.launch {
            locBusy.value = true
            Net.ipInfo()?.let {
                ipLoc.value = it.location
                isp.value = it.isp
            }
            if (settings.value.useGps) Net.gpsCity(getApplication<Application>())?.let { gpsCity.value = it }
            locBusy.value = false
        }
    }

    private fun upd(f: (TestState) -> TestState) {
        test.value = f(test.value)
    }

    fun start() {
        if (job?.isActive == true) return
        job = viewModelScope.launch {
            val s = settings.value
            val all = servers(s)
            val first = all.indexOfFirst { it.url == s.serverUrl }.coerceAtLeast(0)
            val order = all.indices.map { (first + it) % all.size }.let { if (s.fallback) it.take(4) else it.take(1) }
            test.value = TestState(testing = true, phase = Phase.CHECKING, conn = Net.connType(getApplication<Application>()))
            var err = "No server available"
            var ok = false
            for ((n, i) in order.withIndex()) {
                try {
                    runPhases(all[i], s)
                    ok = true
                    break
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    err = friendly(e)
                    if (n < order.lastIndex) upd { it.copy(phase = Phase.SWITCHING) }
                }
            }
            if (!ok) upd { it.copy(testing = false, phase = Phase.ERROR, error = err, progress = 0f) }
        }
    }

    fun stop() {
        job?.cancel()
        upd { it.copy(testing = false, phase = Phase.STOPPED, progress = 0f) }
    }

    private fun friendly(e: Throwable): String = when (e) {
        is UnknownHostException -> "No internet connection."
        is SocketTimeoutException -> "Timeout. The server is not responding."
        is SSLException -> "SSL error. Check your device date and time."
        else -> e.message ?: "Unknown error"
    }

    private suspend fun runPhases(sv: SpeedServer, s: Settings) {
        val conns = s.conns.coerceIn(1, 32)
        upd {
            it.copy(
                phase = Phase.PING, progress = 0.02f, dl = 0.0, ul = 0.0, ping = 0, jitter = 0,
                gauge = 0.0, points = emptyList(), warning = null, error = null, elapsed = 0,
            )
        }
        val pr = SpeedService.ping(sv.url) ?: throw IOException("Server unreachable")
        upd { it.copy(ping = pr.ping, jitter = pr.jitter, progress = 0.08f) }

        upd { it.copy(phase = Phase.DOWNLOAD, points = emptyList(), gauge = 0.0, elapsed = 0) }
        var dl = 0.0
        SpeedService.download(sv.url, s.dlSecs, conns).collect { x ->
            dl = x.avg
            upd {
                it.copy(
                    gauge = x.instant, dl = x.avg, points = (it.points + x.instant).takeLast(80),
                    progress = 0.08f + 0.46f * x.progress, elapsed = x.elapsed,
                )
            }
        }

        upd { it.copy(phase = Phase.UPLOAD, points = emptyList(), gauge = 0.0, elapsed = 0, progress = 0.54f) }
        var ul = 0.0
        try {
            SpeedService.upload(s.ulSecs, conns).collect { x ->
                ul = x.avg
                upd {
                    it.copy(
                        gauge = x.instant, ul = x.avg, points = (it.points + x.instant).takeLast(80),
                        progress = 0.54f + 0.46f * x.progress, elapsed = x.elapsed,
                    )
                }
            }
        } catch (e: IOException) {
            ul = 0.0
            upd { it.copy(ul = 0.0, warning = "Upload failed: ${friendly(e)}") }
        }

        upd { it.copy(phase = Phase.DONE, testing = false, gauge = dl, ul = ul, progress = 1f) }
        if (s.autoSave) {
            val ts = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(Date())
            val e = Entry(ts, sv.flag, sv.name, sv.provider, sv.location, activeLoc, dl, ul, pr.ping, pr.jitter)
            history.value = listOf(e) + history.value.take(499)
            store.saveHistory(history.value)
        }
    }

    fun delete(e: Entry) {
        history.value = history.value.filter { it !== e }
        store.saveHistory(history.value)
    }

    fun clearHistory() {
        history.value = emptyList()
        store.saveHistory(emptyList())
    }

    fun exportCsv(): String = Csv.build(history.value)

    fun importCsv(text: String): Int {
        val seen = history.value.map { it.ts + "|" + it.server }.toMutableSet()
        val added = Csv.parse(text).filter { seen.add(it.ts + "|" + it.server) }
        if (added.isNotEmpty()) {
            history.value = (history.value + added).sortedByDescending { it.ts }
            store.saveHistory(history.value)
        }
        return added.size
    }
}
