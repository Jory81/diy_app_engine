import 'dart:convert';

/// How a device is connected: joined to a Wi-Fi network (`sta`) or running
/// its own soft-AP (`ap`).
enum DeviceMode {
  sta,
  ap,
  unknown;

  static DeviceMode parse(Object? value) => switch (value) {
    'sta' => DeviceMode.sta,
    'ap' => DeviceMode.ap,
    _ => DeviceMode.unknown,
  };
}

/// The answer of a device's `GET /info` endpoint (or its mDNS TXT records).
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.type,
    required this.name,
    this.version,
    this.mode = DeviceMode.unknown,
    this.ip,
    this.modes = const [],
  });

  /// Stable hardware id (last 3 MAC bytes, lower-case hex).
  final String id;

  /// Device type, e.g. `bbq` or `greenhouse`. Unknown types are kept as-is.
  final String type;
  final String name;
  final String? version;
  final DeviceMode mode;

  /// The IP address the device reports for itself.
  final String? ip;

  /// Modes a multi-mode firmware can run (e.g. `bbq`, `greenhouse`); empty
  /// on single-mode firmware. [type] is the active one.
  final List<String> modes;

  /// Whether the device can be switched to another mode.
  bool get canSwitchMode => modes.length > 1;

  /// Parses a `/info` JSON map. Returns null when the mandatory `id` is
  /// missing, so random web servers on the LAN are ignored.
  static DeviceInfo? fromJson(Map<String, dynamic> json) {
    final id = _text(json['id'])?.toLowerCase();
    if (id == null) return null;
    final type = _text(json['type'])?.toLowerCase() ?? 'unknown';
    return DeviceInfo(
      id: id,
      type: type,
      name: _text(json['name']) ?? 'ESP device $id',
      version: _text(json['version']),
      mode: DeviceMode.parse(json['mode']),
      ip: _text(json['ip']),
      modes: parseModes(json['modes']),
    );
  }

  /// Parses a `modes` list: lower-cased, without blanks and duplicates.
  /// Anything that is not a list yields an empty list.
  static List<String> parseModes(Object? value) {
    if (value is! List) return const [];
    return value
        .map(_text)
        .nonNulls
        .map((m) => m.toLowerCase())
        .toSet()
        .toList();
  }

  /// Parses a raw `/info` response body; null if it is not valid device JSON.
  static DeviceInfo? tryParse(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? fromJson(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  /// Builds an info object from mDNS TXT records (`type=`, `id=`, `name=`).
  static DeviceInfo? fromTxt(Map<String, String> txt, {String? ip}) =>
      fromJson({...txt, 'ip': ?ip});

  static String? _text(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}

/// The answer of `GET /mode` and `POST /mode`.
class ModeStatus {
  const ModeStatus({
    required this.mode,
    this.modes = const [],
    this.restarting = false,
  });

  final String mode;
  final List<String> modes;

  /// True right after a successful switch: the device is rebooting.
  final bool restarting;

  static ModeStatus? tryParse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;
      final mode = DeviceInfo._text(json['mode'])?.toLowerCase();
      if (mode == null) return null;
      return ModeStatus(
        mode: mode,
        modes: DeviceInfo.parseModes(json['modes']),
        restarting: json['restarting'] == true,
      );
    } on FormatException {
      return null;
    }
  }
}
