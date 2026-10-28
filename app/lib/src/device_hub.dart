import 'dart:async';

import 'package:flutter/foundation.dart';

import 'discovery/concurrency.dart';
import 'discovery/discovery_service.dart';
import 'discovery/merge.dart';
import 'models/device.dart';
import 'models/device_store.dart';
import 'net/info_client.dart';
import 'net/network_binding.dart';

/// Result of [DeviceHub.switchMode].
enum SwitchOutcome {
  /// The device restarted and now reports the new mode.
  switched,

  /// The device refused or did not answer the `POST /mode`.
  failed,

  /// The switch was accepted but the device did not come back in time.
  notConfirmed,
}

/// App state: the saved devices, their online status and scanning.
class DeviceHub extends ChangeNotifier {
  DeviceHub({
    required this.store,
    required this.infoClient,
    required this.discovery,
    required this.network,
    this.seed = const [],
    this.modePollInterval = const Duration(seconds: 2),
    this.modeSwitchTimeout = const Duration(seconds: 60),
  });

  final DeviceStore store;
  final InfoClient infoClient;
  final DiscoveryService discovery;
  final NetworkBinding network;

  /// Devices used when nothing is saved yet (demo build only).
  final List<Device> seed;

  /// How often `/info` is polled while a device restarts into a new mode,
  /// and for how long before falling back to re-discovery by id.
  final Duration modePollInterval;
  final Duration modeSwitchTimeout;

  List<Device> _devices = [];
  final Map<String, bool> _online = {};
  final Set<String> _switching = {};
  bool _scanning = false;
  Future<Set<String>>? _currentScan;
  WifiDetails? _wifi;

