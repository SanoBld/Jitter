package com.sanobld.jitter

import android.app.Application
import org.osmdroid.config.Configuration
import java.io.File

class JitterApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Save the crash text so the next launch can show it (easier to report).
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            runCatching {
                getSharedPreferences("jitter_crash", MODE_PRIVATE).edit()
                    .putString("trace", android.util.Log.getStackTraceString(e).take(3500)).commit()
            }
            previous?.uncaughtException(t, e)
        }
        Configuration.getInstance().apply {
            userAgentValue = packageName
            osmdroidBasePath = File(cacheDir, "osmdroid")
            osmdroidTileCache = File(cacheDir, "osmdroid/tiles")
        }
    }
}
