import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// A client whose TCP connect really aborts after [connectTimeout], so a
/// subnet sweep does not pile up hanging sockets to non-existent hosts.
http.Client createHttpClient(Duration connectTimeout) =>
    IOClient(HttpClient()..connectionTimeout = connectTimeout);
