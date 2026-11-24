package com.sanobld.jitter

import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import java.util.Locale

val LocalLang = compositionLocalOf { "en" }

val LANGS = listOf(Triple("en", "🇬🇧", "English"), Triple("fr", "🇫🇷", "Français"), Triple("es", "🇪🇸", "Español"))

fun defaultLang(): String = Locale.getDefault().language.let { if (it == "fr" || it == "es") it else "en" }

private fun k(en: String, fr: String, es: String) = arrayOf(en, fr, es)

private val S: Map<String, Array<String>> = mapOf(
    "nav_test" to k("Test", "Test", "Test"),
    "nav_logs" to k("Logs", "Journaux", "Registros"),
    "nav_map" to k("Map", "Carte", "Mapa"),
    "nav_settings" to k("Settings", "Paramètres", "Ajustes"),

    "phase_ready" to k("READY", "PRÊT", "LISTO"),
    "phase_checking" to k("CHECKING…", "VÉRIFICATION…", "VERIFICANDO…"),
    "phase_switching" to k("SWITCHING SERVER…", "CHANGEMENT DE SERVEUR…", "CAMBIANDO SERVIDOR…"),
    "phase_ping" to k("PING", "PING", "PING"),
    "phase_download" to k("DOWNLOAD", "TÉLÉCHARGEMENT", "DESCARGA"),
    "phase_upload" to k("UPLOAD", "ENVOI", "SUBIDA"),
    "phase_done" to k("DONE", "TERMINÉ", "COMPLETADO"),
    "phase_stopped" to k("STOPPED", "ARRÊTÉ", "DETENIDO"),
    "phase_error" to k("ERROR", "ERREUR", "ERROR"),

    "grade_excellent" to k("EXCELLENT", "EXCELLENT", "EXCELENTE"),
    "grade_veryGood" to k("VERY GOOD", "TRÈS BON", "MUY BUENO"),
    "grade_good" to k("GOOD", "BON", "BUENO"),
    "grade_fair" to k("FAIR", "MOYEN", "REGULAR"),
    "grade_slow" to k("SLOW", "LENT", "LENTO"),
    "grade_poor" to k("VERY SLOW", "TRÈS LENT", "MUY LENTO"),

    "down" to k("DOWN", "RÉCEPTION", "BAJADA"),
    "up" to k("UP", "ENVOI", "SUBIDA"),
    "ping" to k("PING", "PING", "PING"),
    "jitter" to k("JITTER", "GIGUE", "JITTER"),
    "m_down" to k("Down", "Réception", "Bajada"),
    "m_up" to k("Up", "Envoi", "Subida"),
    "m_ping" to k("Ping", "Ping", "Ping"),
    "m_jitter" to k("Jitter", "Gigue", "Jitter"),

    "detecting" to k("Detecting…", "Détection…", "Detectando…"),
    "unknown_loc" to k("Unknown location", "Lieu inconnu", "Ubicación desconocida"),
    "conn_wifi" to k("Wi-Fi", "Wi-Fi", "Wi-Fi"),
    "conn_mobile" to k("Mobile", "Mobile", "Móvil"),
    "conn_eth" to k("Ethernet", "Ethernet", "Ethernet"),
    "local_ip" to k("Local IP", "IP locale", "IP local"),
    "start" to k("START TEST", "DÉMARRER LE TEST", "INICIAR TEST"),
    "stop" to k("STOP", "ARRÊTER", "PARAR"),

    "select_server" to k("Select server", "Choisir le serveur", "Elegir servidor"),
    "auto_fallback" to k("Auto-fallback", "Repli automatique", "Cambio automático"),
    "auto_fallback_sub" to k("Try the next server if the current one fails", "Essayer le serveur suivant en cas d'échec", "Probar el siguiente servidor si falla"),
    "duration" to k("Test duration", "Durée du test", "Duración de la prueba"),
    "same_dur" to k("Same for download and upload", "Identique pour réception et envoi", "Igual para bajada y subida"),
    "dur_dl" to k("Download", "Réception", "Bajada"),
    "dur_ul" to k("Upload", "Envoi", "Subida"),
    "dur_both" to k("Download + upload", "Réception + envoi", "Bajada + subida"),
    "dur_for_both" to k("{d} for download and upload", "{d} pour réception et envoi", "{d} para bajada y subida"),
    "custom" to k("Custom…", "Personnalisé…", "Personalizado…"),
    "dur_hint" to k("∞ runs until you press STOP (max 10 min).", "∞ continue jusqu'à STOP (max 10 min).", "∞ continúa hasta pulsar PARAR (máx. 10 min)."),
    "dur_dialog_title" to k("Duration (seconds)", "Durée (secondes)", "Duración (segundos)"),
    "dur_dialog_hint" to k("Enter 1 to 3600 s, or leave empty for ∞.", "Entrez 1 à 3600 s, ou laissez vide pour ∞.", "Introduce 1 a 3600 s, o deja vacío para ∞."),
    "ok" to k("OK", "OK", "OK"),
    "cancel" to k("Cancel", "Annuler", "Cancelar"),
    "save" to k("Save", "Enregistrer", "Guardar"),
    "remove" to k("Remove", "Supprimer", "Quitar"),
    "edit" to k("Edit", "Modifier", "Editar"),

    "unit_title" to k("Speed unit", "Unité de vitesse", "Unidad de velocidad"),
    "u0" to k("Megabits / second", "Mégabits / seconde", "Megabits / segundo"),
    "u1" to k("Megabytes / second", "Mégaoctets / seconde", "Megabytes / segundo"),
    "u2" to k("Gigabits / second", "Gigabits / seconde", "Gigabits / segundo"),
    "u3" to k("Gigabytes / second", "Gigaoctets / seconde", "Gigabytes / segundo"),
    "u4" to k("Kilobits / second", "Kilobits / seconde", "Kilobits / segundo"),
    "u5" to k("Kilobytes / second", "Kilooctets / seconde", "Kilobytes / segundo"),

    "conns" to k("Connections per test", "Connexions par test", "Conexiones por prueba"),
    "conns_parallel" to k("{n}× parallel", "{n}× en parallèle", "{n}× en paralelo"),
    "conns_hint" to k(
        "More connections fill faster links. Use 8–16× with a 1 GB or 10 GB server for gigabit fiber.",
        "Plus de connexions saturent les liens rapides. Utilisez 8–16× avec un serveur 1 Go ou 10 Go pour la fibre gigabit.",
        "Más conexiones llenan enlaces rápidos. Usa 8–16× con un servidor de 1 GB o 10 GB para fibra gigabit.",
    ),
    "auto" to k("Auto", "Auto", "Auto"),
    "conns_dialog_title" to k("Custom connections", "Connexions personnalisées", "Conexiones personalizadas"),
    "conns_dialog_hint" to k("Number from 1 to 64", "Nombre de 1 à 64", "Número de 1 a 64"),

    "logs_title" to k("Logs", "Journaux", "Registros"),
    "tests_count" to k("{n} tests · {m} locations", "{n} tests · {m} lieux", "{n} pruebas · {m} ubicaciones"),
    "list" to k("List", "Liste", "Lista"),
    "trend" to k("Trend", "Tendance", "Tendencia"),
    "export_csv" to k("Export CSV", "Exporter en CSV", "Exportar CSV"),
    "export_sub" to k("Share all results as CSV", "Partager tous les résultats en CSV", "Compartir todos los resultados en CSV"),
    "import_csv" to k("Import CSV", "Importer un CSV", "Importar CSV"),
    "clear_all" to k("Clear all", "Tout effacer", "Borrar todo"),
    "clear_title" to k("Clear all logs?", "Effacer tout l'historique ?", "¿Borrar todo el historial?"),
    "clear_body" to k("Delete all test results? This cannot be undone.", "Supprimer tous les résultats ? Irréversible.", "¿Eliminar todos los resultados? No se puede deshacer."),
    "clear_sub" to k("Permanently delete all saved results", "Supprimer définitivement tous les résultats", "Eliminar todos los resultados guardados"),
    "delete_all" to k("Delete all", "Tout supprimer", "Eliminar todo"),
    "deleted" to k("Result deleted.", "Résultat supprimé.", "Resultado eliminado."),
    "no_tests" to k("No tests yet", "Aucun test", "Sin pruebas"),
    "no_tests_hint" to k("Run a speed test to see results here.", "Lancez un test pour voir vos résultats ici.", "Haz una prueba para ver los resultados aquí."),
    "import_hint" to k(
        "Paste a Jitter CSV. Entries with the same date and server are skipped.",
        "Collez un CSV Jitter. Les entrées avec la même date et le même serveur sont ignorées.",
        "Pega un CSV de Jitter. Se omiten las entradas con la misma fecha y servidor.",
    ),
    "import" to k("Import", "Importer", "Importar"),
    "paste" to k("Paste", "Coller", "Pegar"),
    "imported" to k("{n} result(s) imported.", "{n} résultat(s) importé(s).", "{n} resultado(s) importado(s)."),
    "import_none" to k("No valid entries found.", "Aucune entrée valide.", "No se encontraron entradas válidas."),
    "export_empty" to k("No data to export", "Aucune donnée à exporter", "Sin datos para exportar"),
    "avg" to k("AVERAGE", "MOYENNE", "PROMEDIO"),
    "best" to k("BEST", "MEILLEUR", "MEJOR"),
    "worst" to k("WORST", "PIRE", "PEOR"),
    "vs_avg" to k("VS AVERAGE", "VS MOYENNE", "VS PROMEDIO"),
    "avg_short" to k("avg", "moy.", "prom."),
    "test_detail" to k("TEST DETAIL", "DÉTAIL DU TEST", "DETALLE"),
    "from" to k("From", "Depuis", "Desde"),
    "map_location" to k("LOCATION ON MAP", "EMPLACEMENT SUR LA CARTE", "UBICACIÓN EN EL MAPA"),

    "map_title" to k("Test locations", "Carte des tests", "Ubicaciones de pruebas"),
    "map_count" to k("{n} tests on the map", "{n} tests sur la carte", "{n} pruebas en el mapa"),
    "map_no_gps" to k(
        "No GPS data yet. Turn on GPS location in Settings and run a test.",
        "Aucune donnée GPS. Activez la localisation GPS dans les paramètres et lancez un test.",
        "Sin datos GPS. Activa la ubicación GPS en Ajustes y haz una prueba.",
    ),

    "settings" to k("Settings", "Paramètres", "Ajustes"),
    "s_language" to k("LANGUAGE", "LANGUE", "IDIOMA"),
    "s_appearance" to k("APPEARANCE", "APPARENCE", "APARIENCIA"),
    "s_test" to k("TEST", "TEST", "PRUEBA"),
    "s_custom" to k("CUSTOM SERVER", "SERVEUR PERSONNALISÉ", "SERVIDOR PERSONALIZADO"),
    "s_location" to k("LOCATION", "LOCALISATION", "UBICACIÓN"),
    "s_history" to k("HISTORY", "HISTORIQUE", "HISTORIAL"),
    "theme" to k("Theme", "Thème", "Tema"),
    "system" to k("System", "Système", "Sistema"),
    "light" to k("Light", "Clair", "Claro"),
    "dark" to k("Dark", "Sombre", "Oscuro"),
    "dynamic" to k("Dynamic color", "Couleur dynamique", "Color dinámico"),
    "dynamic_sub" to k("Follow your wallpaper colors", "Suit les couleurs du fond d'écran", "Sigue los colores del fondo"),
    "dynamic_old" to k("Needs Android 12 or newer", "Nécessite Android 12 ou plus", "Requiere Android 12 o superior"),
    "accent" to k("Accent color", "Couleur d'accentuation", "Color de acento"),
    "server" to k("Server", "Serveur", "Servidor"),
    "gps" to k("GPS location", "Localisation GPS", "Ubicación GPS"),
    "gps_sub" to k("Show the city name and save the position for the map", "Afficher la ville et enregistrer la position pour la carte", "Mostrar la ciudad y guardar la posición para el mapa"),
    "gps_city" to k("GPS city", "Ville GPS", "Ciudad GPS"),
    "not_detected" to k("Not detected", "Non détecté", "No detectado"),
    "gps_denied" to k("Location permission denied.", "Permission de localisation refusée.", "Permiso de ubicación denegado."),
    "gps_unavail" to k("GPS unavailable. Check your location settings.", "GPS indisponible. Vérifiez la localisation.", "GPS no disponible. Revisa la ubicación."),
    "ip_loc" to k("IP location", "Localisation IP", "Ubicación por IP"),
    "refresh" to k("Refresh", "Actualiser", "Actualizar"),
    "custom_hint" to k("Any direct download URL, for example http://192.168.1.10/file.bin", "Toute URL de téléchargement directe, par exemple http://192.168.1.10/file.bin", "Cualquier URL de descarga directa, por ejemplo http://192.168.1.10/file.bin"),
    "custom_none" to k("No custom server set", "Aucun serveur personnalisé", "Sin servidor personalizado"),
    "srv_name" to k("Server name", "Nom du serveur", "Nombre del servidor"),
    "srv_url" to k("Download URL", "URL de téléchargement", "URL de descarga"),
    "srv_saved" to k("Custom server saved.", "Serveur enregistré.", "Servidor guardado."),
    "srv_removed" to k("Custom server removed.", "Serveur supprimé.", "Servidor eliminado."),
    "srv_bad_url" to k("URL must start with http:// or https://", "L'URL doit commencer par http:// ou https://", "La URL debe empezar con http:// o https://"),
    "auto_save" to k("Auto-save results", "Sauvegarde automatique", "Guardado automático"),
    "auto_save_sub" to k("Add each test to the logs", "Ajouter chaque test à l'historique", "Añadir cada prueba al historial"),
    "footer" to k("Jitter v2.0.0  ·  Made with Kotlin", "Jitter v2.0.0  ·  Fait avec Kotlin", "Jitter v2.0.0  ·  Hecho con Kotlin"),

    "err_no_internet" to k("No internet connection.", "Pas de connexion internet.", "Sin conexión a internet."),
    "err_timeout" to k("Timeout. The server is not responding.", "Délai dépassé. Le serveur ne répond pas.", "Tiempo agotado. El servidor no responde."),
    "err_ssl" to k("SSL error. Check your device date and time.", "Erreur SSL. Vérifiez la date et l'heure.", "Error SSL. Revisa la fecha y la hora."),
    "err_unreachable" to k("Server unreachable.", "Serveur inaccessible.", "Servidor inaccesible."),
    "err_no_data" to k("No data received.", "Aucune donnée reçue.", "No se recibieron datos."),
    "err_no_server" to k("No server available", "Aucun serveur disponible", "Ningún servidor disponible"),
    "err_upload" to k("Upload failed: {m}", "Échec de l'envoi : {m}", "Falló la subida: {m}"),
    "err_raw" to k("{m}", "{m}", "{m}"),
    "err_unknown" to k("Unknown error", "Erreur inconnue", "Error desconocido"),
)

object L {
    fun t(key: String, lang: String): String {
        val a = S[key] ?: return key
        return when (lang) {
            "fr" -> a[1]
            "es" -> a[2]
            else -> a[0]
        }
    }

    fun t(key: String, lang: String, vararg args: Pair<String, Any>): String {
        var r = t(key, lang)
        for ((n, v) in args) r = r.replace("{$n}", v.toString())
        return r
    }

    fun msg(m: Msg, lang: String): String = t(m.key, lang, "m" to m.m)

    fun has(key: String) = S.containsKey(key)
    fun keys(): Set<String> = S.keys
}

@Composable
fun tr(key: String): String = L.t(key, LocalLang.current)

@Composable
fun tr(key: String, vararg args: Pair<String, Any>): String = L.t(key, LocalLang.current, *args)

@Composable
fun tr(m: Msg): String = L.msg(m, LocalLang.current)
