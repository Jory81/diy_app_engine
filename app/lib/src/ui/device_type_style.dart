import 'package:flutter/material.dart';

/// Icon, colour and label for a device type. Unknown (future) types get a
/// generic look and their raw type name as label.
class DeviceTypeStyle {
  const DeviceTypeStyle(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  /// Types the user can pick when adding a device manually.
  static const selectable = ['bbq', 'greenhouse'];

  /// Friendly name of a firmware mode, used in the "Switch mode" list.
  static String modeLabel(String mode) => switch (mode) {
    'bbq' => 'BBQ / smoker',
    _ => of(mode).label,
  };

  static DeviceTypeStyle of(String type) => switch (type) {
    'bbq' => const DeviceTypeStyle(
      'BBQ controller',
      Icons.local_fire_department,
      Color(0xFFF57C00),
    ),
    'greenhouse' => const DeviceTypeStyle(
      'Greenhouse',
      Icons.eco,
      Color(0xFF2E7D32),
    ),
    _ => DeviceTypeStyle(
      type.isEmpty || type == 'unknown'
          ? 'ESP device'
          : '${type[0].toUpperCase()}${type.substring(1)}',
      Icons.memory,
      const Color(0xFF546E7A),
    ),
  };
}