  /// Saved devices, sorted by name for a stable list.
  List<Device> get devices => List.unmodifiable(
    _devices.toList()..sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    ),
  );
  bool get scanning => _scanning;
  WifiDetails? get wifi => _wifi;

  /// null = not checked yet.
  bool? isOnline(Device device) => _online[device.key];

  /// Whether [device] is restarting into another mode right now.
  bool isSwitching(Device device) => _switching.contains(device.key);

  Future<void> load() async {
    _devices = await store.load();
    if (_devices.isEmpty && seed.isNotEmpty) _devices = [...seed];
    notifyListeners();
  }

  /// Runs a full discovery; concurrent calls share the running scan.
  /// Returns the ids of the devices that answered.
  Future<Set<String>> scan() => _currentScan ??= _scan().whenComplete(() {
    _currentScan = null;
  });

  Future<Set<String>> _scan() async {
    _scanning = true;
    notifyListeners();
    final foundIds = <String>{};
    try {
      final hosts = _devices.map((d) => d.host).toList();
      await for (final found in discovery.discover(knownHosts: hosts)) {
        foundIds.add(found.info.id);
        _applyFound(found);
      }
      // Every saved host was probed, so whatever did not answer is offline.
      for (final d in _devices) {
        if (!foundIds.contains(d.key)) _online[d.key] = false;
      }
      _wifi = await network.wifiDetails();
    } finally {
      _scanning = false;
      notifyListeners();
      await _save();
    }
    return foundIds;
  }

  /// Polls `/info` of every saved device to update online/offline.
  Future<void> refreshStatus() async {
    _wifi = await network.wifiDetails();
    var changed = false;
    await forEachLimited(List.of(_devices), 8, (device) async {
      final info = await infoClient.fetch(
        device.host,
        timeout: const Duration(seconds: 2),
      );
      // A scan may have found the device at another address meanwhile: then
      // this answer (or silence) from the old address says nothing about it.
      if (_byKey(device.key)?.host != device.host) return;
      // A different id at the same IP means DHCP gave it to another device.
      final isSame =
          info != null && (device.id == null || device.id == info.id);
      _online[device.key] = isSame;
      if (isSame) {
        _applyFound(Discovered(info, device.host), notify: false);
        changed = true;
      }
    });
    notifyListeners();
    if (changed) await _save();
  }

  /// Makes sure [device] answers at its saved host. If not, re-discovers it
  /// by id (it may have a new DHCP address or switched to soft-AP).
  /// Returns the up-to-date device, or null if it cannot be found.
  Future<Device?> locate(Device device) async {
    // The saved list may already know a newer address (from a scan).
    final current = _byKey(device.key) ?? device;
    final info = await infoClient.fetch(
      current.host,
      timeout: const Duration(seconds: 3),
    );
    if (info != null && (current.id == null || info.id == current.id)) {
      _applyFound(Discovered(info, current.host));
      await _save();
      return _byKey(info.id);
    }
    final id = current.id;
    if (id == null) return null;
    final foundIds = await scan();
    return foundIds.contains(id) ? _byKey(id) : null;
  }

  /// Switches a multi-mode device to [mode] (`POST /mode`), then waits for
  /// it to restart and report the new type. The id stays the same across
  /// modes, so the saved entry (and its custom name) is updated in place.
  Future<SwitchOutcome> switchMode(Device device, String mode) async {
    final id = device.id;
    if (id == null) return SwitchOutcome.failed;
    _switching.add(device.key);
    notifyListeners();
    try {
      final status = await infoClient.setMode(device.host, mode);
      if (status == null || status.mode != mode) return SwitchOutcome.failed;

      final attempts =
          modeSwitchTimeout.inMilliseconds ~/ modePollInterval.inMilliseconds;
      for (var i = 0; i < attempts; i++) {
        await Future<void>.delayed(modePollInterval);
        final info = await infoClient.fetch(
          device.host,
          timeout: const Duration(seconds: 2),
        );
        if (info != null && info.id == id && info.type == mode) {
          _applyFound(Discovered(info, device.host));
          await _save();
          return SwitchOutcome.switched;
        }
      }
      // It may have come back at another address: look for it by id.
      final foundIds = await scan();
      final found = _byKey(id);
      return found?.type == mode && foundIds.contains(id)
          ? SwitchOutcome.switched
          : SwitchOutcome.notConfirmed;
    } finally {
      _switching.remove(device.key);
      notifyListeners();
    }
  }

  Future<Device> addManual(Device device) async {
    _devices = [..._devices.where((d) => d.key != device.key), device];
    notifyListeners();
    await _save();
    final info = await infoClient.fetch(device.host);
    _online[device.key] = info != null;
    if (info != null) _applyFound(Discovered(info, device.host));
    notifyListeners();
    await _save();
    return (info == null ? null : _byKey(info.id)) ?? device;
  }

  Future<void> rename(Device device, String newName) async {
    final name = newName.trim();
    _replace(
      device.copyWith(
        customName: name,
        clearCustomName: name.isEmpty || name == device.name,
      ),
    );
    await _save();
  }

  Future<void> remove(Device device) async {
    _devices = _devices.where((d) => d.key != device.key).toList();
    notifyListeners();
    await _save();
  }

  /// Puts a removed device back (undo).
  Future<void> restore(Device device) async {
    _devices = [..._devices.where((d) => d.key != device.key), device];
    notifyListeners();
    await _save();
  }

  void _applyFound(Discovered found, {bool notify = true}) {
    final oldKeys = _devices.map((d) => d.key).toSet();
    _devices = mergeDiscovered(_devices, found, DateTime.now());
    _online[found.info.id] = true;
    // A manual entry upgraded to its real id keeps no stale status.
    _online.removeWhere(
      (key, _) => oldKeys.contains(key) && !_devices.any((d) => d.key == key),
    );
    if (notify) notifyListeners();
  }

  void _replace(Device device) {
    _devices = [for (final d in _devices) d.key == device.key ? device : d];
    notifyListeners();
  }

  Device? _byKey(String key) => _devices.where((d) => d.key == key).firstOrNull;

  Future<void> _save() => store.save(_devices);
}
