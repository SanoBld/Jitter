package com.sanobld.jitter

import androidx.compose.ui.graphics.Color
import org.json.JSONObject
import java.util.Locale

data class SpeedServer(
    val name: String,
    val location: String,
    val provider: String,
    val flag: String,
    val url: String,
    val minConns: Int,
    val size: String,
)

object Servers {
    private fun s(n: String, l: String, p: String, f: String, u: String, c: Int, sz: String) =
        SpeedServer(n, l, p, f, u, c, sz)

    val builtin = listOf(
        s("Cloudflare 256 MB", "Anycast, Global", "Cloudflare", "🌐", "https://speed.cloudflare.com/__down?bytes=268435456", 6, "256 MB"),
        s("Cloudflare 100 MB", "Anycast, Global", "Cloudflare", "🌐", "https://speed.cloudflare.com/__down?bytes=104857600", 4, "100 MB"),
        s("OVH 10 GB", "France", "OVH", "🇫🇷", "https://proof.ovh.net/files/10Gb.dat", 16, "10 GB"),
        s("OVH 1 GB", "France", "OVH", "🇫🇷", "https://proof.ovh.net/files/1Gb.dat", 8, "1 GB"),
        s("OVH 100 MB", "France", "OVH", "🇫🇷", "https://proof.ovh.net/files/100Mb.dat", 4, "100 MB"),
        s("Falkenstein 10 GB", "Falkenstein, DE", "Hetzner", "🇩🇪", "https://fsn1-speed.hetzner.com/10GB.bin", 16, "10 GB"),
        s("Falkenstein 1 GB", "Falkenstein, DE", "Hetzner", "🇩🇪", "https://fsn1-speed.hetzner.com/1GB.bin", 8, "1 GB"),
        s("Falkenstein 100 MB", "Falkenstein, DE", "Hetzner", "🇩🇪", "https://fsn1-speed.hetzner.com/100MB.bin", 4, "100 MB"),
        s("Nuremberg 10 GB", "Nuremberg, DE", "Hetzner", "🇩🇪", "https://nbg1-speed.hetzner.com/10GB.bin", 16, "10 GB"),
        s("Nuremberg 1 GB", "Nuremberg, DE", "Hetzner", "🇩🇪", "https://nbg1-speed.hetzner.com/1GB.bin", 8, "1 GB"),
        s("Helsinki 1 GB", "Helsinki, FI", "Hetzner", "🇫🇮", "https://hel1-speed.hetzner.com/1GB.bin", 8, "1 GB"),
        s("Ashburn 1 GB", "Ashburn, US", "Hetzner", "🇺🇸", "https://ash-speed.hetzner.com/1GB.bin", 8, "1 GB"),
    )
}

enum class SpeedUnit(val label: String, private val k: Double) {
    MBIT("Mb/s", 1.0),
    MBYTE("MB/s", 1.0 / 8),
    GBIT("Gb/s", 1.0 / 1000),
    GBYTE("GB/s", 1.0 / 8000),
    KBIT("Kb/s", 1000.0),
    KBYTE("KB/s", 125.0);

    fun fmt(mbps: Double): String {
        val v = mbps * k
        return when (this) {
            GBIT, GBYTE -> if (v >= 1) "%.2f".format(v) else if (v >= 0.1) "%.3f".format(v) else "%.4f".format(v)
            KBIT, KBYTE -> if (v >= 10000) "%.0f".format(v) else "%.1f".format(v)
            else -> if (v >= 100) "%.0f".format(v) else "%.1f".format(v)
        }
    }
}

enum class Grade(val key: String, val color: Color) {
    EXCELLENT("grade_excellent", Color(0xFF1B8E3E)),
    VERY_GOOD("grade_veryGood", Color(0xFF2E9E50)),
    GOOD("grade_good", Color(0xFF1E78D2)),
    FAIR("grade_fair", Color(0xFFE08A00)),
    SLOW("grade_slow", Color(0xFFD9541E)),
    POOR("grade_poor", Color(0xFFD32F2F)),
}

fun gradeFor(mbps: Double): Grade = when {
    mbps >= 500 -> Grade.EXCELLENT
    mbps >= 200 -> Grade.VERY_GOOD
    mbps >= 100 -> Grade.GOOD
    mbps >= 30 -> Grade.FAIR
    mbps >= 10 -> Grade.SLOW
    else -> Grade.POOR
}

/** theme: 0 system, 1 light, 2 dark. conns: 0 = Auto (4). secs: 0 = infinite. */
data class Settings(
    val lang: String = defaultLang(),
    val theme: Int = 0,
    val dynamic: Boolean = true,
    val seed: Int = 0,
    val serverUrl: String = "",
    val unit: Int = 0,
    val conns: Int = 4,
    val dlSecs: Int = 15,
    val ulSecs: Int = 15,
    val linked: Boolean = true,
    val fallback: Boolean = true,
    val autoSave: Boolean = true,
    val amoled: Boolean = false,
    val haptic: Boolean = true,
    val keepOn: Boolean = true,
    val useGps: Boolean = false,
    val customName: String = "",
    val customUrl: String = "",
) {
    val effectiveConns: Int get() = if (conns <= 0) 4 else conns.coerceIn(1, 64)
}

