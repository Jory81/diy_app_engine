import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;

import '../models/device_info.dart';
import 'merge.dart';

/// mDNS service type announced by every device firmware.
const espServiceType = '_espdevice._tcp';

/// Browses `_espdevice._tcp` with Android's NsdManager (via package `nsd`).
///
/// NsdManager is the system mDNS stack, which is more reliable on Android
/// than raw multicast sockets; the `nsd` plugin also takes the Wi-Fi
/// multicast lock while browsing (needs CHANGE_WIFI_MULTICAST_STATE).
class MdnsBrowser {
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Emits every resolved service seen within [duration].
  Stream<Discovered> browse(Duration duration) {
    final controller = StreamController<Discovered>();
    if (!isSupported) {
      controller.close();
      return controller.stream;
    }

    () async {
      nsd.Discovery? discovery;
      try {
        discovery = await nsd.startDiscovery(espServiceType);
        discovery.addServiceListener((service, status) {
          if (status != nsd.ServiceStatus.found) return;
          final found = discoveredFromService(service);
          if (found != null && !controller.isClosed) controller.add(found);
        });
        await Future<void>.delayed(duration);
      } on Object catch (e) {
        debugPrint('mDNS browse failed: $e');
      } finally {
        if (discovery != null) {
          await nsd.stopDiscovery(discovery).catchError((Object _) {});
        }
        await controller.close();
      }
    }();
    return controller.stream;
  }

  /// Converts a resolved service into a device (from its TXT records).
  @visibleForTesting
  static Discovered? discoveredFromService(nsd.Service service) {
    final ip = service.addresses
        ?.where((a) => a.rawAddress.length == 4)
        .map((a) => a.address)
        .firstOrNull;
    if (ip == null) return null;
    final port = service.port ?? 80;
    final txt = {
      for (final entry in (service.txt ?? const {}).entries)
        if (entry.value != null)
          entry.key: utf8.decode(entry.value!, allowMalformed: true),
    };
    final info = DeviceInfo.fromTxt(txt, ip: ip);
    if (info == null) return null;
    return Discovered(info, port == 80 ? ip : '$ip:$port');
  }
}
