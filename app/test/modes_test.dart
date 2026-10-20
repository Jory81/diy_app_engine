import 'dart:convert';

import 'package:esp_device_hub/src/device_hub.dart';
import 'package:esp_device_hub/src/discovery/discovery_service.dart';
import 'package:esp_device_hub/src/discovery/mdns_browser.dart';
import 'package:esp_device_hub/src/discovery/merge.dart';
import 'package:esp_device_hub/src/models/device.dart';
import 'package:esp_device_hub/src/models/device_info.dart';
import 'package:esp_device_hub/src/models/device_store.dart';
import 'package:esp_device_hub/src/net/info_client.dart';
import 'package:esp_device_hub/src/net/network_binding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoNetwork extends NetworkBinding {
  @override
  Future<WifiDetails?> wifiDetails() async => null;

  @override
  Future<bool> bindToWifi() async => false;
}

class _NoMdns extends MdnsBrowser {
  @override
  Stream<Discovered> browse(Duration duration) => const Stream.empty();
}

void main() {
  group('modes parsing', () {
    test('/info with modes', () {
      final info = DeviceInfo.tryParse(
        '{"type":"bbq","id":"a1b2c3","modes":["bbq","Greenhouse"," "]}',
      )!;
      expect(info.modes, ['bbq', 'greenhouse']);
      expect(info.canSwitchMode, isTrue);
    });

    test('single-mode firmware has no modes', () {
      expect(DeviceInfo.tryParse('{"id":"a1b2c3"}')!.modes, isEmpty);
      final one = DeviceInfo.tryParse('{"id":"x","modes":["bbq","bbq"]}')!;
      expect(one.modes, ['bbq']);
      expect(one.canSwitchMode, isFalse);
      final bad = DeviceInfo.tryParse('{"id":"x","modes":"bbq"}')!;
      expect(bad.modes, isEmpty);
    });

    test('/mode answers', () {
      final status = ModeStatus.tryParse(
        '{"mode":"greenhouse","modes":["bbq","greenhouse"],"restarting":true}',
      )!;
      expect(status.mode, 'greenhouse');
      expect(status.modes, ['bbq', 'greenhouse']);
      expect(status.restarting, isTrue);
      expect(ModeStatus.tryParse('{"mode":"bbq"}')!.restarting, isFalse);
      expect(ModeStatus.tryParse('{"modes":[]}'), isNull);
      expect(ModeStatus.tryParse('oops'), isNull);
    });

    test('modes survive the saved-device JSON round trip', () {
      const info = DeviceInfo(
        id: 'a1b2c3',
        type: 'bbq',
        name: 'BBQ',
        modes: ['bbq', 'greenhouse'],
      );
      final device = Device.fromInfo(info, '192.168.1.23', DateTime(2026));
      expect(Device.fromJson(device.toJson())!.modes, ['bbq', 'greenhouse']);
    });

    test('new mode keeps the saved entry (same id) and custom name', () {
      const bbq = DeviceInfo(id: 'a1b2c3', type: 'bbq', name: 'BBQ');
      const gh = DeviceInfo(id: 'a1b2c3', type: 'greenhouse', name: 'GH');
      final saved = [
        Device.fromInfo(bbq, 'h', DateTime(2026)).copyWith(customName: 'Mine'),
      ];
      final list = mergeDiscovered(
        saved,
        const Discovered(gh, 'h'),
        DateTime(2026),
      );
      expect(list, hasLength(1));
      expect(list.single.type, 'greenhouse');
      expect(list.single.displayName, 'Mine');
    });
  });

  group('DeviceHub.switchMode', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    DeviceHub hubFor(MockClient client) {
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
        modePollInterval: const Duration(milliseconds: 5),
        modeSwitchTimeout: const Duration(milliseconds: 200),
      );
    }

    Map<String, Object> infoJson(String type) => {
      'type': type,
      'id': 'a1b2c3',
      'name': type,
      'mode': 'sta',
      'modes': ['bbq', 'greenhouse'],
    };

    test('posts the mode and waits for the new type', () async {
      var active = 'bbq';
      var restartPolls = 0;
      String? postedBody;
      final hub = hubFor(
        MockClient((request) async {
          if (request.url.authority != 'dev') return http.Response('', 404);
          if (request.method == 'POST' && request.url.path == '/mode') {
            postedBody = request.body;
            active = request.bodyFields['set']!;
            restartPolls = 3; // offline for a few polls while rebooting
            return http.Response(
              jsonEncode({
                'mode': active,
                'modes': ['bbq', 'greenhouse'],
                'restarting': true,
              }),
              200,
            );
          }
          if (restartPolls > 0) {
            restartPolls--;
            throw http.ClientException('connection refused');
          }
          return http.Response(jsonEncode(infoJson(active)), 200);
        }),
      );
      await hub.load();
      final device = await hub.addManual(
        Device.manual(host: 'dev', type: 'bbq'),
      );
      expect(device.canSwitchMode, isTrue);

      final outcome = await hub.switchMode(device, 'greenhouse');

      expect(outcome, SwitchOutcome.switched);
      expect(postedBody, 'set=greenhouse');
      expect(hub.devices.single.type, 'greenhouse');
      expect(hub.devices.single.key, 'a1b2c3');
      expect(hub.isSwitching(hub.devices.single), isFalse);
    });

    test('reports failure when the device rejects the switch', () async {
      final hub = hubFor(
        MockClient((request) async {
          if (request.method == 'POST') return http.Response('bad mode', 400);
          return http.Response(jsonEncode(infoJson('bbq')), 200);
        }),
      );
      await hub.load();
      final device = await hub.addManual(
        Device.manual(host: 'dev', type: 'bbq'),
      );
      expect(await hub.switchMode(device, 'greenhouse'), SwitchOutcome.failed);
      expect(hub.devices.single.type, 'bbq');
    });

    test('falls back to re-discovery when the type never changes', () async {
      final hub = hubFor(
        MockClient((request) async {
          if (request.method == 'POST') {
            return http.Response(
              '{"mode":"greenhouse","restarting":true}',
              200,
            );
          }
          return http.Response(jsonEncode(infoJson('bbq')), 200);
        }),
      );
      await hub.load();
      final device = await hub.addManual(
        Device.manual(host: 'dev', type: 'bbq'),
      );
      expect(
        await hub.switchMode(device, 'greenhouse'),
        SwitchOutcome.notConfirmed,
      );
    });
  });
}
