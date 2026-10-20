import 'package:esp_device_hub/src/models/device_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceInfo.tryParse', () {
    test('parses a full /info answer', () {
      final info = DeviceInfo.tryParse(
        '{"type":"bbq","name":"BBQ controller",'
        '"id":"A1B2C3","version":"2.0","mode":"ap","ip":"192.168.4.1"}',
      )!;
      expect(info.id, 'a1b2c3'); // normalised to lower case
      expect(info.type, 'bbq');
      expect(info.name, 'BBQ controller');
      expect(info.version, '2.0');
      expect(info.mode, DeviceMode.ap);
      expect(info.ip, '192.168.4.1');
    });

    test('keeps unknown future types', () {
      final info = DeviceInfo.tryParse(
        '{"type":"WeatherStation","id":"abcdef","mode":"sta"}',
      )!;
      expect(info.type, 'weatherstation');
      expect(info.mode, DeviceMode.sta);
      expect(info.name, 'ESP device abcdef');
    });

    test('tolerates missing optional fields and odd values', () {
      final info = DeviceInfo.tryParse(
        '{"id":"112233","mode":"mesh",'
        '"version":2}',
      )!;
      expect(info.type, 'unknown');
      expect(info.mode, DeviceMode.unknown);
      expect(info.version, '2');
      expect(info.ip, isNull);
    });

    test('rejects non-device answers', () {
      expect(DeviceInfo.tryParse('<html>router login</html>'), isNull);
      expect(DeviceInfo.tryParse('[1,2,3]'), isNull);
      expect(DeviceInfo.tryParse('{"type":"bbq"}'), isNull); // no id
      expect(DeviceInfo.tryParse('{"id":"  "}'), isNull);
      expect(DeviceInfo.tryParse(''), isNull);
    });
  });

  test('DeviceInfo.fromTxt reads mDNS TXT records', () {
    final info = DeviceInfo.fromTxt({
      'type': 'greenhouse',
      'id': 'd4e5f6',
      'name': 'Greenhouse',
    }, ip: '192.168.1.40')!;
    expect(info.id, 'd4e5f6');
    expect(info.type, 'greenhouse');
    expect(info.ip, '192.168.1.40');
    expect(info.mode, DeviceMode.unknown);
  });
}
