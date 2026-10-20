import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The phone's current Wi-Fi network as reported by Android.
class WifiDetails {
  const WifiDetails({
    this.ip,
    this.prefixLength,
    this.gateway,
    this.hasInternet = false,
    this.bound = false,
  });

  factory WifiDetails.fromMap(Map<Object?, Object?> map) => WifiDetails(
    ip: map['ip'] as String?,
    prefixLength: map['prefixLength'] as int?,
    gateway: map['gateway'] as String?,
    hasInternet: map['hasInternet'] == true,
    bound: map['bound'] == true,
  );

  final String? ip;
  final int? prefixLength;
  final String? gateway;

  /// Whether Android validated internet access on this Wi-Fi.
  final bool hasInternet;

  /// Whether the app process is bound to this Wi-Fi network.
  final bool bound;
}

/// Talks to the Kotlin side (`MainActivity`) that binds the app process to
/// the Wi-Fi network. Without it, Android sends traffic over mobile data
/// when the Wi-Fi (the ESP32 soft-AP) has no internet, and 192.168.4.1
/// becomes unreachable.
class NetworkBinding {
  static const _channel = MethodChannel('esp_device_hub/network');

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Current Wi-Fi details, or null when not on Wi-Fi / not supported.
  Future<WifiDetails?> wifiDetails() async {
    if (!isSupported) return null;
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>(
        'getWifiInfo',
      );
      if (map == null || map['connected'] != true) return null;
      return WifiDetails.fromMap(map);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Binds all app traffic (Dart sockets and the WebView) to Wi-Fi.
  /// The Kotlin side also does this automatically whenever Wi-Fi appears.
  Future<bool> bindToWifi() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('bindToWifi') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
