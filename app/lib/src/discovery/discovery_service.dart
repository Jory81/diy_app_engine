import 'dart:async';

import '../net/info_client.dart';
import '../net/network_binding.dart';
import 'concurrency.dart';
import 'mdns_browser.dart';
import 'merge.dart';
import 'subnet.dart';

/// Default address of an ESP32 soft-AP.
const softApAddress = '192.168.4.1';

/// Finds devices with three methods running in parallel:
///
/// 1. mDNS browse of `_espdevice._tcp`,
/// 2. direct `/info` probes of 192.168.4.1, the Wi-Fi gateway and any
///    [knownHosts] (saved devices),
/// 3. a sweep of the phone's /24 network as a fallback.
///
/// Results are de-duplicated by device id while streaming.
class DiscoveryService {
  DiscoveryService({
    required this.infoClient,
    required this.network,
    MdnsBrowser? mdns,
    this.extraHosts = const [],
  }) : mdns = mdns ?? MdnsBrowser();

  final InfoClient infoClient;
  final NetworkBinding network;
  final MdnsBrowser mdns;

  /// Hosts always probed (used by the demo build).
  final List<String> extraHosts;

  static const sweepTimeout = Duration(milliseconds: 700);
  static const sweepConcurrency = 32;
  static const mdnsDuration = Duration(seconds: 5);

  /// Upper limit for a whole scan, so a stuck lookup never spins forever.
  static const scanTimeout = Duration(seconds: 30);

  Stream<Discovered> discover({Iterable<String> knownHosts = const []}) {
    final controller = StreamController<Discovered>();
    final seenIds = <String>{};

    void emit(Discovered d) {
      if (!controller.isClosed && seenIds.add(d.info.id)) controller.add(d);
    }

    Future<void> probe(String host, Duration timeout) async {
      final info = await infoClient.fetch(host, timeout: timeout);
      if (info != null) emit(Discovered(info, host));
    }

    () async {
      await network.bindToWifi();
      final wifi = await network.wifiDetails();
      final direct = {
        softApAddress,
        ?wifi?.gateway,
        ...knownHosts,
        ...extraHosts,
      };
      final sweep = wifi?.ip == null
          ? const <String>[]
          : subnetHosts(wifi!.ip!, exclude: direct);

      try {
        await Future.wait([
          _browseMdns(emit),
          Future.wait(direct.map((h) => probe(h, const Duration(seconds: 2)))),
          forEachLimited(
            sweep,
            sweepConcurrency,
            (h) => probe(h, sweepTimeout),
          ),
        ]).timeout(scanTimeout);
      } on TimeoutException {
        // keep what was found so far
      }
      await controller.close();
    }();
    return controller.stream;
  }

  Future<void> _browseMdns(void Function(Discovered) emit) async {
    await for (final hit in mdns.browse(mdnsDuration)) {
      // Prefer the live /info answer (it has the mode); fall back to TXT.
      final info = await infoClient.fetch(hit.host);
      emit(info == null ? hit : Discovered(info, hit.host));
    }
  }
}
