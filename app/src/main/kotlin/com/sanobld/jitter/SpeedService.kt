package com.sanobld.jitter

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout
import okhttp3.Callback
import okhttp3.Response
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.channels.ProducerScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import okhttp3.Call
import okhttp3.ConnectionPool
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.RequestBody
import okio.BufferedSink
import java.io.IOException
import java.util.Random
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import okhttp3.HttpUrl.Companion.toHttpUrl
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.sqrt

/** An error whose text is a key of Strings.kt. */
class AppError(val key: String, val detail: String = "") : IOException(key)

data class Sample(val instant: Double, val avg: Double, val progress: Float, val elapsed: Int)
data class PingResult(val ping: Int, val jitter: Int)

private typealias Worker = (AtomicLong, ConcurrentLinkedQueue<Call>, () -> Boolean) -> Unit

private class CountingBody(
    private val size: Long,
    private val counter: AtomicLong,
    private val chunk: ByteArray,
) : RequestBody() {
    override fun contentType() = "application/octet-stream".toMediaType()
    override fun contentLength() = size
    override fun writeTo(sink: BufferedSink) {
        var left = size
        while (left > 0) {
            val n = minOf(left, chunk.size.toLong()).toInt()
            sink.write(chunk, 0, n)
            counter.addAndGet(n.toLong())
            left -= n
        }
    }
}

object SpeedService {
    private const val UP_URL = "https://speed.cloudflare.com/__up"

    val client: OkHttpClient = OkHttpClient.Builder()
        .protocols(listOf(Protocol.HTTP_1_1))
        // Browser-like headers: some servers drop unknown clients; "identity" stops gzip so byte counts stay real.
        .addInterceptor { chain ->
            chain.proceed(
                chain.request().newBuilder()
                    .header("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36")
                    .header("Accept-Encoding", "identity")
                    .header("Accept", "*/*")
                    .build(),
            )
        }
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .writeTimeout(10, TimeUnit.SECONDS)
        .connectionPool(ConnectionPool(96, 1, TimeUnit.MINUTES))
        .build()

    /** Short timeouts so a dead server fails fast instead of blocking the test. */
    /** Some servers (e.g. Hetzner) drop HTTP/1.1 requests; hosts that only work with HTTP/2 are remembered here. */
    private val h2Hosts: MutableSet<String> = ConcurrentHashMap.newKeySet()
    private val h2Client: OkHttpClient = client.newBuilder()
        .protocols(listOf(Protocol.HTTP_2, Protocol.HTTP_1_1))
        .connectTimeout(4, TimeUnit.SECONDS).readTimeout(4, TimeUnit.SECONDS).callTimeout(6, TimeUnit.SECONDS)
        .build()
    private val h2Download: OkHttpClient = client.newBuilder()
        .protocols(listOf(Protocol.HTTP_2, Protocol.HTTP_1_1))
        .build()

    /** Last HTTP error code seen by a transfer worker (0 = none). */
    private val lastCode = AtomicInteger(0)

    private val pingClient: OkHttpClient = client.newBuilder()
        .connectTimeout(4, TimeUnit.SECONDS)
        .readTimeout(4, TimeUnit.SECONDS)
        .callTimeout(6, TimeUnit.SECONDS)
        .build()

    /** Cloudflare has a zero-byte endpoint; other servers use the file URL with a 1-byte range. */
    private fun isCf(url: String) = url.contains("speed.cloudflare.com/__down")

    private fun pingUrlOf(url: String): String =
        if (url.contains("speed.cloudflare.com/__down")) "https://speed.cloudflare.com/__down?bytes=0" else url

