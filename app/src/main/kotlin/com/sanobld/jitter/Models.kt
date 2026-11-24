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
        s("Cloudflare 100 MB", "Anycast, Global", "Cloudflare", "🌐", "https://speed.cloudflare.com/__down?bytes=104857600", 4, "100 MB"),
        s("Cloudflare 1 GB", "Anycast, Global", "Cloudflare", "🌐", "https://speed.cloudflare.com/__down?bytes=1073741824", 8, "1 GB"),
        s("Strasbourg 10 GB", "Strasbourg, FR", "OVH", "🇫🇷", "https://proof.ovh.net/files/10Gb.dat", 16, "10 GB"),
        s("Strasbourg 1 GB", "Strasbourg, FR", "OVH", "🇫🇷", "https://proof.ovh.net/files/1Gb.dat", 8, "1 GB"),
        s("Paris 100 MB", "Paris, FR", "OVH", "🇫🇷", "https://proof.ovh.net/files/100Mb.dat", 4, "100 MB"),
        s("Falkenstein 10 GB", "Falkenstein, DE", "Hetzner", "🇩🇪", "https://fsn1-speed.hetzner.com/10GB.bin", 16, "10 GB"),
        s("Falkenstein 1 GB", "Falkenstein, DE", "Hetzner", "🇩🇪", "https://fsn1-speed.hetzner.com/1GB.bin", 8, "1 GB"),
        s("Falkenstein 100 MB", "Falkenstein, DE", "Hetzner", "🇩🇪", "https://fsn1-speed.hetzner.com/100MB.bin", 4, "100 MB"),
        s("Nuremberg 10 GB", "Nuremberg, DE", "Hetzner", "🇩🇪", "https://nbg1-speed.hetzner.com/10GB.bin", 16, "10 GB"),
        s("Nuremberg 1 GB", "Nuremberg, DE", "Hetzner", "🇩🇪", "https://nbg1-speed.hetzner.com/1GB.bin", 8, "1 GB"),
        s("Helsinki 1 GB", "Helsinki, FI", "Hetzner", "🇫🇮", "https://hel1-speed.hetzner.com/1GB.bin", 8, "1 GB"),
        s("Ashburn 1 GB", "Ashburn, US", "Hetzner", "🇺🇸", "https://ash-speed.hetzner.com/1GB.bin", 8, "1 GB"),
        s("Amsterdam", "Amsterdam, NL", "Leaseweb", "🇳🇱", "https://mirror.nl.leaseweb.net/speedtest/1000mb.bin", 8, "1 GB"),
        s("Frankfurt", "Frankfurt, DE", "Leaseweb", "🇩🇪", "https://mirror.de.leaseweb.net/speedtest/1000mb.bin", 8, "1 GB"),
        s("Ashburn", "Ashburn, US", "Leaseweb", "🇺🇸", "https://mirror.us.leaseweb.net/speedtest/100mb.bin", 4, "100 MB"),
        s("Singapore", "Singapore, SG", "Leaseweb", "🇸🇬", "https://mirror.sg.leaseweb.net/speedtest/100mb.bin", 4, "100 MB"),
        s("London", "London, UK", "Clouvider", "🇬🇧", "https://lon.speedtest.clouvider.net/1000MB.test", 8, "1 GB"),
        s("Frankfurt", "Frankfurt, DE", "Clouvider", "🇩🇪", "https://fra.speedtest.clouvider.net/1000MB.test", 8, "1 GB"),
        s("Amsterdam", "Amsterdam, NL", "Clouvider", "🇳🇱", "https://ams.speedtest.clouvider.net/1000MB.test", 8, "1 GB"),
        s("New York", "New York, US", "Clouvider", "🇺🇸", "https://nyc.speedtest.clouvider.net/100MB.test", 4, "100 MB"),
        s("Los Angeles", "Los Angeles, US", "Clouvider", "🇺🇸", "https://la.speedtest.clouvider.net/100MB.test", 4, "100 MB"),
    )
}

enum class SpeedUnit(val label: String, val desc: String, private val k: Double) {
    MBIT("Mb/s", "Megabits / second", 1.0),
    MBYTE("MB/s", "Megabytes / second", 1.0 / 8),
    GBIT("Gb/s", "Gigabits / second", 1.0 / 1000),
    GBYTE("GB/s", "Gigabytes / second", 1.0 / 8000),
    KBIT("Kb/s", "Kilobits / second", 1000.0),
    KBYTE("KB/s", "Kilobytes / second", 125.0);

