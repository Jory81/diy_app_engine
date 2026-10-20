// Demo data for screenshots and browser previews ONLY.
//
// Active only when built with `--dart-define=DEMO=true`; production builds
// never reference these values (see `main.dart`). The hosts point at the
// mock server in `tool/mock_devices.mjs`.
import '../models/device.dart';
import '../models/device_info.dart';

const demoEnabled = bool.fromEnvironment('DEMO');

/// Mock device endpoints probed during a demo scan.
const demoHosts = ['localhost:8081', 'localhost:8082'];

/// Saved devices pre-filled in the demo; the third one has no mock server
/// behind it, so it shows up as offline.
final demoSeed = [
  const Device(
    key: '0f1e2d',
    id: '0f1e2d',
    type: 'bbq',
    name: 'BBQ controller',
    customName: 'Smoker (garage)',
    host: 'localhost:8083',
    mode: DeviceMode.sta,
    version: '2.0',
    ip: '192.168.1.57',
  ),
];
