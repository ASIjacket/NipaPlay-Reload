import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media_server_transport_client_stub.dart'
    if (dart.library.io) 'media_server_transport_client_io.dart' as platform;

/// Sends Emby/Jellyfin HTTP requests through one configurable transport.
class MediaServerTransport {
  static String? _httpProxyOverride;

  /// Creates a transport that uses [httpProxy] when it is non-empty.
  ///
  /// Browser builds reject non-empty proxy settings because browsers do not
  /// expose per-client forward-proxy configuration.
  MediaServerTransport({String httpProxy = ''})
      : _client =
            platform.createMediaServerClient(validateHttpProxy(httpProxy));

  /// Creates a transport that owns [client] and closes it on timeout or close.
  MediaServerTransport.fromClient(http.Client client) : _client = client;

  /// Updates the proxy used by transports created for subsequent requests.
  static void setHttpProxyOverride(String value) {
    _httpProxyOverride = value.trim();
  }

  /// Clears the runtime override so subsequent transports read preferences.
  static void clearHttpProxyOverride() {
    _httpProxyOverride = null;
  }

  /// Validates and parses an HTTP forward-proxy endpoint.
  ///
  /// Returns `null` when [value] is empty. Proxy authentication and URL
  /// path/query/fragment components are intentionally unsupported.
  static Uri? validateHttpProxy(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    int port;
    try {
      port = uri?.port ?? 0;
    } on FormatException {
      throw FormatException('Invalid HTTP proxy port.', value);
    }
    if (uri == null ||
        uri.scheme.toLowerCase() != 'http' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment ||
        port < 1 ||
        port > 65535) {
      throw FormatException(
        'HTTP proxy must be an http:// host with an optional valid port.',
        value,
      );
    }
    return uri;
  }

  /// Creates a one-request transport from the current persisted proxy setting.
  static Future<MediaServerTransport> fromStoredSettings() async {
    if (!platform.supportsHttpForwardProxy) {
      return MediaServerTransport();
    }
    final override = _httpProxyOverride;
    if (override != null) {
      return MediaServerTransport(httpProxy: override);
    }

    String proxy;
    try {
      final preferences = await SharedPreferences.getInstance();
      proxy =
          (preferences.getString(SettingsKeys.playerHttpProxy) ?? '').trim();
    } catch (_) {
      proxy = '';
    }
    return MediaServerTransport(httpProxy: proxy);
  }

  final http.Client _client;

  /// Sends [request] and fully buffers its response within [timeout].
  ///
  /// A timeout closes this transport, so it cannot be reused afterwards.
  Future<http.Response> send(
    http.BaseRequest request, {
    required Duration timeout,
  }) async {
    try {
      return await (() async {
        final streamedResponse = await _client.send(request);
        return http.Response.fromStream(streamedResponse);
      })()
          .timeout(timeout);
    } on TimeoutException {
      _client.close();
      rethrow;
    }
  }

  /// Releases sockets owned by this transport.
  void close() => _client.close();
}
