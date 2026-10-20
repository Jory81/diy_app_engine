import 'dart:convert';

import 'package:esp_device_hub/src/discovery/discovery_service.dart';
import 'package:esp_device_hub/src/discovery/mdns_browser.dart';
import 'package:esp_device_hub/src/discovery/merge.dart';
import 'package:esp_device_hub/src/models/device_info.dart';
import 'package:esp_device_hub/src/net/info_client.dart';
import 'package:esp_device_hub/src/net/network_binding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeNetwork extends NetworkBinding {
  @override
  Future<WifiDetails?> wifiDetails() async =>
      const WifiDetails(ip: '10.0.0.5', prefixLength: 24, gateway: '10.0.0.1');

  @override
  Future<bool> bindToWifi() async => true;
}

class _FakeMdns extends MdnsBrowser {
  @override
  Stream<Discovered> browse(Duration duration) => Stream.value(
    const Discovered(
      DeviceInfo(id: 'a1b2c3', type: 'bbq', name: 'BBQ'),
      '10.0.0.9',
    ),
  );
}

void main() {
  test('runs all methods and de-duplicates by id', () async {
    final probed = <String>{};
    final client = MockClient((request) async {
      probed.add(request.url.authority);
      final body = switch (request.url.authority) {
        '192.168.4.1' || '10.0.0.9' => {
          'type': 'bbq',
          'id': 'a1b2c3',
          'name': 'BBQ',
          'mode': 'ap',
        },
        '10.0.0.77' => {
          'type': 'greenhouse',
          'id': 'd4e5f6',
          'name': 'GH',
          'mode': 'sta',
        },
        _ => null,
      };
      return body == null
          ? http.Response('not found', 404)
          : http.Response(jsonEncode(body), 200);
    });
    final service = DiscoveryService(
      infoClient: InfoClient(client: client),
      network: _FakeNetwork(),
      mdns: _FakeMdns(),
    );

    final found = await service.discover(knownHosts: ['saved.local']).toList();

    expect(found.map((d) => d.info.id).toSet(), {'a1b2c3', 'd4e5f6'});
    expect(found, hasLength(2));
    expect(probed, containsAll(['192.168.4.1', '10.0.0.1', 'saved.local']));
    expect(probed, contains('10.0.0.254')); // subnet sweep
    expect(probed, isNot(contains('10.0.0.5'))); // not the phone itself
  });
}
