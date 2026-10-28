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
 * Behaviour: the process is only bound while the Wi-Fi has NO internet (the
 * soft-AP case). A Wi-Fi with internet is already Android's default network,
 * so the app then connects like any other app (and like the browser); binding
 * there only adds risk, e.g. picking the wrong network object while switching
 * networks or with a VPN, which made every request fail. The decision is made
 * again whenever a Wi-Fi appears, disappears or gets/loses internet.
 * External apps (e.g. "open in browser") are not affected.
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
            bindToWifi()
        }

        // e.g. a Wi-Fi that turns out to have internet a few seconds after connecting
        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
            bindToWifi()
        }

        override fun onLost(network: Network) {
            if (network == boundNetwork) {
                unbind()
            }
            bindToWifi()
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

    /**
     * Binds to the current Wi-Fi when it has no internet (soft-AP), otherwise
     * makes sure the process is not bound. Returns true when the device
     * network is reachable: bound to an offline Wi-Fi, or using the default
     * network because the Wi-Fi has internet.
     */
    fun bindToWifi(): Boolean {
        val network = findWifiNetwork()
        if (network == null) {
            if (boundNetwork != null) unbind()
            return false
        }
        if (hasInternet(network)) {
            if (boundNetwork != null) unbind()
            return true
        }
        if (network == boundNetwork && connectivity.boundNetworkForProcess == network) {
            return true
        }
        return bind(network)
    }

    private fun hasInternet(network: Network): Boolean =
        connectivity.getNetworkCapabilities(network)
            ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true

    fun unbind() {
        connectivity.bindProcessToNetwork(null)
        boundNetwork = null
        Log.i(TAG, "process unbound (default network)")
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

    /** The Wi-Fi network the phone uses now: Android's active one if that is Wi-Fi, else any Wi-Fi. */
    @Suppress("DEPRECATION") // allNetworks: still the simplest synchronous lookup
    private fun findWifiNetwork(): Network? {
        fun isWifi(network: Network): Boolean {
            val caps = connectivity.getNetworkCapabilities(network) ?: return false
            // a VPN running over Wi-Fi also reports TRANSPORT_WIFI; it is not the local network
            return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
                !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        }
        connectivity.activeNetwork?.let { if (isWifi(it)) return it }
        return connectivity.allNetworks.firstOrNull { isWifi(it) }
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
