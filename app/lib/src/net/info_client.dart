import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/device_info.dart';
import 'http_client_factory.dart';

/// Fetches `GET http://<host>/info` from devices.
class InfoClient {
  InfoClient({http.Client? client, http.Client? patientClient})
    : _client = client ?? createHttpClient(const Duration(milliseconds: 700)),
      _patientClient =
          patientClient ??
          client ??
          createHttpClient(const Duration(seconds: 3));

  /// Gives up connecting after 0.7 s: fine for sweeping a whole subnet.
  final http.Client _client;

  /// Waits up to 3 s for the connection: for a device that is known to be
  /// there but slow to answer (busy, or the phone's Wi-Fi just woke up).
  final http.Client _patientClient;

  /// Returns the parsed info, or null if the host does not answer in time
  /// or is not an ESP device.
  Future<DeviceInfo?> fetch(
    String host, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) async => (await probe(host, timeout: timeout)).info;

  /// Like [fetch], but also says why there is no answer (shown to the user).
  Future<InfoResult> probe(
    String host, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    final client = timeout > const Duration(milliseconds: 1500)
        ? _patientClient
        : _client;
    try {
      final response = await client
          .get(Uri.parse('http://$host/info'))
          .timeout(timeout);
      if (response.statusCode != 200) {
        return InfoResult.failed('$host answered HTTP ${response.statusCode}');
      }
      final info = DeviceInfo.tryParse(response.body);
      return info == null
          ? InfoResult.failed('$host answered, but not as an ESP device')
          : InfoResult(info);
    } on TimeoutException {
      return InfoResult.failed(
        '$host did not answer within ${timeout.inSeconds} s',
      );
    } on Object catch (e) {
      return InfoResult.failed('$host: ${_short(e)}');
    }
  }

  static String _short(Object e) {
    final text = e.toString();
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
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

/// The outcome of [InfoClient.probe]: the device info, or why there is none.
class InfoResult {
  const InfoResult(this.info) : problem = null;
  const InfoResult.failed(this.problem) : info = null;

  final DeviceInfo? info;
  final String? problem;
}
