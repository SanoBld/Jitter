import 'package:flutter/material.dart';

const _t = <String, Map<String, String>>{
  'tabTest':     {'en': 'Test',      'fr': 'Test',        'es': 'Test'},
  'tabLogs':     {'en': 'Logs',      'fr': 'Journaux',    'es': 'Registros'},
  'tabMap':      {'en': 'Map',       'fr': 'Carte',       'es': 'Mapa'},
  'tabSettings': {'en': 'Settings',  'fr': 'Paramètres',  'es': 'Ajustes'},

  'ready':     {'en': 'READY',      'fr': 'PRÊT',        'es': 'LISTO'},
  'done':      {'en': 'DONE',       'fr': 'TERMINÉ',     'es': 'LISTO'},
  'locating':  {'en': 'LOCATING',   'fr': 'LOCALISATION','es': 'LOCALIZANDO'},
  'checking':  {'en': 'CHECKING…',  'fr': 'VÉRIF…',      'es': 'VERIF…'},
  'switching': {'en': 'SWITCHING…', 'fr': 'CHANGEMENT…', 'es': 'CAMBIANDO…'},
  'stopped':   {'en': 'STOPPED',    'fr': 'ARRÊTÉ',      'es': 'DETENIDO'},
  'error':     {'en': 'ERROR',      'fr': 'ERREUR',      'es': 'ERROR'},
  'ping':      {'en': 'PING',       'fr': 'PING',        'es': 'PING'},
  'download':  {'en': 'DOWNLOAD',   'fr': 'TÉLÉCH.',     'es': 'DESCARGA'},
  'upload':    {'en': 'UPLOAD',     'fr': 'ENVOI',       'es': 'SUBIDA'},

  'dlLabel': {'en': '↓ DOWNLOAD', 'fr': '↓ TÉLÉCH.', 'es': '↓ DESCARGA'},
  'ulLabel': {'en': '↑ UPLOAD',   'fr': '↑ ENVOI',   'es': '↑ SUBIDA'},

  'down':   {'en': 'DOWN',   'fr': 'BAS',   'es': 'BAJADA'},
  'up':     {'en': 'UP',     'fr': 'HAUT',  'es': 'SUBIDA'},
  'jitter': {'en': 'JITTER', 'fr': 'GIGUE', 'es': 'JITTER'},

  'detecting': {'en': 'Detecting…',  'fr': 'Détection…',   'es': 'Detectando…'},
  'unknown':   {'en': 'Unknown',      'fr': 'Inconnu',      'es': 'Desconocido'},
  'duration':  {'en': 'Duration:',   'fr': 'Durée :',      'es': 'Duración:'},

  'startTest': {'en': 'START TEST', 'fr': 'DÉMARRER',   'es': 'INICIAR TEST'},
  'stop':      {'en': 'STOP',       'fr': 'ARRÊTER',    'es': 'PARAR'},

  'selectServer':    {'en': 'Select server',   'fr': 'Choisir le serveur', 'es': 'Elegir servidor'},
  'autoFallback':    {'en': 'Auto-fallback',   'fr': 'Repli auto',         'es': 'Auto-cambio'},
  'autoFallbackSub': {
    'en': 'Automatically try the next server if the current one fails',
    'fr': 'Essaie automatiquement le serveur suivant en cas d\'échec',
    'es': 'Intenta el siguiente servidor automáticamente si falla',
  },

  'webBanner': {
    'en': 'Browser mode — only Cloudflare servers available.',
    'fr': 'Mode navigateur — serveurs Cloudflare uniquement.',
    'es': 'Modo navegador — solo servidores Cloudflare.',
  },

  'metricsLogs': {'en': 'METRICS LOGS', 'fr': 'HISTORIQUE',  'es': 'REGISTROS'},
  'clearAll':    {'en': 'Clear all',    'fr': 'Tout effacer', 'es': 'Borrar todo'},
  'noTests':     {'en': 'No tests yet', 'fr': 'Aucun test',   'es': 'Sin pruebas'},
  'noTestsHint': {
    'en': 'Run a speed test to see your results here.',
    'fr': 'Lancez un test pour voir vos résultats ici.',
    'es': 'Haz un test de velocidad para ver tus resultados.',
  },
  'clearHistory':     {'en': 'Clear history',       'fr': 'Effacer l\'historique', 'es': 'Borrar historial'},
  'clearHistoryBody': {
    'en': 'Delete all test results? This cannot be undone.',
    'fr': 'Supprimer tous les résultats ? Irréversible.',
    'es': '¿Eliminar todos los resultados? No se puede deshacer.',
  },
  'cancel':    {'en': 'Cancel',     'fr': 'Annuler',       'es': 'Cancelar'},
  'deleteAll': {'en': 'Delete all', 'fr': 'Tout supprimer','es': 'Eliminar todo'},
  'unknownLoc':{'en': '📍 Unknown', 'fr': '📍 Inconnu',   'es': '📍 Desconocido'},

  'grade_excellent': {'en': 'EXCELLENT', 'fr': 'EXCELLENT', 'es': 'EXCELENTE'},
  'grade_veryGood':  {'en': 'VERY GOOD', 'fr': 'TRÈS BON',  'es': 'MUY BUENO'},
  'grade_good':      {'en': 'GOOD',      'fr': 'BON',       'es': 'BUENO'},
  'grade_fair':      {'en': 'FAIR',      'fr': 'MOYEN',     'es': 'REGULAR'},
  'grade_slow':      {'en': 'SLOW',      'fr': 'LENT',      'es': 'LENTO'},
  'grade_poor':      {'en': 'VERY SLOW', 'fr': 'TRÈS LENT', 'es': 'MUY LENTO'},

  'settings':    {'en': 'SETTINGS',     'fr': 'PARAMÈTRES',  'es': 'AJUSTES'},
  'sLocation':   {'en': 'LOCATION',     'fr': 'LOCALISATION','es': 'UBICACIÓN'},
  'sAppearance': {'en': 'APPEARANCE',   'fr': 'APPARENCE',   'es': 'APARIENCIA'},
  'sServer':     {'en': 'TEST SERVER',  'fr': 'SERVEUR',     'es': 'SERVIDOR'},
  'sDuration':   {'en': 'TEST DURATION','fr': 'DURÉE',       'es': 'DURACIÓN'},
  'sUnit':       {'en': 'UNIT',         'fr': 'UNITÉ',       'es': 'UNIDAD'},
  'sHistory':    {'en': 'HISTORY',      'fr': 'HISTORIQUE',  'es': 'HISTORIAL'},
  'sLanguage':   {'en': 'LANGUAGE',     'fr': 'LANGUE',      'es': 'IDIOMA'},

  'gpsLocation':  {'en': 'GPS location', 'fr': 'Localisation GPS', 'es': 'Ubicación GPS'},
  'gpsSubtitle':  {
    'en': 'Use device sensor for your city name',
    'fr': 'Utiliser le capteur pour le nom de la ville',
    'es': 'Usar el sensor para el nombre de la ciudad',
  },
  'detectingGps': {'en': 'Detecting GPS location…','fr': 'Détection GPS…', 'es': 'Detectando GPS…'},
  'notDetected':  {'en': 'Not detected — tap to try','fr': 'Non détecté — appuyer','es': 'No detectado — toca'},
  'refreshGps':   {'en': 'Refresh GPS',  'fr': 'Rafraîchir GPS',  'es': 'Actualizar GPS'},
  'gpsUnavail':   {
    'en': 'GPS unavailable — check location permissions.',
    'fr': 'GPS indisponible — vérifier les permissions.',
    'es': 'GPS no disponible — verifica los permisos.',
  },
  'ipLocation':    {'en': 'IP-based location','fr': 'Localisation IP',  'es': 'Ubicación por IP'},
  'notDetectedIP': {'en': 'Not detected',     'fr': 'Non détecté',      'es': 'No detectado'},
  'refreshIp':     {'en': 'Refresh IP',       'fr': 'Rafraîchir IP',    'es': 'Actualizar IP'},

  'theme':          {'en': 'Theme',         'fr': 'Thème',            'es': 'Tema'},
  'system':         {'en': 'System',        'fr': 'Système',          'es': 'Sistema'},
  'light':          {'en': 'Light',         'fr': 'Clair',            'es': 'Claro'},
  'dark':           {'en': 'Dark',          'fr': 'Sombre',           'es': 'Oscuro'},
  'dynamicColor':   {'en': 'Dynamic color', 'fr': 'Couleur dynamique','es': 'Color dinámico'},
  'dynamicColorSub':{'en': 'Follows your wallpaper colors (Android 12+)',
                     'fr': 'Suit les couleurs du fond d\'écran (Android 12+)',
                     'es': 'Sigue los colores del fondo (Android 12+)'},
  'accentColor':    {'en': 'Accent color',  'fr': 'Couleur d\'accentuation','es': 'Color de acento'},

  'durationPerTest': {'en': 'Duration per test','fr': 'Durée par test',     'es': 'Duración por prueba'},
  'runsUntilStop':   {'en': 'Runs until you press STOP  (max 10 min)',
                      'fr': 'Jusqu\'à STOP  (max 10 min)',
                      'es': 'Hasta STOP  (máx 10 min)'},

  'speedUnit':    {'en': 'Speed unit',   'fr': 'Unité de vitesse', 'es': 'Unidad de velocidad'},
  'speedUnitSub': {
    'en': 'Mb/s = megabits  ·  MB/s = megabytes  ·  Gb/s = gigabits  ·  GB/s = gigabytes',
    'fr': 'Mb/s = mégabits  ·  Mo/s = mégaoctets  ·  Gb/s = gigabits  ·  Go/s = gigaoctets',
    'es': 'Mb/s = megabits  ·  MB/s = megabytes  ·  Gb/s = gigabits  ·  GB/s = gigabytes',
  },

  'autoSave':    {'en': 'Auto-save results',                   'fr': 'Sauvegarde auto',              'es': 'Guardado automático'},
  'autoSaveSub': {'en': 'Automatically add each test to logs', 'fr': 'Ajouter chaque test aux journaux','es': 'Añadir cada prueba'},

  'clearLogs':      {'en': 'Clear all logs',                      'fr': 'Effacer tous les journaux','es': 'Borrar registros'},
  'clearLogsSub':   {'en': 'Permanently delete all saved results', 'fr': 'Supprimer définitivement', 'es': 'Eliminar permanentemente'},
  'clearLogsTitle': {'en': 'Clear logs',                          'fr': 'Effacer les journaux',     'es': 'Borrar registros'},
  'clearLogsBody':  {'en': 'Delete all results? This cannot be undone.',
                     'fr': 'Supprimer tous les résultats ? Irréversible.',
                     'es': '¿Eliminar todos los resultados? No se puede deshacer.'},
  'delete': {'en': 'Delete', 'fr': 'Supprimer', 'es': 'Eliminar'},

  'exportCsv':    {'en': 'Export CSV',                 'fr': 'Exporter CSV',                     'es': 'Exportar CSV'},
  'exportCsvSub': {'en': 'Copy all results to clipboard as CSV',
                   'fr': 'Copier les résultats dans le presse-papiers',
                   'es': 'Copiar resultados al portapapeles como CSV'},
  'exportCopied': {'en': 'Copied to clipboard!', 'fr': 'Copié !',         'es': '¡Copiado!'},
  'exportEmpty':  {'en': 'No data to export',    'fr': 'Aucune donnée',   'es': 'Sin datos'},

  'testDetail': {'en': 'TEST DETAIL',  'fr': 'DÉTAIL DU TEST', 'es': 'DETALLE'},
  'trend':      {'en': 'TREND',        'fr': 'TENDANCE',       'es': 'TENDENCIA'},
  'vsAverage':  {'en': 'VS. AVERAGE',  'fr': 'VS MOYENNE',     'es': 'VS PROMEDIO'},
  'server':     {'en': 'Server',       'fr': 'Serveur',        'es': 'Servidor'},
  'location':   {'en': 'Location',     'fr': 'Localisation',   'es': 'Ubicación'},

  // Dual duration
  'dlDuration':     {'en': '↓  DL',       'fr': '↓  Téléch.',    'es': '↓  Descarga'},
  'ulDuration':     {'en': '↑  UL',       'fr': '↑  Envoi',      'es': '↑  Subida'},
  'linked':         {'en': 'Linked',      'fr': 'Lié',           'es': 'Enlazado'},
  'custom':         {'en': 'Custom',      'fr': 'Personnalisé',  'es': 'Personal.'},

  // Map tab
  'mapTitle':     {'en': 'TEST LOCATIONS', 'fr': 'CARTE DES TESTS', 'es': 'UBICACIONES'},
  'mapNoGps':     {
    'en': 'No GPS data yet.\nEnable GPS location and run a test.',
    'fr': 'Aucune donnée GPS.\nActivez la localisation GPS et lancez un test.',
    'es': 'Sin datos GPS.\nActiva la ubicación GPS y haz un test.',
  },
  'mapTests':     {'en': '{n} test(s) at this location', 'fr': '{n} test(s) ici', 'es': '{n} prueba(s) aquí'},
  'mapLocation':  {'en': 'Location on map',  'fr': 'Emplacement',   'es': 'Ubicación en mapa'},
  'noGpsEntry':   {'en': 'No GPS coords for this test', 'fr': 'Pas de GPS pour ce test', 'es': 'Sin GPS para esta prueba'},
  'osmCredit':    {'en': '© OpenStreetMap contributors', 'fr': '© Contributeurs OpenStreetMap', 'es': '© Contribuidores OpenStreetMap'},

  'footer': {'en': 'Jitter v1.0.0  ·  Made with Flutter', 'fr': 'Jitter v1.0.0  ·  Fait avec Flutter', 'es': 'Jitter v1.0.0  ·  Hecho con Flutter'},
};

extension AppL10n on BuildContext {
  String tr(String key) {
    final lang = Localizations.localeOf(this).languageCode;
    return _t[key]?[lang] ?? _t[key]?['en'] ?? key;
  }
  String trN(String key, int n) => tr(key).replaceAll('{n}', '$n');
}

String phaseLabel(String phase, BuildContext ctx) {
  switch (phase) {
    case 'READY':      return ctx.tr('ready');
    case 'DONE':       return ctx.tr('done');
    case 'LOCATING':   return ctx.tr('locating');
    case 'CHECKING…':  return ctx.tr('checking');
    case 'SWITCHING…': return ctx.tr('switching');
    case 'STOPPED':    return ctx.tr('stopped');
    case 'ERROR':      return ctx.tr('error');
    case 'PING':       return ctx.tr('ping');
    case 'DOWNLOAD':   return ctx.tr('download');
    case 'UPLOAD':     return ctx.tr('upload');
    default:           return phase;
  }
}