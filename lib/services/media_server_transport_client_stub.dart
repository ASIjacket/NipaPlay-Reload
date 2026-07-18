import 'package:http/http.dart' as http;

const bool supportsHttpForwardProxy = false;
const bool supportsCustomUserAgentHeader = false;

/// Creates a browser client when no explicit forward proxy is requested.
http.Client createMediaServerClient(Uri? proxyUri) {
  if (proxyUri != null) {
    throw UnsupportedError(
      'HTTP forward proxies are not configurable in browser builds.',
    );
  }
  return http.Client();
}
