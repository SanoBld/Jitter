package com.sanobld.jitter

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import java.net.ConnectException
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
    val net = MutableStateFlow(NetInfo())
    val ipLoc = MutableStateFlow("")
    val isp = MutableStateFlow("")
    val gpsCity = MutableStateFlow("")
    val gpsLat = MutableStateFlow<Double?>(null)
    val gpsLng = MutableStateFlow<Double?>(null)
    val locBusy = MutableStateFlow(false)
    val message = MutableSharedFlow<Msg>(extraBufferCapacity = 4)
    private var job: Job? = null

    init {
        refreshLocation()
    }

    fun toast(key: String, m: String = "") {
        message.tryEmit(Msg(key, m))
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

    fun saveCustomServer(name: String, url: String): Boolean {
        val u = url.trim()
        if (!(u.startsWith("http://") || u.startsWith("https://"))) {
            toast("srv_bad_url")
            return false
        }
        set { it.copy(customName = name.trim(), customUrl = u, serverUrl = u) }
        toast("srv_saved")
        return true
    }

    fun removeCustomServer() {
        set { it.copy(customName = "", customUrl = "", serverUrl = "") }
        toast("srv_removed")
    }

    val activeLoc: String
        get() = if (settings.value.useGps && gpsCity.value.isNotEmpty()) gpsCity.value else ipLoc.value

    fun refreshNet() {
        net.value = Net.netInfo(getApplication<Application>())
    }

    fun refreshLocation() {
        refreshNet()
        viewModelScope.launch {
            locBusy.value = true
            Net.ipInfo()?.let {
                ipLoc.value = it.location
                isp.value = it.isp
            }
            if (settings.value.useGps) refreshGps()
            locBusy.value = false
        }
    }

    fun setGps(on: Boolean) {
        set { it.copy(useGps = on) }
        if (on) viewModelScope.launch {
            locBusy.value = true
            refreshGps()
            locBusy.value = false
        }
    }

    private suspend fun refreshGps() {
        val fix = Net.gps(getApplication<Application>())
        if (fix == null) {
            toast("gps_unavail")
        } else {
            if (fix.city.isNotEmpty()) gpsCity.value = fix.city
            gpsLat.value = fix.lat
            gpsLng.value = fix.lng
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
            val order = all.indices.map { (first + it) % all.size }.let { if (s.fallback) it.take(6) else it.take(1) }
            refreshNet()
            test.value = TestState(testing = true, phase = Phase.CHECKING)
            var err = Msg("err_no_server")
            var ok = false
            // 1) check candidates in parallel with a real mini-download; keep the healthy ones, in order
            val usable: List<Int>
            if (s.fallback && order.size > 1) {
                upd { it.copy(phase = Phase.CHECKING) }
                val res = SpeedService.checkAll(order.map { all[it].url })
                usable = order.filterIndexed { k, _ -> res[k].first >= 0 }.take(2)
                if (usable.isEmpty()) err = friendly(AppError("err_unreachable", res.first().second))
            } else usable = order
            // 2) run the test on the first healthy server (second one only if it breaks)
            for ((n, i) in usable.withIndex()) {
                try {
                    runPhases(all[i], s)
                    ok = true
                    break
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    err = friendly(e)
                    if (n < usable.lastIndex) upd { it.copy(phase = Phase.SWITCHING) }
                }
            }
            if (!ok) upd { it.copy(testing = false, phase = Phase.ERROR, error = err, progress = 0f) }
        }
    }

    fun stop() {
        job?.cancel()
        upd { it.copy(testing = false, phase = Phase.STOPPED, progress = 0f) }
    }

    private fun friendly(e: Throwable): Msg = when (e) {
        is AppError -> Msg(e.key, e.detail)
        is UnknownHostException -> Msg("err_no_internet")
        is SocketTimeoutException -> Msg("err_timeout")
        is SSLException -> Msg("err_ssl")
        is ConnectException -> Msg("err_unreachable")
        else -> e.message?.let { Msg("err_raw", it) } ?: Msg("err_unknown")
    }

    /** Ping every 2 s while the speed phases run, like the old app: shows latency under load. */
    private suspend fun backgroundPing(url: String) {
        val hist = ArrayList<Int>()
        while (true) {
            delay(3000)
            val ms = SpeedService.pingOnce(url)
            if (ms >= 0) {
                hist.add(ms)
                if (hist.size > 20) hist.removeAt(0)
                upd { it.copy(ping = ms, jitter = if (hist.size >= 3) SpeedService.jitterOf(hist) else it.jitter) }
            }
        }
    }

    private suspend fun runPhases(sv: SpeedServer, s: Settings) {
        val conns = s.effectiveConns
        upd {
            it.copy(
                phase = Phase.PING, progress = 0.02f, dl = 0.0, ul = 0.0, ping = 0, jitter = 0,
                gauge = 0.0, points = emptyList(), dlPoints = emptyList(), warning = null, error = null, elapsed = 0,
            )
        }
        val pr = SpeedService.ping(sv.url)
        upd { it.copy(ping = pr.ping, jitter = pr.jitter, progress = 0.08f) }

        var dl = 0.0
        var ul = 0.0
        coroutineScope {
            val bg = launch { backgroundPing(sv.url) }
            try {
                upd { it.copy(phase = Phase.DOWNLOAD, points = emptyList(), gauge = 0.0, elapsed = 0) }
                SpeedService.download(sv.url, s.dlSecs, conns).collect { x ->
                    dl = x.avg
                    upd {
                        it.copy(
                            gauge = x.instant, dl = x.avg, points = (it.points + x.instant).takeLast(120),
                            progress = 0.08f + 0.46f * x.progress, elapsed = x.elapsed,
                        )
                    }
                }

                upd { it.copy(phase = Phase.UPLOAD, dlPoints = it.points, points = emptyList(), gauge = 0.0, elapsed = 0, progress = 0.54f) }
                try {
                    SpeedService.upload(s.ulSecs, conns).collect { x ->
                        ul = x.avg
                        upd {
                            it.copy(
                                gauge = x.instant, ul = x.avg, points = (it.points + x.instant).takeLast(120),
                                progress = 0.54f + 0.46f * x.progress, elapsed = x.elapsed,
                            )
                        }
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    ul = 0.0
                    val m = friendly(e)
                    upd { it.copy(ul = 0.0, warning = Msg("err_upload", L.msg(m, settings.value.lang))) }
                }
            } finally {
                bg.cancel()
            }
        }

        val finalPing = pr.ping
        val finalJitter = pr.jitter
        upd { it.copy(phase = Phase.DONE, testing = false, gauge = dl, ul = ul, ping = pr.ping, jitter = pr.jitter, progress = 1f) }
        if (s.autoSave) {
            val ts = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(Date())
            val useGps = s.useGps
            val e = Entry(
                ts, sv.flag, sv.name, sv.provider, sv.location, activeLoc, dl, ul, finalPing, finalJitter,
                if (useGps) gpsLat.value else null, if (useGps) gpsLng.value else null,
            )
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

    /** @return number of new entries added. */
    fun importCsv(text: String): Int {
        val seen = history.value.map { it.ts + "|" + it.server }.toMutableSet()
        val added = Csv.parse(text).filter { seen.add(it.ts + "|" + it.server) }
        if (added.isNotEmpty()) {
            history.value = (history.value + added).sortedByDescending { it.ts }.take(500)
            store.saveHistory(history.value)
        }
        return added.size
    }
}
