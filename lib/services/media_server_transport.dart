import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/utils/http_user_agent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media_server_transport_client_stub.dart'
    if (dart.library.io) 'media_server_transport_client_io.dart' as platform;

/// Sends Emby/Jellyfin HTTP requests through one configurable transport.
class MediaServerTransport {
  static String? _httpProxyOverride;
  static String? _connectionUserAgentCache;

  static const String defaultConnectionUserAgent = defaultNipaPlayUserAgent;

  MediaServerTransport({
    String httpProxy = '',
    String userAgent = defaultConnectionUserAgent,
  })  : _client = platform.createMediaServerClient(
          validateHttpProxy(httpProxy),
        ),
        _userAgent = _resolveUserAgent(userAgent);

  /// Creates a transport that owns [client] and closes it on timeout or close.
  MediaServerTransport.fromClient(
    http.Client client, {
    String userAgent = defaultConnectionUserAgent,
  })  : _client = client,
        _userAgent = _resolveUserAgent(userAgent);

  /// Updates the proxy used by transports created for subsequent requests.
  static void setHttpProxyOverride(String value) {
    _httpProxyOverride = value.trim();
  }

  /// Clears the runtime override so subsequent transports read preferences.
  static void clearHttpProxyOverride() {
    _httpProxyOverride = null;
  }

  /// Persists the User-Agent shared by all Emby/Jellyfin request types.
  ///
  /// An empty value restores [defaultConnectionUserAgent].
  static Future<String> saveConnectionUserAgent(String userAgent) async {
    final sanitized = sanitizeHttpUserAgent(userAgent);
    _connectionUserAgentCache = sanitized;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        SettingsKeys.mediaServerConnectionUserAgent,
        sanitized,
      );
    } catch (_) {}
    return sanitized;
  }

  /// Returns the stored value; an empty value means to use the app default.
  static Future<String> getStoredConnectionUserAgent() async {
    final cached = _connectionUserAgentCache;
    if (cached != null) {
      return cached;
    }
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = sanitizeHttpUserAgent(
        preferences.getString(SettingsKeys.mediaServerConnectionUserAgent) ??
            '',
      );
      _connectionUserAgentCache = stored;
      return stored;
    } catch (_) {
      _connectionUserAgentCache = '';
      return '';
    }
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

  /// Creates a one-request transport from the current persisted settings.
  static Future<MediaServerTransport> fromStoredSettings() async {
    if (!platform.supportsHttpForwardProxy) {
      return MediaServerTransport();
    }
    final storedUserAgent = await getStoredConnectionUserAgent();
    final userAgent = _resolveUserAgent(storedUserAgent);
    final override = _httpProxyOverride;
    if (override != null) {
      return MediaServerTransport(
        httpProxy: override,
        userAgent: userAgent,
      );
    }

    String proxy;
    try {
      final preferences = await SharedPreferences.getInstance();
      proxy =
          (preferences.getString(SettingsKeys.playerHttpProxy) ?? '').trim();
    } catch (_) {
      proxy = '';
    }
    return MediaServerTransport(
      httpProxy: proxy,
      userAgent: userAgent,
    );
  }

  final http.Client _client;
  final String _userAgent;

  static String _resolveUserAgent(String value) {
    final sanitized = sanitizeHttpUserAgent(value);
    return sanitized.isEmpty ? defaultConnectionUserAgent : sanitized;
  }

  /// Sends [request] and fully buffers its response within [timeout].
  ///
  /// A timeout closes this transport, so it cannot be reused afterwards.
  Future<http.Response> send(
    http.BaseRequest request, {
    required Duration timeout,
  }) async {
    final hasUserAgent = request.headers.keys.any(
      (header) => header.toLowerCase() == 'user-agent',
    );
    if (platform.supportsCustomUserAgentHeader && !hasUserAgent) {
      request.headers['User-Agent'] = _userAgent;
    }
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
