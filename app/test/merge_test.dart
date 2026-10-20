import 'package:esp_device_hub/src/discovery/merge.dart';
import 'package:esp_device_hub/src/models/device.dart';
import 'package:esp_device_hub/src/models/device_info.dart';
import 'package:flutter_test/flutter_test.dart';

const bbq = DeviceInfo(
  id: 'a1b2c3',
  type: 'bbq',
  name: 'BBQ controller',
  mode: DeviceMode.sta,
  ip: '192.168.1.23',
);

void main() {
  final now = DateTime(2026, 10, 20, 12);

  group('dedupeById', () {
    test('keeps the first answer per id', () {
      final result = dedupeById([
        const Discovered(bbq, '192.168.1.23'),
        const Discovered(
          DeviceInfo(id: 'd4e5f6', type: 'greenhouse', name: 'GH'),
          'gh',
        ),
        const Discovered(bbq, 'bbq-a1b2c3.local'),
      ]);
      expect(result.map((d) => d.host), ['192.168.1.23', 'gh']);
    });
  });

  group('mergeDiscovered', () {
    test('adds a new device', () {
      final list = mergeDiscovered(
        [],
        const Discovered(bbq, '192.168.1.23'),
        now,
      );
      expect(list, hasLength(1));
      expect(list.single.key, 'a1b2c3');
      expect(list.single.host, '192.168.1.23');
      expect(list.single.mode, DeviceMode.sta);
      expect(list.single.lastSeen, now);
    });

    test('updates a known id with its new address and keeps custom name', () {
      final saved = [
        Device.fromInfo(
          bbq,
          '192.168.1.23',
          DateTime(2026),
        ).copyWith(customName: 'Smoker'),
      ];
      const apInfo = DeviceInfo(
        id: 'a1b2c3',
        type: 'bbq',
        name: 'BBQ',
        mode: DeviceMode.ap,
      );
      final list = mergeDiscovered(
        saved,
        const Discovered(apInfo, '192.168.4.1'),
        now,
      );
      expect(list, hasLength(1));
      expect(list.single.host, '192.168.4.1');
      expect(list.single.mode, DeviceMode.ap);
      expect(list.single.displayName, 'Smoker');
      expect(list.single.name, 'BBQ');
    });

    test('upgrades a manual entry at the same host; device type wins', () {
      final saved = [
        Device.manual(host: '192.168.1.23', type: 'greenhouse', name: 'Mine'),
      ];
      final list = mergeDiscovered(
        saved,
        const Discovered(bbq, '192.168.1.23'),
        now,
      );
      expect(list, hasLength(1));
      expect(list.single.key, 'a1b2c3');
      expect(list.single.id, 'a1b2c3');
      expect(list.single.type, 'bbq');
    });

    test('does not hijack a different device that had the same IP', () {
      const other = DeviceInfo(id: '999999', type: 'greenhouse', name: 'GH');
      final saved = [Device.fromInfo(other, '192.168.1.23', DateTime(2026))];
      final list = mergeDiscovered(
        saved,
        const Discovered(bbq, '192.168.1.23'),
        now,
      );
      expect(list.map((d) => d.key), ['999999', 'a1b2c3']);
    });

    test('keeps order of other devices', () {
      final saved = [
        Device.manual(host: 'x', type: 'bbq'),
        Device.fromInfo(bbq, 'old', DateTime(2026)),
        Device.manual(host: 'y', type: 'bbq'),
      ];
      final list = mergeDiscovered(saved, const Discovered(bbq, 'new'), now);
      expect(list.map((d) => d.host), ['x', 'new', 'y']);
    });
  });

  test('Device JSON round trip', () {
    final device = Device.fromInfo(
      bbq,
      '192.168.1.23',
      now,
    ).copyWith(customName: 'Smoker');
    final copy = Device.fromJson(device.toJson())!;
    expect(copy.key, device.key);
    expect(copy.customName, 'Smoker');
    expect(copy.mode, DeviceMode.sta);
    expect(copy.ip, '192.168.1.23');
    expect(copy.lastSeen, now);
    expect(Device.fromJson({'nope': 1}), isNull);
  });
}
