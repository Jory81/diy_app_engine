import 'dart:io';

import 'package:esp_device_hub/src/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('appVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(appVersion, version);
  });
}
