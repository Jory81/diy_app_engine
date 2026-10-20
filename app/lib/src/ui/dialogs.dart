import 'package:flutter/material.dart';

import '../discovery/subnet.dart';
import '../models/device.dart';
import 'device_type_style.dart';

/// Asks for an address and a type; returns a manual [Device] or null.
Future<Device?> showAddDeviceDialog(BuildContext context) => showDialog<Device>(
  context: context,
  builder: (_) => const _AddDeviceDialog(),
);

class _AddDeviceDialog extends StatefulWidget {
  const _AddDeviceDialog();

  @override
  State<_AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<_AddDeviceDialog> {
  final _host = TextEditingController();
  final _name = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _type = DeviceTypeStyle.selectable.first;

  @override
  void dispose() {
    _host.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final name = _name.text.trim();
    Navigator.pop(
      context,
      Device.manual(
        host: normalizeHost(_host.text),
        type: _type,
        name: name.isEmpty ? DeviceTypeStyle.of(_type).label : name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add device'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _host,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'IP address or hostname',
                  hintText: '192.168.4.1 or bbq-a1b2c3.local',
                  prefixIcon: Icon(Icons.lan_outlined),
                ),
                validator: (value) => normalizeHost(value ?? '').isEmpty
                    ? 'Enter an address'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Name (optional)',
                  prefixIcon: Icon(Icons.label_outline),
                ),
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              Text('Type', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: [
                    for (final type in DeviceTypeStyle.selectable)
                      ButtonSegment(
                        value: type,
                        icon: Icon(DeviceTypeStyle.of(type).icon),
                        label: Text(
                          type == 'bbq'
                              ? 'BBQ'
                              : DeviceTypeStyle.of(type).label,
                        ),
                      ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'If the device answers, its own type and name are used.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

/// Asks for a new name; returns it (empty = reset to the device's name).
Future<String?> showRenameDialog(BuildContext context, Device device) =>
    showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(device: device),
    );

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.device});

  final Device device;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(
    text: widget.device.displayName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename device'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: 'Name',
          helperText: 'Leave empty to use "${widget.device.name}"',
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Lets the user pick another mode of a multi-mode device and confirms the
/// restart. Returns the chosen mode, or null if cancelled.
Future<String?> showSwitchModeDialog(
  BuildContext context,
  Device device,
) async {
  final mode = await showDialog<String>(
    context: context,
    builder: (_) => _SwitchModeDialog(device: device),
  );
  if (mode == null || !context.mounted) return null;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.restart_alt),
      title: Text('Switch to ${DeviceTypeStyle.modeLabel(mode)}?'),
      content: Text(
        '"${device.displayName}" restarts in the new mode. This takes about '
        '10 seconds; a running cook or program on the device stops.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Switch and restart'),
        ),
      ],
    ),
  );
  return confirmed == true ? mode : null;
}

class _SwitchModeDialog extends StatefulWidget {
  const _SwitchModeDialog({required this.device});

  final Device device;

  @override
  State<_SwitchModeDialog> createState() => _SwitchModeDialogState();
}

class _SwitchModeDialogState extends State<_SwitchModeDialog> {
  late String _mode = widget.device.type;

  @override
  Widget build(BuildContext context) {
    final current = widget.device.type;
    return AlertDialog(
      title: const Text('Switch mode'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: RadioGroup<String>(
        groupValue: _mode,
        onChanged: (mode) => setState(() => _mode = mode ?? _mode),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in widget.device.modes)
              RadioListTile<String>(
                value: mode,
                secondary: Icon(
                  DeviceTypeStyle.of(mode).icon,
                  color: DeviceTypeStyle.of(mode).color,
                ),
                title: Text(DeviceTypeStyle.modeLabel(mode)),
                subtitle: mode == current ? const Text('Current mode') : null,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _mode == current
              ? null
              : () => Navigator.pop(context, _mode),
          child: const Text('Switch'),
        ),
      ],
    );
  }
}
