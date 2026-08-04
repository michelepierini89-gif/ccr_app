package com.ccr.ccr_app

import android.content.Intent
import android.location.GnssStatus
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val batteryChannel = "ccr/battery"
    private val gnssEventChannel = "ccr/gnss_status"

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
