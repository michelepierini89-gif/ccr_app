package com.ccr.ccr_app

import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.location.GnssStatus
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val batteryChannel = "ccr/battery"
    private val notificationChannelName = "ccr/notification"
    private val gnssEventChannel = "ccr/gnss_status"

    // Notification ID + channel ID del foreground service di geolocator_android
    // (com.baseflow.geolocator.GeolocatorLocationService, hardcoded nel plugin,
    // non esposto via API pubblica) — riusati per aggiornare il testo della
    // notifica persistente senza toccare il ciclo di vita del service: notify()
    // con lo stesso ID sostituisce solo il contenuto visibile.
    private val geolocatorNotificationId = 75415
    private val geolocatorChannelId = "geolocator_channel_01"

    private var gnssCallback: GnssStatus.Callback? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, batteryChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "requestIgnoreBatteryOptimization" -> {
                        val intent = Intent(
                            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(null)
                    }
                    "getManufacturer" -> result.success(Build.MANUFACTURER)
                    "getDeviceModel" -> result.success(Build.MODEL)
                    "isForegroundServiceActive" -> {
                        result.success(isAnyForegroundServiceRunning())
                    }
                    "openBatterySettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "openManufacturerBatterySettings" -> {
                        result.success(openManufacturerBatterySettings())
                    }
                    else -> result.notImplemented()
                }
            }

        // Blocco 5 — contatore punti nella notifica persistente: aggiorna il
        // testo della notifica del foreground service di geolocator (stesso
        // notification ID/channel, vedi commento sopra) così il pilota può
        // verificare dalla lock screen che la registrazione GPS è viva senza
        // aprire l'app.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateForegroundNotification" -> {
                        val text = call.argument<String>("text") ?: ""
                        result.success(updateForegroundNotificationText(text))
                    }
                    else -> result.notImplemented()
                }
            }

        // Blocco C — diagnostica GNSS reale (satelliti usati, C/N0, dual
        // frequency): il campo `accuracy` di FusedLocationProvider è
        // ottimistico sui chip economici (es. MediaTek), GnssStatus espone
        // dati molto più informativi sulla qualità effettiva del fix.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, gnssEventChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    startGnssMonitoring()
                }

                override fun onCancel(arguments: Any?) {
                    stopGnssMonitoring()
                    eventSink = null
                }
            })
    }

    @Suppress("DEPRECATION")
    private fun isAnyForegroundServiceRunning(): Boolean {
        return try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            am.getRunningServices(Integer.MAX_VALUE).any {
                it.service.packageName == packageName && it.foreground
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun updateForegroundNotificationText(text: String): Boolean {
        return try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Idempotente: se il canale esiste già (creato dal foreground
                // service di geolocator) questa chiamata non lo altera.
                val channel = NotificationChannel(
                    geolocatorChannelId,
                    "Geolocator background service",
                    NotificationManager.IMPORTANCE_LOW
                )
                nm.createNotificationChannel(channel)
            }
            val notification: Notification = NotificationCompat.Builder(this, geolocatorChannelId)
                .setContentTitle("Registrazione GPS")
                .setContentText(text)
                .setOngoing(true)
                .setSmallIcon(applicationInfo.icon)
                .build()
            nm.notify(geolocatorNotificationId, notification)
            true
        } catch (e: Exception) {
            false
        }
    }

    // Percorsi noti (non ufficiali, pubblicati da progetti open-source come
    // riferimento) per le schermate di risparmio energetico/autostart
    // proprietarie dei produttori più aggressivi. Non garantiti su tutte le
    // versioni ROM: ogni componente viene provato in ordine, il primo che
    // risolve viene aperto; se nessuno esiste si ricade sulle impostazioni
    // app generiche.
    private fun manufacturerComponents(manufacturer: String): List<ComponentName> {
        val m = manufacturer.lowercase()
        return when {
            m.contains("xiaomi") -> listOf(
                ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"
                ),
                ComponentName(
                    "com.miui.powerkeeper",
                    "com.miui.powerkeeper.ui.HiddenAppsConfigActivity"
                ),
            )
            m.contains("oppo") -> listOf(
                ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                ),
                ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.startupapp.StartupAppListActivity"
                ),
                ComponentName(
                    "com.oppo.safe",
                    "com.oppo.safe.permission.startup.StartupAppListActivity"
                ),
            )
            m.contains("realme") -> listOf(
                ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                ),
                ComponentName(
                    "com.oplus.securitycenter",
                    "com.oplus.securitycenter.startupapp.StartupAppListActivity"
                ),
            )
            m.contains("vivo") -> listOf(
                ComponentName(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                ),
                ComponentName(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"
                ),
            )
            m.contains("huawei") || m.contains("honor") -> listOf(
                ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                ),
                ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity"
                ),
            )
            m.contains("oneplus") -> listOf(
                ComponentName(
                    "com.oneplus.security",
                    "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"
                ),
            )
            m.contains("samsung") -> listOf(
                ComponentName(
                    "com.samsung.android.lool",
                    "com.samsung.android.sm.ui.battery.BatteryActivity"
                ),
            )
            // Oukitel e altri MediaTek "generici" non hanno una schermata
            // proprietaria nota: nessun componente, si ricade sempre sul
            // fallback delle impostazioni app.
            else -> emptyList()
        }
    }

    private fun openManufacturerBatterySettings(): Boolean {
        for (component in manufacturerComponents(Build.MANUFACTURER)) {
            try {
                val intent = Intent().apply {
                    setComponent(component)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                return true
            } catch (e: Exception) {
                // Componente non presente su questa ROM: prova il prossimo.
                continue
            }
        }
        return try {
            val intent = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun startGnssMonitoring() {
        // GnssStatus.Callback esiste da API 24; il resto del canale (satelliti
        // usati/visibili, C/N0) è disponibile solo da lì in su.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        if (gnssCallback != null) return

        val locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        val callback = object : GnssStatus.Callback() {
            override fun onSatelliteStatusChanged(status: GnssStatus) {
                val satCount = status.satelliteCount
                var usedCount = 0
                var cn0Sum = 0.0
                var cn0UsedCount = 0
                var hasDualFrequency = false
                val constellations = mutableSetOf<String>()

                for (i in 0 until satCount) {
                    if (!status.usedInFix(i)) continue
                    usedCount++
                    cn0Sum += status.getCn0DbHz(i)
                    cn0UsedCount++
                    constellations.add(constellationName(status.getConstellationType(i)))

                    // Dual-frequency (L5/E5a, banda attorno 1176.45 MHz) vs
                    // L1/E1 (banda attorno 1575.42/1602 MHz): disponibile
                    // solo da API 26 (hasCarrierFrequencyHz).
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        status.hasCarrierFrequencyHz(i)
                    ) {
                        val freqMhz = status.getCarrierFrequencyHz(i) / 1_000_000.0
                        if (freqMhz in 1150.0..1300.0) hasDualFrequency = true
                    }
                }

                val avgCn0 = if (cn0UsedCount > 0) cn0Sum / cn0UsedCount else 0.0

                val data = HashMap<String, Any>()
                data["satellitesVisible"] = satCount
                data["satellitesUsed"] = usedCount
                data["avgCn0"] = avgCn0
                data["constellations"] = constellations.toList()
                data["hasDualFrequency"] = hasDualFrequency

                mainHandler.post { eventSink?.success(data) }
            }
        }
        gnssCallback = callback
        locationManager.registerGnssStatusCallback(callback, mainHandler)
    }

    private fun stopGnssMonitoring() {
        val callback = gnssCallback ?: return
        val locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        locationManager.unregisterGnssStatusCallback(callback)
        gnssCallback = null
    }

    private fun constellationName(type: Int): String = when (type) {
        GnssStatus.CONSTELLATION_GPS -> "GPS"
        GnssStatus.CONSTELLATION_GLONASS -> "GLONASS"
        GnssStatus.CONSTELLATION_GALILEO -> "GALILEO"
        GnssStatus.CONSTELLATION_BEIDOU -> "BEIDOU"
        GnssStatus.CONSTELLATION_QZSS -> "QZSS"
        GnssStatus.CONSTELLATION_SBAS -> "SBAS"
        GnssStatus.CONSTELLATION_IRNSS -> "IRNSS"
        else -> "UNKNOWN"
    }

    override fun onDestroy() {
        stopGnssMonitoring()
        super.onDestroy()
    }
}
