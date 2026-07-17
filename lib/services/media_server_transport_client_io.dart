import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

const bool supportsHttpForwardProxy = true;
const bool supportsCustomUserAgentHeader = true;

/// Creates a native client configured for an HTTP forward proxy.
http.Client createMediaServerClient(Uri? proxyUri) {
  if (proxyUri == null) {
    return http.Client();
  }

  final proxyPort = proxyUri.hasPort ? proxyUri.port : 80;
  final proxyHost =
      proxyUri.host.contains(':') ? '[${proxyUri.host}]' : proxyUri.host;
  final inner = HttpClient()..findProxy = (_) => 'PROXY $proxyHost:$proxyPort';
  return IOClient(inner);
}
