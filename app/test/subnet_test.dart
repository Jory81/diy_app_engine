import 'package:esp_device_hub/src/discovery/concurrency.dart';
import 'package:esp_device_hub/src/discovery/subnet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('subnetHosts', () {
    test('lists the /24 without the phone itself', () {
      final hosts = subnetHosts('192.168.1.40');
      expect(hosts, hasLength(253));
      expect(hosts.first, '192.168.1.1');
      expect(hosts.last, '192.168.1.254');
      expect(hosts, isNot(contains('192.168.1.40')));
      expect(hosts, isNot(contains('192.168.1.0')));
      expect(hosts, isNot(contains('192.168.1.255')));
    });

    test('skips excluded hosts', () {
      final hosts = subnetHosts(
        '192.168.4.2',
        exclude: {'192.168.4.1', '10.0.0.1'},
      );
      expect(hosts, hasLength(252));
      expect(hosts.first, '192.168.4.3');
    });

    test('returns nothing for invalid input', () {
      expect(subnetHosts(''), isEmpty);
      expect(subnetHosts('192.168.1'), isEmpty);
      expect(subnetHosts('192.168.1.300'), isEmpty);
      expect(subnetHosts('fe80::1'), isEmpty);
    });
  });

  test('normalizeHost strips scheme and path', () {
    expect(normalizeHost(' http://192.168.4.1/ '), '192.168.4.1');
    expect(normalizeHost('BBQ-A1B2C3.local/info'), 'bbq-a1b2c3.local');
    expect(normalizeHost('10.0.0.5:8080'), '10.0.0.5:8080');
  });

  test('forEachLimited respects the concurrency limit', () async {
    var running = 0;
    var peak = 0;
    final done = <int>[];
    await forEachLimited(List.generate(50, (i) => i), 4, (i) async {
      running++;
      peak = running > peak ? running : peak;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      running--;
      done.add(i);
    });
    expect(done, hasLength(50));
    expect(peak, 4);
  });
}
