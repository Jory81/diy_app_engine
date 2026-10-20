import '../models/device.dart';
import '../models/device_info.dart';

/// One answer found during a scan: the device's info and where it answered.
class Discovered {
  const Discovered(this.info, this.host);

  final DeviceInfo info;
  final String host;
}

/// Keeps the first answer per device id (the same device is usually found
/// by several discovery methods at once).
List<Discovered> dedupeById(Iterable<Discovered> found) {
  final byId = <String, Discovered>{};
  for (final d in found) {
    byId.putIfAbsent(d.info.id, () => d);
  }
  return byId.values.toList();
}

/// Merges a discovered device into the saved list and returns the new list.
///
/// * A saved device with the same id is updated (new IP, mode, name, type),
///   keeping the user's custom name.
/// * Otherwise a manual entry with the same host is upgraded to the real id.
/// * Otherwise the device is appended.
List<Device> mergeDiscovered(
  List<Device> saved,
  Discovered found,
  DateTime now,
) {
  final info = found.info;
  var index = saved.indexWhere((d) => d.id == info.id);
  if (index < 0) {
    index = saved.indexWhere((d) => d.id == null && d.host == found.host);
  }
  if (index < 0) return [...saved, Device.fromInfo(info, found.host, now)];

  final updated = saved[index].updatedFrom(info, found.host, now);
  return [
    for (var i = 0; i < saved.length; i++)
      if (i == index) updated else if (saved[i].key != updated.key) saved[i],
  ];
}
