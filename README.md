# Jitter

Internet speed test for Android — Kotlin, Jetpack Compose, Material 3 Expressive (Material You).

- Ping, jitter (live, during the test), download and upload with 1–64 parallel connections
- 22 built-in servers (Cloudflare, OVH, Hetzner, Leaseweb, Clouvider) + custom server + auto-fallback
- 6 speed units, separate download/upload durations (5 s … 60 s, custom, ∞)
- History grouped by location, trend view, CSV export/import, per-test comparison to the average
- Map of tests (OpenStreetMap) with GPS positions
- English, Français, Español
- Dynamic color (Android 12+) or 7 accent colors, system/light/dark theme

Build: push to `main` → GitHub Actions produces `Jitter.apk`. Tag `v*` to publish a release.
Local: `./gradlew assembleRelease` (JDK 17).
