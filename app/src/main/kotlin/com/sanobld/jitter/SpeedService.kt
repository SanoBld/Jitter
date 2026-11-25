package com.sanobld.jitter

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.channels.ProducerScope
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import okhttp3.Call
import okhttp3.Callback
import okhttp3.ConnectionPool
import okhttp3.Dispatcher
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.Response
import okio.BufferedSink
import java.io.IOException
import java.util.Random
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
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
    private const val UA = "Jitter/2.0 (Android)"
    private val AUTO = listOf(Protocol.HTTP_2, Protocol.HTTP_1_1)
    private val H1 = listOf(Protocol.HTTP_1_1)

    /** Base client: honest User-Agent, no gzip (so byte counts are real), shared thread pool. */
    private val base: OkHttpClient = OkHttpClient.Builder()
        .addInterceptor { chain ->
            chain.proceed(
                chain.request().newBuilder().header("User-Agent", UA).header("Accept-Encoding", "identity").build(),
            )
        }
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(12, TimeUnit.SECONDS)
        .writeTimeout(12, TimeUnit.SECONDS)
        .dispatcher(Dispatcher().apply { maxRequests = 64; maxRequestsPerHost = 32 })
        .build()

    val client: OkHttpClient get() = base

    /** Hosts that only worked with plain HTTP/1.1 (found by check()). */
    private val h1Hosts: MutableSet<String> = ConcurrentHashMap.newKeySet()

    /** Idle-ping clients, reused so the ping does not include a new TLS handshake each time. */
    private val pingClients = ConcurrentHashMap<String, OkHttpClient>()

    /** Last error seen by a transfer worker (shown if no data arrives). */
    private val lastError = AtomicReference("")

    private fun hostOf(url: String) = runCatching { url.toHttpUrl().host }.getOrDefault("")
    private fun isCf(url: String) = url.contains("speed.cloudflare.com/__down")

    /** A client with its OWN connection pool = its own TCP connection (parallel streams, like a real speed test). */
    private fun connClient(url: String, protos: List<Protocol>? = null, probe: Boolean = false): OkHttpClient {
        val p = protos ?: if (hostOf(url) in h1Hosts) H1 else AUTO
        val b = base.newBuilder().protocols(p).connectionPool(ConnectionPool(2, 1, TimeUnit.MINUTES))
        if (probe) b.callTimeout(6, TimeUnit.SECONDS)
        return b.build()
    }

    private fun errText(e: Exception) = e.javaClass.simpleName + (e.message?.let { ": " + it.take(60) } ?: "")

    /** Cancellable, non-blocking call. */
    private suspend fun Call.await(): Response = suspendCancellableCoroutine { c ->
        c.invokeOnCancellation { cancel() }
        enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) = c.resumeWithException(e)
            override fun onResponse(call: Call, response: Response) = c.resume(response)
        })
    }

    // ---------- server check: a real mini-download ----------

    /** First 32 KB of the file. Returns (ms to first byte, protocol) or (-1, reason). */
    private suspend fun fetchOnce(url: String, protos: List<Protocol>): Pair<Int, String> {
        val b = Request.Builder().url(if (isCf(url)) "https://speed.cloudflare.com/__down?bytes=32768" else url)
        if (!isCf(url)) b.header("Range", "bytes=0-32767")
        val req = b.build()
        val client = connClient(url, protos, probe = true)
        val t0 = System.nanoTime()
        return try {
            withTimeout(7000) {
                withContext(Dispatchers.IO) {
                    client.newCall(req).execute().use { r ->
                        if (r.code != 200 && r.code != 206) return@use -1 to "HTTP ${r.code}"
                        val n = r.body!!.byteStream().read(ByteArray(8192))
                        if (n > 0) ((System.nanoTime() - t0) / 1_000_000).toInt() to r.protocol.toString() else -1 to "no data"
                    }
                }
            }
        } catch (e: TimeoutCancellationException) {
            -1 to "timeout"
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            -1 to errText(e)
        } finally {
            client.connectionPool.evictAll()
        }
    }

    /** Auto protocol first (HTTP/2 when offered); if the server drops it, retry with HTTP/1.1 only. */
    suspend fun check(url: String): Pair<Int, String> {
        val a = fetchOnce(url, AUTO)
        if (a.first >= 0 || a.second == "timeout" || a.second.startsWith("HTTP")) return a
        val b = fetchOnce(url, H1)
        if (b.first >= 0) h1Hosts.add(hostOf(url))
        return if (b.first >= 0) b else a
    }

    /** All candidates at the same time (about 7 s max). */
    suspend fun checkAll(urls: List<String>): List<Pair<Int, String>> = coroutineScope {
        urls.map { async { check(it) } }.awaitAll()
    }

    // ---------- ping ----------

    private suspend fun pingWith(c: OkHttpClient, url: String): Pair<Int, String> {
        val b = Request.Builder().url(if (isCf(url)) "https://speed.cloudflare.com/__down?bytes=0" else url)
        if (isCf(url)) b.head() else b.header("Range", "bytes=0-0")
        val t0 = System.nanoTime()
        return try {
            withTimeout(5000) {
                c.newCall(b.build()).await().use { r ->
                    val ms = ((System.nanoTime() - t0) / 1_000_000).toInt()
                    if (r.code == 200 || r.code == 206 || r.code == 416 || r.code == 429) ms to "" else -1 to "HTTP ${r.code}"
                }
            }
        } catch (e: TimeoutCancellationException) {
            -1 to "timeout"
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            -1 to errText(e)
        }
    }

    /** Ping while a transfer runs. -1 on failure. */
    suspend fun pingOnce(url: String): Int = pingWith(pingClients[url] ?: connClient(url, probe = true), url).first

    /** Standard deviation of the samples, like the previous Flutter app. */
    fun jitterOf(v: List<Int>): Int {
        if (v.size < 2) return 0
        val avg = v.average()
        return sqrt(v.sumOf { (it - avg) * (it - avg) } / v.size).toInt()
    }

    /** Idle ping: 1 warm-up (DNS + TLS), then 5 measured on the same connection. */
    suspend fun ping(url: String): PingResult {
        val c = connClient(url, probe = true)
        pingClients[url] = c
        val v = ArrayList<Int>()
        var fails = 0
        var reason = ""
        for (i in 0 until 6) {
            val (ms, why) = pingWith(c, url)
            if (ms < 0) {
                reason = why
                if (++fails >= 2) throw AppError("err_unreachable", reason)
                continue
            }
            if (i > 0) v.add(ms)
            delay(150)
        }
        if (v.isEmpty()) throw AppError("err_unreachable", reason)
        return PingResult(v.average().toInt(), jitterOf(v))
    }

    // ---------- transfers ----------

    private fun downloadWorker(url: String): Worker = { total, calls, active ->
        val c = connClient(url)
        val buf = ByteArray(65536)
        try {
            while (active()) {
                try {
                    val call = c.newCall(Request.Builder().url(url).build())
                    calls.add(call)
                    call.execute().use { r ->
                        if (!r.isSuccessful) {
                            lastError.set("HTTP ${r.code}")
                            Thread.sleep(if (r.code == 429) 3000 else 700)
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
                    if (active()) {
                        lastError.set(errText(e))
                        Thread.sleep(500)
                    }
                }
            }
        } finally {
            c.connectionPool.evictAll()
        }
    }

    private fun uploadWorker(): Worker = { total, calls, active ->
        val c = connClient(UP_URL)
        val chunk = ByteArray(65536).also { Random().nextBytes(it) }
        try {
            while (active()) {
                try {
                    val body = CountingBody(4L * 1024 * 1024, total, chunk)
                    val call = c.newCall(Request.Builder().url(UP_URL).post(body).build())
                    calls.add(call)
                    call.execute().use { r ->
                        r.body?.bytes()
                        if (!r.isSuccessful) {
                            lastError.set("HTTP ${r.code}")
                            Thread.sleep(if (r.code == 429) 3000 else 700)
                        }
                    }
                } catch (e: IOException) {
                    if (active()) {
                        lastError.set(errText(e))
                        Thread.sleep(500)
                    }
                }
            }
        } finally {
            c.connectionPool.evictAll()
        }
    }

    private fun measure(secs: Int, conns: Int, worker: Worker): Flow<Sample> = channelFlow {
        lastError.set("")
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
            if (ms > 8000 && b == 0L) {
                val e = lastError.get()
                throw when {
                    e.startsWith("HTTP ") -> AppError("err_http", e.removePrefix("HTTP "))
                    e.isNotEmpty() -> AppError("err_unreachable", e)
                    else -> AppError("err_no_data")
                }
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
