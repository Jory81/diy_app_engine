import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device.dart';

/// Persists the saved device list as JSON in shared_preferences.
///
/// Storage problems never stop the app: the list then just isn't remembered.
class DeviceStore {
  static const _key = 'devices.v1';

  Future<List<Device>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(Device.fromJson)
          .nonNulls
          .toList();
    } on Object catch (e) {
      debugPrint('Could not load the saved devices: $e');
      return [];
    }
  }

  Future<void> save(List<Device> devices) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode([for (final d in devices) d.toJson()]),
      );
    } on Object catch (e) {
      debugPrint('Could not save the devices: $e');
    }
  }
}
