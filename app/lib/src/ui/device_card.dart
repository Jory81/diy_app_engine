import 'package:flutter/material.dart';

import '../models/device.dart';
import '../models/device_info.dart';
import 'device_type_style.dart';

enum DeviceAction { switchMode, rename, openInBrowser, delete }

/// One saved device in the list.
class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.device,
    required this.online,
    required this.onTap,
    required this.onAction,
    this.switching = false,
  });

  final Device device;

  /// null while the first status check is running.
  final bool? online;
  final VoidCallback onTap;
  final ValueChanged<DeviceAction> onAction;

  /// True while the device restarts into another mode.
  final bool switching;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = DeviceTypeStyle.of(device.type);
    final dimmed = online == false && !switching;
    final subtitle = [
      if (style.label != device.displayName) style.label,
      device.displayAddress,
    ].join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 4, 16),
          child: Row(
            children: [
              _TypeAvatar(style: style, dimmed: dimmed),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (switching)
                          const _RestartingBadge()
                        else
                          _StatusBadge(online: online),
                        if (device.mode != DeviceMode.unknown)
                          _ModeBadge(mode: device.mode),
                      ],
                    ),
                  ],
                ),
              ),
              _ActionMenu(
                onAction: onAction,
                canSwitchMode: device.canSwitchMode && !switching,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeAvatar extends StatelessWidget {
  const _TypeAvatar({required this.style, required this.dimmed});

  final DeviceTypeStyle style;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = dimmed
        ? theme.disabledColor
        : theme.brightness == Brightness.dark
        ? Color.lerp(style.color, Colors.white, 0.3)!
        : style.color;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(style.icon, color: color, size: 30),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.online});

  final bool? online;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return switch (online) {
      true => _Badge(
        icon: Icons.circle,
        label: 'Online',
        color: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
      ),
      false => _Badge(
        icon: Icons.circle_outlined,
        label: 'Offline',
        color: scheme.onSurfaceVariant,
      ),
      null => _Badge(
        icon: Icons.more_horiz,
        label: 'Checking',
        color: scheme.onSurfaceVariant,
      ),
    };
  }
}

class _RestartingBadge extends StatelessWidget {
  const _RestartingBadge();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            'Restarting…',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.mode});

  final DeviceMode mode;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return mode == DeviceMode.ap
        ? _Badge(icon: Icons.wifi_tethering, label: 'Soft-AP', color: color)
        : _Badge(icon: Icons.wifi, label: 'Wi-Fi', color: color);
  }
}

class _ActionMenu extends StatelessWidget {
  const _ActionMenu({required this.onAction, required this.canSwitchMode});

  final ValueChanged<DeviceAction> onAction;
  final bool canSwitchMode;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<DeviceAction>(
      tooltip: 'More',
      onSelected: onAction,
      itemBuilder: (context) => [
        if (canSwitchMode)
          const PopupMenuItem(
            value: DeviceAction.switchMode,
            child: ListTile(
              leading: Icon(Icons.swap_horiz),
              title: Text('Switch mode'),
            ),
          ),
        const PopupMenuItem(
          value: DeviceAction.rename,
          child: ListTile(leading: Icon(Icons.edit), title: Text('Rename')),
        ),
        const PopupMenuItem(
          value: DeviceAction.openInBrowser,
          child: ListTile(
            leading: Icon(Icons.open_in_browser),
            title: Text('Open in browser'),
          ),
        ),
        const PopupMenuItem(
          value: DeviceAction.delete,
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Delete'),
          ),
        ),
      ],
    );
  }
}
