package com.sanobld.jitter

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.ProducerScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
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
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs

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
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .writeTimeout(10, TimeUnit.SECONDS)
        .connectionPool(ConnectionPool(64, 1, TimeUnit.MINUTES))
        .build()

    private fun pingOnce(url: String): Int {
        val req = Request.Builder().url(url).header("Range", "bytes=0-0").build()
        val t0 = System.nanoTime()
        return try {
            client.newCall(req).execute().use { r ->
                val ms = ((System.nanoTime() - t0) / 1_000_000).toInt()
                if (r.code == 206) {
                    r.body?.bytes()
                    ms
                } else if (r.code == 200) {
                    ms
                } else {
                    -1
                }
            }
        } catch (e: IOException) {
            -1
        }
    }

    suspend fun ping(url: String): PingResult? = withContext(Dispatchers.IO) {
        val v = ArrayList<Int>()
        for (i in 0 until 6) {
            val ms = pingOnce(url)
            if (i > 0 && ms >= 0) v.add(ms)
            delay(150)
        }
        if (v.isEmpty()) {
            null
        } else {
            var diff = 0.0
            for (i in 1 until v.size) diff += abs(v[i] - v[i - 1])
            val jitter = if (v.size > 1) diff / (v.size - 1) else 0.0
            PingResult(v.average().toInt(), jitter.toInt())
        }
    }

    private fun downloadWorker(url: String): Worker = { total, calls, active ->
        val buf = ByteArray(65536)
        while (active()) {
            try {
                val call = client.newCall(Request.Builder().url(url).build())
                calls.add(call)
                call.execute().use { r ->
                    if (!r.isSuccessful) {
                        Thread.sleep(300)
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
                    if (!r.isSuccessful) Thread.sleep(300)
                }
            } catch (e: IOException) {
                if (active()) Thread.sleep(300)
            }
        }
    }

    private fun measure(secs: Int, conns: Int, worker: Worker): Flow<Sample> = channelFlow {
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
            if (ms > 6000 && b == 0L) throw IOException("No data received")
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