    fun fmt(mbps: Double): String {
        val v = mbps * k
        return when (this) {
            GBIT, GBYTE -> if (v >= 1) "%.2f".format(v) else if (v >= 0.1) "%.3f".format(v) else "%.4f".format(v)
            KBIT, KBYTE -> if (v >= 10000) "%.0f".format(v) else "%.1f".format(v)
            else -> if (v >= 100) "%.0f".format(v) else "%.1f".format(v)
        }
    }
}

enum class Grade(val label: String, val color: Color) {
    EXCELLENT("EXCELLENT", Color(0xFF1B8E3E)),
    VERY_GOOD("VERY GOOD", Color(0xFF2E9E50)),
    GOOD("GOOD", Color(0xFF1E78D2)),
    FAIR("FAIR", Color(0xFFE08A00)),
    SLOW("SLOW", Color(0xFFD9541E)),
    POOR("VERY SLOW", Color(0xFFD32F2F)),
}

fun gradeFor(mbps: Double): Grade = when {
    mbps >= 500 -> Grade.EXCELLENT
    mbps >= 200 -> Grade.VERY_GOOD
    mbps >= 100 -> Grade.GOOD
    mbps >= 30 -> Grade.FAIR
    mbps >= 10 -> Grade.SLOW
    else -> Grade.POOR
}

data class Settings(
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
    val useGps: Boolean = false,
    val customName: String = "",
    val customUrl: String = "",
)

val SEEDS = listOf(0xFF6750A4, 0xFF1565C0, 0xFF00796B, 0xFF2E7D32, 0xFFE65100, 0xFFC62828, 0xFFAD1457)

enum class Phase(val label: String) {
    READY("READY"),
    CHECKING("CHECKING…"),
    SWITCHING("SWITCHING SERVER…"),
    PING("PING"),
    DOWNLOAD("DOWNLOAD"),
    UPLOAD("UPLOAD"),
    DONE("DONE"),
    STOPPED("STOPPED"),
    ERROR("ERROR"),
}

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
    val error: String? = null,
    val warning: String? = null,
    val conn: String = "",
)

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
) {
    fun toJson(): JSONObject = JSONObject()
        .put("ts", ts).put("flag", flag).put("server", server).put("provider", provider)
        .put("serverLoc", serverLoc).put("userLoc", userLoc)
        .put("dl", dl).put("ul", ul).put("ping", ping).put("jitter", jitter)

    companion object {
        fun fromJson(j: JSONObject) = Entry(
            j.getString("ts"), j.optString("flag"), j.optString("server"), j.optString("provider"),
            j.optString("serverLoc"), j.optString("userLoc"),
            j.getDouble("dl"), j.getDouble("ul"), j.getInt("ping"), j.optInt("jitter"),
        )
    }
}

object Csv {
    private const val HEADER =
        "timestamp,flag,server,provider,server_location,user_location,download_mbps,upload_mbps,ping_ms,jitter_ms,unit"

    private fun q(s: String) = "\"" + s.replace("\"", "\"\"") + "\""
    private fun f(d: Double) = String.format(Locale.US, "%.2f", d)

    fun build(list: List<Entry>): String {
        val b = StringBuilder(HEADER).append('\n')
        for (e in list) {
            b.append(
                listOf(
                    q(e.ts), q(e.flag), q(e.server), q(e.provider), q(e.serverLoc), q(e.userLoc),
                    f(e.dl), f(e.ul), e.ping, e.jitter, "Mb/s",
                ).joinToString(",")
            ).append('\n')
        }
        return b.toString()
    }

    fun parse(text: String): List<Entry> {
        val out = ArrayList<Entry>()
        for (line in text.removePrefix("\uFEFF").lines()) {
            if (line.isBlank() || line.startsWith("timestamp")) continue
            val c = split(line.trim())
            if (c.size < 10) continue
            out.add(
                Entry(
                    c[0], c[1], c[2], c[3], c[4], c[5],
                    c[6].toDoubleOrNull() ?: 0.0, c[7].toDoubleOrNull() ?: 0.0,
                    c[8].toIntOrNull() ?: 0, c[9].toIntOrNull() ?: 0,
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
