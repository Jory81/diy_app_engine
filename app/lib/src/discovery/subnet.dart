/// Parses a dotted IPv4 address; null if [ip] is not one.
List<int>? parseIpv4(String ip) {
  final parts = ip.trim().split('.');
  if (parts.length != 4) return null;
  final octets = parts.map(int.tryParse).toList();
  if (octets.any((o) => o == null || o < 0 || o > 255)) return null;
  return octets.cast<int>();
}

/// All host addresses of the /24 network that [ip] belongs to (x.y.z.1 to
/// x.y.z.254), without [ip] itself and without [exclude].
///
/// Larger networks are deliberately limited to the phone's own /24 to keep
/// the sweep fast; home routers and the ESP32 soft-AP both use a /24.
List<String> subnetHosts(String ip, {Set<String> exclude = const {}}) {
  final octets = parseIpv4(ip);
  if (octets == null) return const [];
  final prefix = octets.take(3).join('.');
  return [for (var last = 1; last <= 254; last++) '$prefix.$last']
      .where((host) => host != ip && !exclude.contains(host))
      .toList();
}

/// Normalises what a user types as a device address: strips a scheme,
/// path and surrounding whitespace (`http://192.168.4.1/` → `192.168.4.1`).
String normalizeHost(String input) {
  var host = input.trim();
  host = host.replaceFirst(RegExp(r'^[a-zA-Z]+://'), '');
  final slash = host.indexOf('/');
  if (slash >= 0) host = host.substring(0, slash);
  return host.toLowerCase();
}
