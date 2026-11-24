package com.sanobld.jitter

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import androidx.core.os.CancellationSignal
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.Request
import org.json.JSONObject
import kotlin.coroutines.resume

data class IpInfo(val location: String, val isp: String)

object Net {
    private fun join(a: String, b: String) =
        listOf(a, b).filter { it.isNotEmpty() && it != "null" }.joinToString(", ")

    private fun <T> fetch(url: String, parse: (JSONObject) -> T?): T? = try {
        val req = Request.Builder().url(url).header("User-Agent", "JitterApp/1.0").build()
        SpeedService.client.newCall(req).execute().use { r ->
            if (r.isSuccessful) parse(JSONObject(r.body!!.string())) else null
        }
    } catch (e: Exception) {
        null
    }

    private fun info(city: String, cc: String, isp: String): IpInfo? =
        join(city, cc).let { if (it.isEmpty()) null else IpInfo(it, isp) }

    private val asPrefix = Regex("^AS\\d+\\s*")

    suspend fun ipInfo(): IpInfo? = withContext(Dispatchers.IO) {
        fetch("https://ipwho.is/") { j ->
            if (j.optBoolean("success", true)) {
                info(j.optString("city"), j.optString("country_code"), j.optJSONObject("connection")?.optString("isp") ?: "")
            } else null
        } ?: fetch("https://ipapi.co/json/") { j ->
            info(j.optString("city"), j.optString("country_code"), j.optString("org").replace(asPrefix, ""))
        } ?: fetch("https://ipinfo.io/json") { j ->
            info(j.optString("city"), j.optString("country"), j.optString("org").replace(asPrefix, ""))
        }
    }

    @SuppressLint("MissingPermission")
    suspend fun gpsCity(ctx: Context): String? {
        val granted = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION)
        if (granted != PackageManager.PERMISSION_GRANTED) return null
        val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val provider = LocationManager.NETWORK_PROVIDER
        if (!runCatching { lm.isProviderEnabled(provider) }.getOrDefault(false)) return null
        val loc = withTimeoutOrNull(12_000) {
            suspendCancellableCoroutine<Location?> { c ->
                val cs = CancellationSignal()
                c.invokeOnCancellation { cs.cancel() }
                LocationManagerCompat.getCurrentLocation(lm, provider, cs, ContextCompat.getMainExecutor(ctx)) {
                    c.resume(it)
                }
            }
        } ?: return null
        return withContext(Dispatchers.IO) {
            val url = "https://nominatim.openstreetmap.org/reverse?lat=${loc.latitude}&lon=${loc.longitude}" +
                "&format=json&zoom=10&accept-language=en"
            fetch(url) { j ->
                val a = j.optJSONObject("address") ?: return@fetch null
                val city = listOf("city", "town", "village", "municipality", "county")
                    .map { a.optString(it) }.firstOrNull { it.isNotEmpty() } ?: ""
                join(city, a.optString("country_code").uppercase()).ifEmpty { null }
            }
        }
    }

    fun connType(ctx: Context): String {
        val cm = ctx.getSystemService(ConnectivityManager::class.java) ?: return ""
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return ""
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "Mobile"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet"
            else -> ""
        }
    }
}
