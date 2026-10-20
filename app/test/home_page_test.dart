import 'dart:convert';

import 'package:esp_device_hub/main.dart';
import 'package:esp_device_hub/src/device_hub.dart';
import 'package:esp_device_hub/src/discovery/discovery_service.dart';
import 'package:esp_device_hub/src/discovery/mdns_browser.dart';
import 'package:esp_device_hub/src/discovery/merge.dart';
import 'package:esp_device_hub/src/models/device_store.dart';
import 'package:esp_device_hub/src/net/info_client.dart';
import 'package:esp_device_hub/src/net/network_binding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoMdns extends MdnsBrowser {
  @override
  Stream<Discovered> browse(Duration duration) => const Stream.empty();
}

/// No platform channels in widget tests: behave like "not on Wi-Fi".
class _NoNetwork extends NetworkBinding {
  @override
  Future<WifiDetails?> wifiDetails() async => null;

  @override
  Future<bool> bindToWifi() async => false;
}

DeviceHub _hub(Map<String, Map<String, String>> answers) {
  final client = MockClient((request) async {
    final body = answers[request.url.authority];
    return body == null
        ? http.Response('', 404)
        : http.Response(jsonEncode(body), 200);
  });
  final info = InfoClient(client: client);
  final network = _NoNetwork();
  return DeviceHub(
    store: DeviceStore(),
    infoClient: info,
    network: network,
    discovery: DiscoveryService(
      infoClient: info,
      network: network,
      mdns: _NoMdns(),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the empty state when nothing is found', (tester) async {
    await tester.pumpWidget(EspDeviceHubApp(hub: _hub({})));
    await tester.pumpAndSettle();

    expect(find.text('No devices yet'), findsOneWidget);
    expect(
      find.textContaining('ESP32-AP network, then tap Scan'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox()); // stops the poll timer
  });

  testWidgets('lists a device found on the soft-AP', (tester) async {
    final hub = _hub({
      '192.168.4.1': {
        'type': 'bbq',
        'name': 'BBQ controller',
        'id': 'a1b2c3',
        'mode': 'ap',
        'ip': '192.168.4.1',
        'version': '2.0',
      },
    });
    await tester.pumpWidget(EspDeviceHubApp(hub: hub));
    await tester.pumpAndSettle();

    expect(find.text('BBQ controller'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Soft-AP'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
