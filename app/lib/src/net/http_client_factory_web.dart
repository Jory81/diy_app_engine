import 'package:http/http.dart' as http;

/// Browser builds (demo/screenshots only): the browser handles timeouts.
http.Client createHttpClient(Duration connectTimeout) => http.Client();
