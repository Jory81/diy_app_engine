import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'device.dart';

/// Persists the saved device list as JSON in shared_preferences.
class DeviceStore {
  static const _key = 'devices.v1';

  Future<List<Device>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(Device.fromJson)
          .nonNulls
          .toList();
    } on Object {
      return [];
    }
  }

  Future<void> save(List<Device> devices) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final d in devices) d.toJson()]),
    );
  }
}
