package com.sanobld.jitter

import android.content.Context
import org.json.JSONArray

class Store(ctx: Context) {
    private val p = ctx.getSharedPreferences("jitter", Context.MODE_PRIVATE)

    fun load() = Settings(
        lang = p.getString("lang", null) ?: defaultLang(),
        theme = p.getInt("theme", 0),
        dynamic = p.getBoolean("dynamic", true),
        seed = p.getInt("seed", 0),
        serverUrl = p.getString("serverUrl", "") ?: "",
        unit = p.getInt("unit", 0),
        conns = p.getInt("conns", 4),
        dlSecs = p.getInt("dlSecs", 15),
        ulSecs = p.getInt("ulSecs", 15),
        linked = p.getBoolean("linked", true),
        fallback = p.getBoolean("fallback", true),
        autoSave = p.getBoolean("autoSave", true),
        useGps = p.getBoolean("useGps", false),
        customName = p.getString("customName", "") ?: "",
        customUrl = p.getString("customUrl", "") ?: "",
    )

    fun save(s: Settings) {
        p.edit()
            .putString("lang", s.lang).putInt("theme", s.theme).putBoolean("dynamic", s.dynamic).putInt("seed", s.seed)
            .putString("serverUrl", s.serverUrl).putInt("unit", s.unit).putInt("conns", s.conns)
            .putInt("dlSecs", s.dlSecs).putInt("ulSecs", s.ulSecs).putBoolean("linked", s.linked)
            .putBoolean("fallback", s.fallback).putBoolean("autoSave", s.autoSave)
            .putBoolean("useGps", s.useGps).putString("customName", s.customName)
            .putString("customUrl", s.customUrl)
            .apply()
    }

    fun loadHistory(): List<Entry> {
        val a = try {
            JSONArray(p.getString("history", "[]"))
        } catch (e: Exception) {
            JSONArray()
        }
        return (0 until a.length()).mapNotNull {
            runCatching { Entry.fromJson(a.getJSONObject(it)) }.getOrNull()
        }
    }

    fun saveHistory(list: List<Entry>) {
        val a = JSONArray()
        list.forEach { a.put(it.toJson()) }
        p.edit().putString("history", a.toString()).apply()
    }
}
