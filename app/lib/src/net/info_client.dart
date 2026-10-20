import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/device_info.dart';
import 'http_client_factory.dart';

/// Fetches `GET http://<host>/info` from devices.
class InfoClient {
  InfoClient({http.Client? client})
    : _client = client ?? createHttpClient(const Duration(milliseconds: 700));

  final http.Client _client;

  /// Returns the parsed info, or null if the host does not answer in time
  /// or is not an ESP device.
  Future<DeviceInfo?> fetch(
    String host, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    try {
      final response = await _client
          .get(Uri.parse('http://$host/info'))
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      return DeviceInfo.tryParse(response.body);
    } on Object {
      return null; // timeouts, refused connections, bad hosts …
    }
  }

  /// `POST http://<host>/mode` with form body `set=<mode>`. Returns the
  /// device's answer, or null if the request failed.
  Future<ModeStatus?> setMode(String host, String mode) async {
    try {
      final response = await _client
          .post(
            Uri.parse('http://$host/mode'),
            body: {'set': mode}, // sent as application/x-www-form-urlencoded
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      return ModeStatus.tryParse(response.body);
    } on Object {
      return null;
    }
  }
}
