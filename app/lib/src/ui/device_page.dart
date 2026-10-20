import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../device_hub.dart';
import '../models/device.dart';
import 'device_type_style.dart';
import 'dialogs.dart';

enum _Phase { locating, restarting, ready, failed }

/// Shows a device's own web UI full-screen in a WebView.
///
/// Before loading, the device is located: if it no longer answers at its
/// saved address, the network is re-scanned for its id.
class DevicePage extends StatefulWidget {
  const DevicePage({super.key, required this.hub, required this.device});

  final DeviceHub hub;
  final Device device;

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  late Device _device = widget.device;
  _Phase _phase = _Phase.locating;
  String? _error;
  WebViewController? _controller;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _locateAndLoad();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _locateAndLoad() async {
    setState(() {
      _phase = _Phase.locating;
      _error = null;
    });
    final found = await widget.hub.locate(_device);
    if (!mounted) return;
    if (found == null) {
      setState(() {
        _phase = _Phase.failed;
        _error =
            '"${_device.displayName}" did not answer at '
            '${_device.host} and was not found on this network.';
      });
      return;
    }
    _device = found;
    if (kIsWeb) {
      setState(() {
        _phase = _Phase.failed;
        _error = 'The in-app view is only available on the phone.';
      });
      return;
    }
    final controller = _controller ??= _createController();
    await controller.loadRequest(_device.uiUri);
    if (mounted) setState(() => _phase = _Phase.ready);
  }

  WebViewController _createController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => mounted ? setState(() => _progress = p) : null,
          onWebResourceError: (error) {
            if (error.isForMainFrame != true || !mounted) return;
            setState(() {
              _phase = _Phase.failed;
              _error = 'Could not load the device page: ${error.description}';
            });
          },
        ),
      );
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      // The BBQ page plays alarm.mp3 without a tap.
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    return controller;
  }

  Future<void> _switchMode() async {
    final mode = await showSwitchModeDialog(context, _device);
    if (mode == null || !mounted) return;
    setState(() => _phase = _Phase.restarting);
    final outcome = await widget.hub.switchMode(_device, mode);
    if (!mounted) return;
    if (outcome == SwitchOutcome.failed) {
      setState(() {
        _phase = _Phase.failed;
        _error = 'The device did not accept the mode switch.';
      });
      return;
    }
    // Same id in every mode: pick up the updated entry and reload its UI.
    _device = widget.hub.devices.firstWhere(
      (d) => d.key == _device.key,
      orElse: () => _device,
    );
    await _locateAndLoad();
  }

  Future<void> _openInBrowser() =>
      launchUrl(_device.uiUri, mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final style = DeviceTypeStyle.of(_device.type);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        titleSpacing: 0,
        title: Row(
          children: [
            Icon(style.icon, color: style.color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_device.displayName, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          if (_device.canSwitchMode)
            IconButton(
              tooltip: 'Switch mode',
              icon: const Icon(Icons.swap_horiz),
              onPressed: _phase == _Phase.restarting ? null : _switchMode,
            ),
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _phase == _Phase.ready
                ? () => _controller?.reload()
                : _locateAndLoad,
          ),
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(Icons.open_in_browser),
            onPressed: _openInBrowser,
          ),
        ],
        bottom: _phase == _Phase.ready && _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 2,
                ),
              )
            : null,
      ),
      body: switch (_phase) {
        _Phase.ready => WebViewWidget(controller: _controller!),
        _Phase.locating => _Message(
          icon: const CircularProgressIndicator(),
          title: 'Connecting to ${_device.displayName}…',
          text:
              'If it moved to another address, the app searches '
              'the network for it.',
        ),
        _Phase.restarting => _Message(
          icon: const CircularProgressIndicator(),
          title: 'Restarting…',
          text:
              '${_device.displayName} is switching mode. The page reloads '
              'when it is back (usually 5–10 s).',
        ),
        _Phase.failed => _Message(
          icon: Icon(
            Icons.portable_wifi_off,
            size: 56,
            color: Theme.of(context).colorScheme.error,
          ),
          title: 'Device not reachable',
          text:
              '${_error ?? ''}\n\nCheck that the phone is on the same '
              'Wi-Fi or on the ESP32-AP network.',
          actions: [
            FilledButton.icon(
              onPressed: _locateAndLoad,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
            OutlinedButton.icon(
              onPressed: _openInBrowser,
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Open in browser'),
            ),
          ],
        ),
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.text,
    this.actions = const [],
  });

  final Widget icon;
  final String title;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 24),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}
