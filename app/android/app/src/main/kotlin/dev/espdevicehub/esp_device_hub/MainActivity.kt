package dev.espdevicehub.esp_device_hub

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var wifiBinder: WifiNetworkBinder? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val binder = WifiNetworkBinder(applicationContext).also { it.start() }
        wifiBinder = binder

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getWifiInfo" -> result.success(binder.wifiInfo())
                    "bindToWifi" -> result.success(binder.bindToWifi())
                    "unbind" -> {
                        binder.unbind()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        wifiBinder?.stop()
        wifiBinder = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private companion object {
        const val CHANNEL = "esp_device_hub/network"
    }
}
