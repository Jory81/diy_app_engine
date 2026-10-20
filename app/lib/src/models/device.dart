import 'device_info.dart';

/// A device remembered by the app (persisted in shared_preferences).
class Device {
  const Device({
    required this.key,
    required this.type,
    required this.name,
    required this.host,
    this.id,
    this.customName,
    this.mode = DeviceMode.unknown,
    this.version,
    this.ip,
    this.lastSeen,
    this.modes = const [],
  });

  /// A manually added device whose `/info` has not answered yet.
  factory Device.manual({
    required String host,
    required String type,
    String? name,
  }) => Device(key: 'manual:$host', type: type, name: name ?? host, host: host);

  /// A device seen for the first time at [host].
  factory Device.fromInfo(DeviceInfo info, String host, DateTime seen) =>
      Device(
        key: info.id,
        id: info.id,
        type: info.type,
        name: info.name,
        host: host,
      ).updatedFrom(info, host, seen);

  /// Unique list key: the hardware id, or `manual:<host>` until it is known.
  final String key;

  /// Hardware id reported by `/info`; null for unverified manual entries.
  final String? id;
  final String type;

  /// Name reported by the device (or typed in when added manually).
  final String name;

  /// User-chosen name; overrides [name] when set.
  final String? customName;

  /// Address used to reach the device: an IP or hostname, optionally `:port`.
  final String host;
  final DeviceMode mode;
  final String? version;

  /// IP the device last reported about itself.
  final String? ip;
  final DateTime? lastSeen;

  /// Modes of a multi-mode firmware (see [DeviceInfo.modes]).
  final List<String> modes;

  bool get canSwitchMode => modes.length > 1;

  String get displayName => customName ?? name;

  /// The last-known IP to show to the user.
  String get displayAddress => ip ?? host;

  Uri get uiUri => Uri.parse('http://$host/');

  /// Applies a fresh `/info` answer received from [host]. The device's own
  /// type and name win over what was typed in; the custom name is kept.
  Device updatedFrom(DeviceInfo info, String host, DateTime seen) => Device(
    key: info.id,
    id: info.id,
    type: info.type,
    name: info.name,
    customName: customName,
    host: host,
    mode: info.mode,
    version: info.version,
    ip: info.ip,
    lastSeen: seen,
    modes: info.modes,
  );

  Device copyWith({String? customName, bool clearCustomName = false}) => Device(
    key: key,
    id: id,
    type: type,
    name: name,
    customName: clearCustomName ? null : customName ?? this.customName,
    host: host,
    mode: mode,
    version: version,
    ip: ip,
    lastSeen: lastSeen,
    modes: modes,
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'id': ?id,
    'type': type,
    'name': name,
    'customName': ?customName,
    'host': host,
    'mode': mode.name,
    'version': ?version,
    'ip': ?ip,
    'lastSeen': ?lastSeen?.toIso8601String(),
    if (modes.isNotEmpty) 'modes': modes,
  };

  static Device? fromJson(Map<String, dynamic> json) {
    final key = json['key'];
    final host = json['host'];
    if (key is! String || host is! String) return null;
    return Device(
      key: key,
      id: json['id'] as String?,
      type: json['type'] as String? ?? 'unknown',
      name: json['name'] as String? ?? host,
      customName: json['customName'] as String?,
      host: host,
      mode: DeviceMode.parse(json['mode']),
      version: json['version'] as String?,
      ip: json['ip'] as String?,
      lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? ''),
      modes: DeviceInfo.parseModes(json['modes']),
    );
  }
}
