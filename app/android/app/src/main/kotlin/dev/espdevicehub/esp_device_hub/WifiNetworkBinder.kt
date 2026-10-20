package dev.espdevicehub.esp_device_hub

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.util.Log
import java.net.Inet4Address

/**
 * Keeps the whole app process bound to the Wi-Fi network.
 *
 * Problem: when the phone joins a Wi-Fi without internet (the ESP32 soft-AP
 * "ESP32-AP") while mobile data is on, Android keeps mobile data as the
 * default network. Sockets of the app then go out over mobile data and
 * 192.168.4.1 is unreachable.
 *
 * Fix: [ConnectivityManager.bindProcessToNetwork] with the Wi-Fi [Network].
 * This covers every socket of the process: Dart's HTTP client, mDNS and the
 * in-app WebView (its network stack runs inside the app process).
 *
 * Behaviour: the binding is kept whenever ANY Wi-Fi is connected, also when
 * that Wi-Fi has internet. The app only talks to devices on the local Wi-Fi,
 * so this is always correct, and it avoids races when switching between the
 * home Wi-Fi and the soft-AP. When the Wi-Fi is lost the process is unbound
 * (so it falls back to the default network) and re-bound as soon as another
 * Wi-Fi appears. External apps (e.g. "open in browser") are not affected.
 */
class WifiNetworkBinder(context: Context) {
    private val connectivity =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val wifiManager =
        context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

    @Volatile
    private var boundNetwork: Network? = null
    private var registered = false

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            bind(network)
        }

        override fun onLost(network: Network) {
            if (network == boundNetwork) {
                unbind()
                findWifiNetwork()?.let { bind(it) }
            }
        }
    }

    fun start() {
        if (registered) return
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            // The soft-AP has no internet: do not require it.
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        try {
            connectivity.registerNetworkCallback(request, callback)
            registered = true
        } catch (e: RuntimeException) {
            Log.w(TAG, "registerNetworkCallback failed", e)
        }
        bindToWifi()
    }

    fun stop() {
        if (registered) {
            try {
                connectivity.unregisterNetworkCallback(callback)
            } catch (e: IllegalArgumentException) {
                Log.w(TAG, "unregisterNetworkCallback failed", e)
            }
            registered = false
        }
        unbind()
    }

    /** Binds to the current Wi-Fi network; returns false if there is none. */
    fun bindToWifi(): Boolean {
        val network = findWifiNetwork() ?: return false
        return bind(network)
    }

    fun unbind() {
        connectivity.bindProcessToNetwork(null)
        boundNetwork = null
    }

    /** Details of the current Wi-Fi network for discovery. */
    fun wifiInfo(): Map<String, Any?> {
        val network = boundNetwork ?: findWifiNetwork()
            ?: return mapOf("connected" to false)
        val link = connectivity.getLinkProperties(network)
        val caps = connectivity.getNetworkCapabilities(network)
        val address = link?.linkAddresses?.firstOrNull { it.address is Inet4Address }
        val gateway = link?.routes
            ?.firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }
            ?.gateway?.hostAddress
            ?: dhcpGateway()
        return mapOf(
            "connected" to true,
            "ip" to address?.address?.hostAddress,
            "prefixLength" to address?.prefixLength,
            "gateway" to gateway,
            "hasInternet" to (caps?.hasCapability(
                NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true),
            "bound" to (connectivity.boundNetworkForProcess == network),
        )
    }

    private fun bind(network: Network): Boolean {
        val ok = connectivity.bindProcessToNetwork(network)
        if (ok) boundNetwork = network
        Log.i(TAG, "bindProcessToNetwork($network) = $ok")
        return ok
    }

    @Suppress("DEPRECATION") // allNetworks: still the simplest synchronous lookup
    private fun findWifiNetwork(): Network? =
        connectivity.allNetworks.firstOrNull { network ->
            connectivity.getNetworkCapabilities(network)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }

    /** Fallback when LinkProperties has no default route (no location needed). */
    @Suppress("DEPRECATION")
    private fun dhcpGateway(): String? {
        val gw = wifiManager.dhcpInfo?.gateway ?: 0
        if (gw == 0) return null
        // DhcpInfo stores the address as a little-endian int.
        return listOf(gw and 0xff, gw shr 8 and 0xff, gw shr 16 and 0xff, gw shr 24 and 0xff)
            .joinToString(".")
    }

    private companion object {
        const val TAG = "WifiNetworkBinder"
    }
}
