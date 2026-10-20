import 'package:flutter/material.dart';

import 'src/demo/demo.dart';
import 'src/device_hub.dart';
import 'src/discovery/discovery_service.dart';
import 'src/models/device_store.dart';
import 'src/net/info_client.dart';
import 'src/net/network_binding.dart';
import 'src/ui/home_page.dart';
import 'src/ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final infoClient = InfoClient();
  final network = NetworkBinding();
  final hub = DeviceHub(
    store: DeviceStore(),
    infoClient: infoClient,
    network: network,
    discovery: DiscoveryService(
      infoClient: infoClient,
      network: network,
      extraHosts: demoEnabled ? demoHosts : const [],
    ),
    seed: demoEnabled ? demoSeed : const [],
  );
  runApp(EspDeviceHubApp(hub: hub));
}

class EspDeviceHubApp extends StatelessWidget {
  const EspDeviceHubApp({super.key, required this.hub});

  final DeviceHub hub;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP Device Hub',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: HomePage(hub: hub),
    );
  }
}