    /** Cancellable, non-blocking call: Stop works instantly. */
    private suspend fun Call.await(): Response = suspendCancellableCoroutine { c ->
        c.invokeOnCancellation { cancel() }
        enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) = c.resumeWithException(e)
            override fun onResponse(call: Call, response: Response) = c.resume(response)
        })
    }

    /** One timed request. Returns (ms, "") on success or (-1, reason) on failure. */
    private suspend fun probeOnce(url: String, timeoutMs: Long, plain: Boolean, h2: Boolean = false): Pair<Int, String> {
        val b = Request.Builder().url(pingUrlOf(url))
        if (isCf(url)) b.head() else if (plain) b.header("Connection", "close") else b.header("Range", "bytes=0-0")
        val req = b.build()
        val t0 = System.nanoTime()
        return try {
            withTimeout(timeoutMs) {
                (if (h2) h2Client else pingClient).newCall(req).await().use { r ->
                    val ms = ((System.nanoTime() - t0) / 1_000_000).toInt()
                    if (r.code == 200 || r.code == 206 || r.code == 416 || r.code == 429) ms to "" else -1 to "HTTP ${r.code}"
                }
            }
        } catch (e: TimeoutCancellationException) {
            -1 to "timeout"
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            -1 to (e.javaClass.simpleName + (e.message?.let { ": " + it.take(60) } ?: ""))
        }
    }

    /** Range request first; if the server drops it, retry once as a plain GET on a fresh connection. */
    private suspend fun probe(url: String, timeoutMs: Long): Pair<Int, String> {
        val first = probeOnce(url, timeoutMs, plain = false)
        if (first.first >= 0 || first.second == "timeout" || first.second.startsWith("HTTP")) return first
        val second = probeOnce(url, timeoutMs, plain = true)
        if (second.first >= 0 || second.second == "timeout" || second.second.startsWith("HTTP")) return second
        val third = probeOnce(url, timeoutMs, plain = false, h2 = true)
        if (third.first >= 0) runCatching { h2Hosts.add(pingUrlOf(url).toHttpUrl().host) }
        return if (third.first >= 0) third else second
    }

    /** Real mini-download (first 32 KB). Proves data really flows. Returns (ms to first byte, "") or (-1, reason). */
    private suspend fun fetchOnce(url: String, h2: Boolean): Pair<Int, String> {
        val b = Request.Builder().url(if (isCf(url)) "https://speed.cloudflare.com/__down?bytes=32768" else url)
        if (!isCf(url)) b.header("Range", "bytes=0-32767")
        val req = b.build()
        val t0 = System.nanoTime()
        return try {
            withTimeout(5000) {
                withContext(Dispatchers.IO) {
                    (if (h2) h2Client else pingClient).newCall(req).execute().use { r ->
                        if (r.code != 200 && r.code != 206) return@use -1 to "HTTP ${r.code}"
                        val n = r.body!!.byteStream().read(ByteArray(8192))
                        if (n > 0) ((System.nanoTime() - t0) / 1_000_000).toInt() to "" else -1 to "no data"
                    }
                }
            }
        } catch (e: TimeoutCancellationException) {
            -1 to "timeout"
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            -1 to (e.javaClass.simpleName + (e.message?.let { ": " + it.take(60) } ?: ""))
        }
    }

    suspend fun check(url: String): Pair<Int, String> {
        val first = fetchOnce(url, false)
        if (first.first >= 0 || first.second == "timeout" || first.second.startsWith("HTTP")) return first
        val second = fetchOnce(url, true)
        if (second.first >= 0) runCatching { h2Hosts.add(url.toHttpUrl().host) }
        return if (second.first >= 0) second else first
    }

    /** Checks all candidates at the same time (about 5 s max) so dead servers cost almost nothing. */
    suspend fun checkAll(urls: List<String>): List<Pair<Int, String>> = coroutineScope {
        urls.map { async { check(it) } }.awaitAll()
    }

    suspend fun pingOnce(url: String): Int = probe(url, 5000).first


    /** Standard deviation of the samples, like the previous Flutter app. */
    fun jitterOf(v: List<Int>): Int {
        if (v.size < 2) return 0
        val avg = v.average()
        return sqrt(v.sumOf { (it - avg) * (it - avg) } / v.size).toInt()
    }

    /** Idle ping: 1 warm-up request (DNS + TLS), then 4 measured. Fails after 2 errors in a row. */
    suspend fun ping(url: String): PingResult {
        val v = ArrayList<Int>()
        var fails = 0
        var reason = ""
        for (i in 0 until 5) {
            val (ms, why) = probe(url, 5000)
            if (ms < 0) {
                reason = why
                if (++fails >= 2) throw AppError("err_unreachable", reason)
                continue
            }
            fails = 0
            if (i > 0) v.add(ms)
            delay(250)
        }
        if (v.isEmpty()) throw AppError("err_unreachable", reason)
        return PingResult(v.average().toInt(), jitterOf(v))
    }

    private fun downloadWorker(url: String): Worker = { total, calls, active ->
        val buf = ByteArray(65536)
        while (active()) {
            try {
                val host = runCatching { url.toHttpUrl().host }.getOrDefault("")
                val call = (if (host in h2Hosts) h2Download else client).newCall(Request.Builder().url(url).build())
                calls.add(call)
                call.execute().use { r ->
                    if (!r.isSuccessful) {
                        lastCode.set(r.code)
                        Thread.sleep(if (r.code == 429) 3000 else 500)
                    } else {
                        val s = r.body!!.byteStream()
                        while (active()) {
                            val n = s.read(buf)
                            if (n < 0) break
                            total.addAndGet(n.toLong())
                        }
                    }
                }
            } catch (e: IOException) {
                if (active()) Thread.sleep(300)
            }
        }
    }

    private fun uploadWorker(): Worker = { total, calls, active ->
        val chunk = ByteArray(65536).also { Random().nextBytes(it) }
        while (active()) {
            try {
                val body = CountingBody(4L * 1024 * 1024, total, chunk)
                val call = client.newCall(Request.Builder().url(UP_URL).post(body).build())
                calls.add(call)
                call.execute().use { r ->
                    r.body?.bytes()
                    if (!r.isSuccessful) {
                        lastCode.set(r.code)
                        Thread.sleep(if (r.code == 429) 3000 else 500)
                    }
                }
            } catch (e: IOException) {
                if (active()) Thread.sleep(300)
            }
        }
    }

    private fun measure(secs: Int, conns: Int, worker: Worker): Flow<Sample> = channelFlow {
        lastCode.set(0)
        val total = AtomicLong(0)
        val calls = ConcurrentLinkedQueue<Call>()
        val limit = if (secs == 0) 600_000L else secs * 1000L
        val t0 = System.nanoTime()
        val jobs = List(conns) {
            launch(Dispatchers.IO) { worker(total, calls) { isActive } }
        }
        try {
            tick(total, t0, limit)
        } finally {
            calls.forEach { it.cancel() }
            jobs.forEach { it.cancel() }
        }
    }

    private suspend fun ProducerScope<Sample>.tick(total: AtomicLong, t0: Long, limit: Long) {
        val hist = ArrayDeque<Pair<Long, Long>>()
        var warmT = -1L
        var warmB = 0L
        while (true) {
            delay(250)
            val ms = (System.nanoTime() - t0) / 1_000_000
            val b = total.get()
            if (ms > 6000 && b == 0L) {
                val c = lastCode.get()
                throw if (c > 0) AppError("err_http", c.toString()) else AppError("err_no_data")
            }
            hist.addLast(ms to b)
            while (hist.size > 1 && ms - hist.first().first > 1000) hist.removeFirst()
            val (m0, b0) = hist.first()
            val inst = if (ms > m0) (b - b0) * 8.0 / (ms - m0) / 1000.0 else 0.0
            if (warmT < 0 && ms >= 1000) {
                warmT = ms
                warmB = b
            }
            val avg = when {
                warmT >= 0 && ms - warmT >= 500 -> (b - warmB) * 8.0 / (ms - warmT) / 1000.0
                ms > 0 -> b * 8.0 / ms / 1000.0
                else -> 0.0
            }
            send(Sample(inst, avg, (ms.toFloat() / limit).coerceAtMost(1f), (ms / 1000).toInt()))
            if (ms >= limit) break
        }
    }

    fun download(url: String, secs: Int, conns: Int): Flow<Sample> = measure(secs, conns, downloadWorker(url))

    fun upload(secs: Int, conns: Int): Flow<Sample> = measure(secs, conns, uploadWorker())
}