val SEEDS = listOf(0xFF6750A4, 0xFF1565C0, 0xFF00796B, 0xFF2E7D32, 0xFFE65100, 0xFFC62828, 0xFFAD1457)

enum class Phase(val key: String) {
    READY("phase_ready"),
    CHECKING("phase_checking"),
    SWITCHING("phase_switching"),
    PING("phase_ping"),
    DOWNLOAD("phase_download"),
    UPLOAD("phase_upload"),
    DONE("phase_done"),
    STOPPED("phase_stopped"),
    ERROR("phase_error"),
}

/** A translatable message: [key] into Strings.kt, [m] fills the {m} placeholder. */
data class Msg(val key: String, val m: String = "")

data class TestState(
    val phase: Phase = Phase.READY,
    val testing: Boolean = false,
    val gauge: Double = 0.0,
    val dl: Double = 0.0,
    val ul: Double = 0.0,
    val ping: Int = 0,
    val jitter: Int = 0,
    val progress: Float = 0f,
    val elapsed: Int = 0,
    val points: List<Double> = emptyList(),
    val dlPoints: List<Double> = emptyList(),
    val error: Msg? = null,
    val warning: Msg? = null,
)

/** conn: "wifi" | "mobile" | "eth" | "" */
data class NetInfo(val conn: String = "", val localIp: String = "")

data class Entry(
    val ts: String,
    val flag: String,
    val server: String,
    val provider: String,
    val serverLoc: String,
    val userLoc: String,
    val dl: Double,
    val ul: Double,
    val ping: Int,
    val jitter: Int,
    val lat: Double? = null,
    val lng: Double? = null,
) {
    val hasPos: Boolean get() = lat != null && lng != null

    fun toJson(): JSONObject = JSONObject()
        .put("ts", ts).put("flag", flag).put("server", server).put("provider", provider)
        .put("serverLoc", serverLoc).put("userLoc", userLoc)
        .put("dl", dl).put("ul", ul).put("ping", ping).put("jitter", jitter)
        .also {
            if (lat != null && lng != null) it.put("lat", lat).put("lng", lng)
        }

    companion object {
        fun fromJson(j: JSONObject) = Entry(
            j.getString("ts"), j.optString("flag"), j.optString("server"), j.optString("provider"),
            j.optString("serverLoc"), j.optString("userLoc"),
            j.getDouble("dl"), j.getDouble("ul"), j.getInt("ping"), j.optInt("jitter"),
            if (j.has("lat") && !j.isNull("lat")) j.getDouble("lat") else null,
            if (j.has("lng") && !j.isNull("lng")) j.getDouble("lng") else null,
        )
    }
}

/** Same columns as the old Flutter app, so exports of either app import into both. */
object Csv {
    private const val HEADER =
        "timestamp,flag,server,provider,server_location,user_location," +
            "download_mbps,upload_mbps,ping_ms,jitter_ms,unit,lat,lng"

    private fun q(s: String) = "\"" + s.replace("\"", "\"\"") + "\""
    private fun f(d: Double) = String.format(Locale.US, "%.2f", d)
    private fun c(d: Double?) = if (d == null) "" else String.format(Locale.US, "%.6f", d)

    fun build(list: List<Entry>): String {
        val b = StringBuilder("\uFEFF").append(HEADER).append('\n')
        for (e in list) {
            b.append(
                listOf(
                    q(e.ts), q(e.flag), q(e.server), q(e.provider), q(e.serverLoc), q(e.userLoc),
                    f(e.dl), f(e.ul), e.ping, e.jitter, "Mb/s", c(e.lat), c(e.lng),
                ).joinToString(",")
            ).append('\n')
        }
        return b.toString()
    }

    fun parse(text: String): List<Entry> {
        val out = ArrayList<Entry>()
        for (raw in text.removePrefix("\uFEFF").lines()) {
            val line = raw.trim()
            if (line.isEmpty() || line.lowercase(Locale.ROOT).startsWith("timestamp")) continue
            val c = split(line)
            if (c.size < 10) continue
            out.add(
                Entry(
                    c[0], c[1], c[2], c[3], c[4], c[5],
                    c[6].toDoubleOrNull() ?: 0.0, c[7].toDoubleOrNull() ?: 0.0,
                    c[8].toIntOrNull() ?: 0, c[9].toIntOrNull() ?: 0,
                    c.getOrNull(11)?.toDoubleOrNull(), c.getOrNull(12)?.toDoubleOrNull(),
                )
            )
        }
        return out
    }

    private fun split(line: String): List<String> {
        val r = ArrayList<String>()
        val b = StringBuilder()
        var inQ = false
        var i = 0
        while (i < line.length) {
            val ch = line[i]
            if (ch == '"') {
                if (inQ && i + 1 < line.length && line[i + 1] == '"') {
                    b.append('"')
                    i++
                } else {
                    inQ = !inQ
                }
            } else if (ch == ',' && !inQ) {
                r.add(b.toString().trim())
                b.setLength(0)
            } else {
                b.append(ch)
            }
            i++
        }
        r.add(b.toString().trim())
        return r
    }
}
