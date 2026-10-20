import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../device_hub.dart';
import '../models/device.dart';
import 'device_card.dart';
import 'device_page.dart';
import 'device_type_style.dart';
import 'dialogs.dart';

/// The saved-device list with scanning and online status.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.hub});

  final DeviceHub hub;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _pollInterval = Duration(seconds: 10);
  Timer? _poll;

  DeviceHub get hub => widget.hub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    await hub.load();
    _startPolling();
    await hub.refreshStatus();
    await hub.scan();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      hub.refreshStatus();
    } else if (state == AppLifecycleState.paused) {
      _stopPolling();
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollInterval, (_) => hub.refreshStatus());
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _open(Device device) async {
    _stopPolling(); // only poll while the list is visible
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DevicePage(hub: hub, device: device),
      ),
    );
    if (!mounted) return;
    _startPolling();
    unawaited(hub.refreshStatus());
  }

  Future<void> _add() async {
    final device = await showAddDeviceDialog(context);
    if (device == null) return;
    final saved = await hub.addManual(device);
    if (!mounted) return;
    final online = hub.isOnline(saved) == true;
    _snack(
      online
          ? 'Found "${saved.displayName}"'
          : 'Saved. "${saved.host}" did not answer yet.',
    );
  }

  Future<void> _onAction(Device device, DeviceAction action) async {
    switch (action) {
      case DeviceAction.switchMode:
        await _switchMode(device);
      case DeviceAction.rename:
        final name = await showRenameDialog(context, device);
        if (name != null) await hub.rename(device, name);
      case DeviceAction.openInBrowser:
        await launchUrl(device.uiUri, mode: LaunchMode.externalApplication);
      case DeviceAction.delete:
        await hub.remove(device);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${device.displayName}"'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => hub.restore(device),
            ),
          ),
        );
    }
  }

  Future<void> _switchMode(Device device) async {
    final mode = await showSwitchModeDialog(context, device);
    if (mode == null) return;
    final label = DeviceTypeStyle.modeLabel(mode);
    final outcome = await hub.switchMode(device, mode);
    if (!mounted) return;
    _snack(switch (outcome) {
      SwitchOutcome.switched => '"${device.displayName}" is now in $label mode',
      SwitchOutcome.failed => 'The device did not accept the mode switch',
      SwitchOutcome.notConfirmed =>
        'Switched, but the device has not come back yet. Pull to refresh.',
    });
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: hub,
      builder: (context, _) {
        final devices = hub.devices;
        return Scaffold(
          appBar: AppBar(
            title: const Text('ESP Device Hub'),
            actions: [
              IconButton(
                tooltip: 'Scan',
                onPressed: hub.scanning ? null : hub.scan,
                icon: const Icon(Icons.radar),
              ),
              const SizedBox(width: 4),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(3),
              child: hub.scanning
                  ? const LinearProgressIndicator(minHeight: 3)
                  : const SizedBox(height: 3),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: const Text('Add device'),
          ),
          body: RefreshIndicator(
            onRefresh: hub.scan,
            child: devices.isEmpty
                ? _EmptyState(scanning: hub.scanning, onScan: hub.scan)
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: devices.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      if (i == 0) return _NetworkHeader(hub: hub);
                      final device = devices[i - 1];
                      return DeviceCard(
                        key: ValueKey(device.key),
                        device: device,
                        online: hub.isOnline(device),
                        switching: hub.isSwitching(device),
                        onTap: () => _open(device),
                        onAction: (a) => _onAction(device, a),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}

/// Small line above the list: scanning state and the phone's Wi-Fi.
class _NetworkHeader extends StatelessWidget {
  const _NetworkHeader({required this.hub});

  final DeviceHub hub;

  @override
  Widget build(BuildContext context) {
    final wifi = hub.wifi;
    final count = hub.devices.where((d) => hub.isOnline(d) == true).length;
    final parts = [
      hub.scanning ? 'Scanning…' : '$count of ${hub.devices.length} online',
      if (wifi?.ip != null)
        'Phone ${wifi!.ip}${wifi.hasInternet ? '' : ' (no internet)'}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        parts.join(' · '),
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scanning, required this.onScan});

  final bool scanning;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.wifi_find,
                    size: 48,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  scanning ? 'Looking for devices…' : 'No devices yet',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'Connect your phone to your home Wi-Fi or to the device\'s '
                  'ESP32-AP network, then tap Scan.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: scanning ? null : onScan,
                  icon: const Icon(Icons.radar),
                  label: const Text('Scan'),
                ),
                const SizedBox(height: 64),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
