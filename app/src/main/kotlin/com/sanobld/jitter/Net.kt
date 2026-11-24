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
import java.net.Inet4Address
import kotlin.coroutines.resume

data class IpInfo(val location: String, val isp: String)
data class GpsFix(val city: String, val lat: Double, val lng: Double)

object Net {
    private fun join(a: String, b: String) =
        listOf(a, b).filter { it.isNotEmpty() && it != "null" }.joinToString(", ")

    private fun <T> fetch(url: String, parse: (JSONObject) -> T?): T? = try {
        val req = Request.Builder().url(url).header("User-Agent", "JitterApp/2.0 (speed-test)").build()
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

    fun hasLocationPermission(ctx: Context): Boolean =
        ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    private suspend fun currentLocation(ctx: Context): Location? {
        if (!hasLocationPermission(ctx)) return null
        val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val fine = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val providers = buildList {
            add(LocationManager.NETWORK_PROVIDER)
            if (fine) add(LocationManager.GPS_PROVIDER)
        }.filter { runCatching { lm.isProviderEnabled(it) }.getOrDefault(false) }
        for (provider in providers) {
            val loc = withTimeoutOrNull(10_000) {
                suspendCancellableCoroutine<Location?> { c ->
                    val cs = CancellationSignal()
                    c.invokeOnCancellation { cs.cancel() }
                    LocationManagerCompat.getCurrentLocation(lm, provider, cs, ContextCompat.getMainExecutor(ctx)) {
                        if (c.isActive) c.resume(it)
                    }
                }
            }
            if (loc != null) return loc
        }
        return providers.firstNotNullOfOrNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }
    }

    /** Device position + reverse-geocoded "City, CC" (OpenStreetMap Nominatim). */
    suspend fun gps(ctx: Context): GpsFix? {
        val loc = currentLocation(ctx) ?: return null
        val city = withContext(Dispatchers.IO) {
            val url = "https://nominatim.openstreetmap.org/reverse?lat=${loc.latitude}&lon=${loc.longitude}" +
                "&format=json&zoom=10&accept-language=en"
            fetch(url) { j ->
                val a = j.optJSONObject("address") ?: return@fetch null
                val c = listOf("city", "town", "village", "municipality", "county")
                    .map { a.optString(it) }.firstOrNull { it.isNotEmpty() } ?: ""
                join(c, a.optString("country_code").uppercase()).ifEmpty { null }
            }
        } ?: ""
        return GpsFix(city, loc.latitude, loc.longitude)
    }

    fun netInfo(ctx: Context): NetInfo {
        val cm = ctx.getSystemService(ConnectivityManager::class.java) ?: return NetInfo()
        val net = cm.activeNetwork ?: return NetInfo()
        val caps = cm.getNetworkCapabilities(net)
        val conn = when {
            caps == null -> ""
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "eth"
            else -> ""
        }
        val ip = cm.getLinkProperties(net)?.linkAddresses
            ?.firstOrNull { it.address is Inet4Address && !it.address.isLoopbackAddress }
            ?.address?.hostAddress.orEmpty()
        return NetInfo(conn, ip)
    }
}
